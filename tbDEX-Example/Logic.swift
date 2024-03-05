import Foundation
import TypeID
import tbDEX
import Web5

/// Set this to whatever the exemplar app spits out for PFI DID
let pfiDIDURI = "did:dht:rf533jrdwgmtg5o1wrwbfxnr4d3j9yecpubhc4a13we9cjot4t7o"

/// Set this to whatever the exemplar app spits out for output in `example-issue-credential`
let claim = "eyJ0eXAiOiJKV1QiLCJhbGciOiJFZERTQSIsImtpZCI6ImRpZDpkaHQ6em50aXV6YzlxNm54cmg2MzFmaTRrZmJqYmZkOGNlaDQ2bXhxcHprYjQ3bXh6enJ5dW96byMwIn0.eyJ2YyI6eyJAY29udGV4dCI6WyJodHRwczovL3d3dy53My5vcmcvMjAxOC9jcmVkZW50aWFscy92MSJdLCJ0eXBlIjpbIlZlcmlmaWFibGVDcmVkZW50aWFsIiwiU2FuY3Rpb25DcmVkZW50aWFsIl0sImlkIjoidXJuOnV1aWQ6ZTk0MmNjOTUtZGVkNC00Y2Q1LWE3YzctZjNlNGJmN2NjZDUzIiwiaXNzdWVyIjoiZGlkOmRodDp6bnRpdXpjOXE2bnhyaDYzMWZpNGtmYmpiZmQ4Y2VoNDZteHFwemtiNDdteHp6cnl1b3pvIiwiaXNzdWFuY2VEYXRlIjoiMjAyNC0wMi0yMVQxNzoxMzoxNloiLCJjcmVkZW50aWFsU3ViamVjdCI6eyJpZCI6ImRpZDpqd2s6ZXlKcmRIa2lPaUpQUzFBaUxDSnJhV1FpT2lKUGJHNXpVRGhrWnpCVE56Tm9Ta3BmWVdrNGRtODNkVmh4Y25OdU5IVlNTamhDU0RKelZIZHVTM2hCSWl3aVkzSjJJam9pUldReU5UVXhPU0lzSW5naU9pSlJORkpQWldOT1RqQXdhRjlFYUU1eVVXRkpZbE4xYVdGM1JUbEVYM0pXZWxveWNrNHRhVlV3Ylc1Sklpd2lZV3huSWpvaVJXUkVVMEVpZlEiLCJiZWVwIjoiYm9vcCJ9fSwiaXNzIjoiZGlkOmRodDp6bnRpdXpjOXE2bnhyaDYzMWZpNGtmYmpiZmQ4Y2VoNDZteHFwemtiNDdteHp6cnl1b3pvIiwic3ViIjoiZGlkOmp3azpleUpyZEhraU9pSlBTMUFpTENKcmFXUWlPaUpQYkc1elVEaGtaekJUTnpOb1NrcGZZV2s0ZG04M2RWaHhjbk51TkhWU1NqaENTREp6VkhkdVMzaEJJaXdpWTNKMklqb2lSV1F5TlRVeE9TSXNJbmdpT2lKUk5GSlBaV05PVGpBd2FGOUVhRTV5VVdGSllsTjFhV0YzUlRsRVgzSldlbG95Y2s0dGFWVXdiVzVKSWl3aVlXeG5Jam9pUldSRVUwRWlmUSJ9.Idj7BJzEKPNGlQ-G3RmFbk5M6Bvzvp5V55o-oYUsBdEiC8tIkC_XK3IQGlHr3TXIHe__PRxdjRbGH73HK-YRCQ"

// Creates or loads a `BearerDID` from disk
func createOrLoadDid() throws -> BearerDID {
    let userDefaultsKey = "did"

    if let existingDIDData = UserDefaults.standard.value(forKey: userDefaultsKey) as? Data,
       let portableDID = try? JSONDecoder().decode(PortableDID.self, from: existingDIDData) {
        // Existing DID exists on disk, use it
        let did = try DIDJWK.import(portableDID: portableDID)

        // Print it to console
        print("Loaded DID: \(did.uri)")

        return did
    } else {
        // Create a new DID
        let did = try DIDJWK.create(
            keyManager: InMemoryKeyManager(),
            options: .init(algorithm: .ed25519)
        )

        // Save it to disk
        let portableDID = try did.export()
        UserDefaults.standard.setValue(try JSONEncoder().encode(portableDID), forKey: userDefaultsKey)

        // Print it to console
        print("Created DID: \(did.uri)")

        return did
    }
}

/// Fetches offerings from the PFI
func getOfferings() async throws -> [Offering] {
    return try await tbDEXHttpClient.getOfferings(pfiDIDURI: pfiDIDURI)
}

/// Run an example exchange between the client and PFI
func exampleExchange(offering: Offering, did: BearerDID) async throws {
    print("Creating RFQ...")

    // Create an RFQ
    var rfq = RFQ(
        to: offering.metadata.from,
        from: did.uri,
        data: .init(
            offeringId: offering.metadata.id.rawValue,
            payinAmount: "1.00",
            claims: [
                claim,
            ],
            payinMethod: SelectedPaymentMethod(
                kind: "USD_LEDGER",
                paymentDetails: [:]
            ),
            payoutMethod: SelectedPaymentMethod(
                kind: "MOMO_MPESA",
                paymentDetails: [
                    "phoneNumber": "1234567890",
                    "reason": "just cause"
                ]
            )
        )
    )

    // exchangeID is set by the first message in an exchange, which is the RFQ in this case (Offering is a Resource,
    // which is why we do not use that ID).
    let exchangeID = rfq.metadata.id.rawValue

    // Sign the RFQ
    try rfq.sign(did: did)

    // Send the RFQ
    try await tbDEXHttpClient.sendMessage(message: rfq)

    print("Sent RFQ, waiting for Quote")

    // Poll exchanges every 1 second to check for a Quote
    var quote: Quote!
    while quote == nil {
        let exchanges = try await tbDEXHttpClient.getExchanges(pfiDIDURI: pfiDIDURI, requesterDID: did)
        for exchange in exchanges {
            guard let lastMessageInExchange = exchange.last else { continue }

            if case .quote(let q) = lastMessageInExchange, q.metadata.exchangeID == exchangeID {
                quote = q
                break
            }
        }

        if quote == nil {
            print("No Quote yet, sleeping for 1 second")
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    print("Got Quote! Making Order")

    // Got the Quote, now make an Order out of it
    var order = Order(
        from: did.uri,
        to: pfiDIDURI,
        exchangeID: exchangeID,
        data: .init()
    )

    // Sign the Order
    try order.sign(did: did)

    // Send the Order
    try await tbDEXHttpClient.sendMessage(message: order)

    print("Sent Order, waiting for Close")

    // Poll exchanges every 1 second to check for an Close
    var close: Close!
    while close == nil {
        let exchanges = try await tbDEXHttpClient.getExchanges(pfiDIDURI: pfiDIDURI, requesterDID: did)
        for exchange in exchanges {
            guard let lastMessageInExchange = exchange.last else { continue }

            switch lastMessageInExchange {
            case .orderStatus(let o):
                if o.metadata.exchangeID == exchangeID {
                    print("Order Status: \(o.data.orderStatus)")
                }
            case .close(let c):
                if c.metadata.exchangeID == exchangeID {
                    close = c
                }
            default:
                // We only care for OrderStatus and Close, ignore the rest
                continue
            }
        }

        if close == nil {
            print("No Close yet, sleeping for 1 second")
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    print("Exchange Closed! Reason: \(close.data.reason ?? "No reason provided")")
}
