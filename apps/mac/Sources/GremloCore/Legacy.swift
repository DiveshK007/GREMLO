import Foundation

/// The product was called Notchi before it was renamed Gremlo. These are the old names, read only to carry
/// existing installs over (settings, hooks, config, packs, env vars); nothing new is written under them.
/// Remove after one release.
public enum Legacy {
    public static let name = "Notchi"
    /// The old env var prefix: GREMLO_X wins, NOTCHI_X is read as a fallback.
    public static func env(_ key: String) -> String? {
        let e = ProcessInfo.processInfo.environment
        return e["GREMLO_\(key)"] ?? e["NOTCHI_\(key)"]
    }
    public static let hookCommand = "bash ~/.notchi/notchi-hook.sh"
    public static let hookScript = "notchi-hook.sh"
    public static let configDir = ".notchi"
    public static let supportDir = "Notchi"
    public static let defaultsDomains = ["Notchi", "app.notchi.mac"]
    public static let keychainService = "dev.notchi.phone"
    public static let gitMarker = "# notchi git hook"
    public static let gitPrev = ".notchi-prev"
    public static let packKey = "notchi"
    public static let cliName = "notchi"

    /// Old species ids ("notchi", "notchi-pip") to the new ones ("gremlo", "gremlo-pip").
    public static func species(_ id: String) -> String {
        id == "notchi" ? "gremlo" : id.hasPrefix("notchi-") ? "gremlo-" + id.dropFirst(7) : id
    }
}
