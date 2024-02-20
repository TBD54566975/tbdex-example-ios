import Foundation
import TypeID
import tbDEX
import Web5

/// Set this to whatever the exemplar app spits out
let pfiDIDURI = "did:dht:gei65bh1mwoo8tn3ifnqy69umitfqxzx91eigndxs6mxq1cqxfcy"

let keyManager = InMemoryKeyManager()

func createDid() throws -> BearerDID {
    return try DIDJWK.create(
        keyManager: keyManager,
        options: .init(algorithm: .ed25519)
    )
}

func getOfferings() async throws -> [Offering] {
    return try await HttpClient.getOfferings(pfiDIDURI: pfiDIDURI)
}

func createRfq(offering: Offering, did: DID) -> RFQ {
    return RFQ(
        to: offering.metadata.from,
        from: did.uri,
        data: .init(
            offeringId: offering.metadata.id.rawValue,
            payinAmount: "1.00",
            claims: [],
            payinMethod: SelectedPaymentMethod(
                kind: "USD_LEDGER",
                paymentDetails: [:]
            ),
            payoutMethod: SelectedPaymentMethod(
                kind: "MOMO_MPEAS",
                paymentDetails: [
                    "phoneNumber": "1234567890",
                    "reason": "just cause"
                ]
            )
        )
    )
}
