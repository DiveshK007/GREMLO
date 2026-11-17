import Foundation

/// Whether the pet keeps out of sight. Ads never depend on mood: a hungry pet (compute budget empty) still walks the
/// sponsored sign while the agent works, because that's how it earns food. Mood only stops the paid AI calls.
/// Only an asleep pet (the chain can't be read) with no agent work stays home.
public func staysHome(mood: String, agentWorking: Bool) -> Bool { mood == "asleep" && !agentWorking }

// yoctoNEAR string to "0.0192 NEAR": 4 decimals, rounded down so the popover never shows more than the account holds.
public func near4(_ yocto: String?) -> String {
    guard let yocto, !yocto.isEmpty, yocto.allSatisfy({ $0.isASCII && $0.isNumber }), var units = Decimal(string: yocto) else { return "\u{2014}" }
    units /= Decimal(sign: .plus, exponent: 20, significand: 1)
    var whole = Decimal()
    NSDecimalRound(&whole, &units, 0, .down)
    let digits = String(repeating: "0", count: max(0, 5 - "\(whole)".count)) + "\(whole)"
    return "\(digits.dropLast(4)).\(digits.suffix(4))"  // product copy names no chain; the unit lives in Advanced and the docs
}

public func nearAmount(_ yocto: Decimal) -> String { "\(yocto / Decimal(sign: .plus, exponent: 24, significand: 1))" }

// "+0.0002 NEAR" when the balance went up, nil otherwise (first poll, unknown, same or down).
public func nearGain(_ old: String?, _ new: String?) -> String? {
    guard let o = old.flatMap({ Decimal(string: $0) }), let n = new.flatMap({ Decimal(string: $0) }), n > o else { return nil }
    return "+" + nearAmount(n - o)
}
