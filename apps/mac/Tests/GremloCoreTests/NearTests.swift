import CryptoKit
import Foundation
import Testing
@testable import GremloCore

@Suite struct NearTests {
    // Reference values from near-api-js 7.4 (createTransaction + encodeTransaction) for the same inputs.
    let seed = Data((1...32).map { UInt8($0) })
    let refPub = "ed25519:9C6hybhQ6Aycep9jaUnP6uL9ZYvDjUp1aSkFWPUFJtpj"
    let refBlock = "US517G5965aydkZ46HS38QLi7UQiSojurfbQfKCELFx"
    let refTx = "FAAAAG1vY2hpLmdyZW1sby50ZXN0bmV0AHm1Vi6P5lT5QHixEuipi6eQH4U65pW+1+DjkQutBJZkKgAAAAAAAAAUAAAAbW9jaGkuZ3JlbWxvLnRlc3RuZXQHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwEAAAACDQAAAHBheV9pbmZlcmVuY2VjAAAAeyJhbW91bnQiOiI1MDAwMDAwMDAwMDAwMDAwMDAwMDAiLCJwcm92aWRlciI6Im9wZXJhdG9yLmdyZW1sby50ZXN0bmV0IiwicmVxdWVzdF9pZCI6ImNoYXRjbXBsLWFiYyJ9AOBX60gbAAAAAAAAAAAAAAAAAAAAAAAA"
    let refHash = "716c92a94b9686d5b66d4f179638ba358cc30cf31afc0842d8c8b33ece68e5a9"

    @Test func base58RoundTripsAndMatchesNear() throws {
        #expect(Base58.encode(Data(repeating: 7, count: 32)) == refBlock)
        #expect(Base58.decode(refBlock) == Data(repeating: 7, count: 32))
        #expect(Base58.encode(Data([0, 0, 1])) == "112" && Base58.decode("112") == Data([0, 0, 1]))
        #expect(Base58.decode("0OIl") == nil, "not in the alphabet")
    }

    @Test func payInferenceTransactionIsByteIdenticalToNearApiJs() throws {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        #expect(Purse.keyString(key.publicKey) == refPub)
        let call = NearCall(signer: "mochi.gremlo.testnet", publicKey: key.publicKey.rawRepresentation, nonce: 42, receiver: "mochi.gremlo.testnet",
                            blockHash: Base58.decode(refBlock)!, method: "pay_inference",
                            args: Purse.payArgs(provider: "operator.gremlo.testnet", amountYocto: "500000000000000000000", requestId: "chatcmpl-abc"), gas: Purse.payGas)
        #expect(call.encoded().base64EncodedString() == refTx)
        #expect(Data(SHA256.hash(data: call.encoded())).map { String(format: "%02x", $0) }.joined() == refHash)
        // the signature covers sha256(tx) and verifies with the key the purse knows
        let (b64, hash) = try call.signed(with: key)
        let out = Data(base64Encoded: b64)!
        #expect(out.prefix(out.count - 65) == call.encoded() && out[out.count - 65] == 0)
        #expect(key.publicKey.isValidSignature(out.suffix(64), for: Data(SHA256.hash(data: call.encoded()))))
        #expect(Base58.decode(hash)?.count == 32)
    }
}
