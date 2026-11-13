import AppKit
import CryptoKit
import GremloCore

// The pet's purse on the Mac (R4 §18, contracts-accounts): this Mac holds an ed25519 key that the owner adds to the
// purse as a function-call key, limited to pay_inference. After each paid thought the server says what's owed
// (payFor); the Mac signs pay_inference on the purse, sends it, and reports the tx to /paid, which counts it only
// once the chain shows it. The key can't move money any other way, and the model never signs anything.

final class PurseController {
    unowned let backend: Backend
    static let service = "dev.gremlo.purse"
    private let rpc = Legacy.env("NEAR_RPC") ?? "https://test.rpc.fastnear.com"
    private var queue: [PayFor] = []
    private var busy = false
    private(set) var lastError: String?
    private(set) var lastPaid: (requestId: String, tx: String)?

    init(backend: Backend) { self.backend = backend }

    /// This Mac's purse key, made once and kept in the Keychain (this device only).
    lazy var key: Curve25519.Signing.PrivateKey = {
        if let s = Keychain.get(service: Self.service), let d = Data(base64Encoded: s), let k = try? Curve25519.Signing.PrivateKey(rawRepresentation: d) { return k }
        let k = Curve25519.Signing.PrivateKey()
        Keychain.set(k.rawRepresentation.base64EncodedString(), service: Self.service)
        return k
    }()
    var publicKey: String { Purse.keyString(key.publicKey) }

    /// Queues one payment; payments go one at a time so the key's nonce never collides.
    func pay(_ p: PayFor) {
        guard !queue.contains(p), lastPaid?.requestId != p.requestId else { return }
        queue.append(p)
        next()
    }

    private func next() {
        guard !busy, let p = queue.first else { return }
        busy = true
        Task { @MainActor in
            do {
                let tx = try await send(p)
                try await report(p, tx: tx)
                lastPaid = (p.requestId, tx)
                lastError = nil
                print("purse: paid \(p.amount) for \(p.requestId), tx \(tx)")
            } catch {
                // nothing is retried blindly: the server stops paid thinking while a thought stays unpaid, and says so
                lastError = error.localizedDescription
                print("purse: \(p.requestId) not paid: \(error.localizedDescription)")
            }
            queue.removeFirst()
            busy = false
            backend.shown = ""
            backend.render()
            next()
        }
    }

    private struct Failure: LocalizedError { let errorDescription: String? }

    private func rpcCall(_ method: String, _ params: Any) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: rpc)!, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": "gremlo", "method": method, "params": params])
        let (data, _) = try await URLSession.shared.data(for: req)
        let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if let e = o["error"] { throw Failure(errorDescription: "NEAR RPC \(method): \(String(describing: e).prefix(200))") }
        return o["result"] as? [String: Any] ?? [:]
    }

    /// Signs and sends pay_inference on the purse; returns the tx hash once it has executed.
    private func send(_ p: PayFor) async throws -> String {
        let ak = try await rpcCall("query", ["request_type": "view_access_key", "finality": "final", "account_id": p.purse, "public_key": publicKey])
        guard let nonce = (ak["nonce"] as? NSNumber)?.uint64Value, let bh = ak["block_hash"] as? String, let block = Base58.decode(bh) else {
            throw Failure(errorDescription: "this Mac's key isn't on \(p.purse) yet (add it in Settings, Phone and Mac)")
        }
        let call = NearCall(signer: p.purse, publicKey: key.publicKey.rawRepresentation, nonce: nonce + 1, receiver: p.purse, blockHash: block,
                            method: "pay_inference", args: Purse.payArgs(provider: p.payTo, amountYocto: p.amount, requestId: p.requestId), gas: Purse.payGas)
        let (b64, hash) = try call.signed(with: key)
        let r = try await rpcCall("send_tx", ["signed_tx_base64": b64, "wait_until": "EXECUTED_OPTIMISTIC"])
        if let status = r["status"] as? [String: Any], let failure = status["Failure"] { throw Failure(errorDescription: "the purse refused: \(String(describing: failure).prefix(200))") }
        return hash
    }

    /// Tells the server; it checks the tx on chain and answers 409 while the tx isn't final, so ask a few times.
    private func report(_ p: PayFor, tx: String) async throws {
        for attempt in 0..<5 {
            let (ok, err) = await withCheckedContinuation { (c: CheckedContinuation<(Bool, String?), Never>) in
                backend.request("/pets/\(backend.petName)/paid", body: ["requestId": p.requestId, "tx": tx]) { data, err in c.resume(returning: (data != nil, err)) }
            }
            if ok { return }
            guard let err, err.hasPrefix("HTTP 409"), attempt < 4 else { throw Failure(errorDescription: err ?? "the server didn't accept the payment") }
            try await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }
}

extension Backend {
    /// Settings, Phone and Mac: the purse this Mac pays from, and the key to add to it.
    func purseGroup() -> NSView {
        let w = pageWidth
        let key = purse.publicKey
        var rows: [NSView] = []
        if let p = info?.purse {
            rows.append(UI.kv("Pays from", p.account, width: w))
            rows.append(UI.kv("Per thought, at most", near4(p.perCall), width: w))
            rows.append(UI.kv("Per day, at most", near4(p.daily), width: w))
        } else {
            rows.append(UI.row("No purse yet", "With a purse, the pet pays for each thought from its own account, within caps you set. Create it with this Mac's key below (see contracts-accounts in the repo).", nil, width: w))
        }
        rows.append(UI.row("This Mac's purse key", key, Btn("Copy", target: self, action: #selector(copyPurseKey)), width: w))
        if let e = purse.lastError { rows.append(UI.row("Last payment failed", e, nil, width: w)) }
        else if let p = purse.lastPaid { rows.append(UI.kv("Last payment", "\(p.tx.prefix(10))\u{2026}", width: w)) }
        return UI.group("The pet's purse", rows, note: "The key can only call pay_inference on the purse: it can't withdraw or move money any other way.", width: w)
    }
    @objc func copyPurseKey() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(purse.publicKey, forType: .string)
    }
}
