import CryptoKit
import Foundation

// Just enough NEAR for the pet's purse (R4 §18): the Mac signs one kind of transaction, a pay_inference call on the
// pet's own purse, with a function-call key that can call nothing else. Pure: building, encoding and signing are
// here and tested against near-api-js; fetching the nonce and sending live in the app.

public enum Base58 {
    static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    public static func encode(_ data: Data) -> String {
        var digits: [Int] = [0]
        for byte in data {
            var carry = Int(byte)
            for i in digits.indices { carry += digits[i] << 8; digits[i] = carry % 58; carry /= 58 }
            while carry > 0 { digits.append(carry % 58); carry /= 58 }
        }
        let zeros = data.prefix { $0 == 0 }.count
        let body = digits.reversed().drop { $0 == 0 }.map { alphabet[$0] }
        return String(repeating: "1", count: zeros) + String(body)
    }

    public static func decode(_ s: String) -> Data? {
        var bytes: [UInt8] = [0]
        for ch in s {
            guard let v = alphabet.firstIndex(of: ch) else { return nil }
            var carry = v
            for i in bytes.indices { carry += Int(bytes[i]) * 58; bytes[i] = UInt8(carry & 0xff); carry >>= 8 }
            while carry > 0 { bytes.append(UInt8(carry & 0xff)); carry >>= 8 }
        }
        let zeros = s.prefix { $0 == "1" }.count
        return Data(repeating: 0, count: zeros) + Data(bytes.reversed().drop { $0 == 0 })
    }
}

/// A NEAR transaction with one FunctionCall action, Borsh-encoded the way nearcore expects.
public struct NearCall: Equatable, Sendable {
    public var signer: String, publicKey: Data, nonce: UInt64, receiver: String, blockHash: Data
    public var method: String, args: Data, gas: UInt64, deposit: UInt64  // deposit in yocto; the purse call attaches none

    public init(signer: String, publicKey: Data, nonce: UInt64, receiver: String, blockHash: Data, method: String, args: Data, gas: UInt64, deposit: UInt64 = 0) {
        self.signer = signer; self.publicKey = publicKey; self.nonce = nonce; self.receiver = receiver; self.blockHash = blockHash
        self.method = method; self.args = args; self.gas = gas; self.deposit = deposit
    }

    public func encoded() -> Data {
        var d = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u64(_ v: UInt64) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 8)) }
        func str(_ s: String) { let b = Data(s.utf8); u32(b.count); d.append(b) }
        str(signer)
        d.append(0); d.append(publicKey)          // key type 0: ed25519
        u64(nonce)
        str(receiver)
        d.append(blockHash)
        u32(1)                                    // one action
        d.append(2)                               // Action::FunctionCall
        str(method)
        u32(args.count); d.append(args)
        u64(gas)
        u64(deposit); u64(0)                      // u128, little-endian
        return d
    }

    /// The signed transaction, ready for RPC send_tx, and its hash (base58, as explorers show it).
    public func signed(with key: Curve25519.Signing.PrivateKey) throws -> (base64: String, hash: String) {
        let body = encoded()
        let digest = Data(SHA256.hash(data: body))
        let sig = try key.signature(for: digest)
        var out = body
        out.append(0); out.append(sig)             // signature type 0: ed25519, 64 bytes
        return (out.base64EncodedString(), Base58.encode(digest))
    }
}

public enum Purse {
    /// The JSON args for pay_inference, keys sorted so the bytes are stable.
    public static func payArgs(provider: String, amountYocto: String, requestId: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["provider": provider, "amount": amountYocto, "request_id": requestId], options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }
    public static let payGas: UInt64 = 30_000_000_000_000  // 30 Tgas
    /// "ed25519:<base58>", the form NEAR uses for public keys everywhere.
    public static func keyString(_ k: Curve25519.Signing.PublicKey) -> String { "ed25519:" + Base58.encode(k.rawRepresentation) }
}
