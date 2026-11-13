import AppKit
import AudioToolbox
import GremloCore

// Theme, sound and haptics on the Mac (spec R2 §7-8, HAPTICS.md). Rules in GremloCore/Feel.swift.

var themeSetting = ThemeSetting(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system
// "Approvals only" by default; an old "Sounds off" setting carries over as Off.
var soundLevel: SoundLevel = SoundLevel(rawValue: defaults.object(forKey: "soundLevel") as? Int ?? -1)
    ?? ((defaults.object(forKey: "sounds") as? Bool) == false ? .off : .default)
var hapticLevel = HapticLevel(rawValue: defaults.string(forKey: "haptics") ?? "") ?? .on

/// What silences sounds and haptics. Screen share, meetings, Focus and full-screen video are detected in the
/// privacy milestone; until then these stay false and the gates simply have nothing to block on.
var silence = SilenceGate()

func applyTheme() {
    switch themeSetting {
    case .system: NSApp.appearance = nil
    case .light: NSApp.appearance = NSAppearance(named: .aqua)
    case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}

var currentMode: Mode {
    Theme.resolve(themeSetting, systemIsDark: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
}

/// Accent-coloured text for the active pet: the accent on dark, the paper-safe shade on light.
func accentTextColor(_ skin: Skin) -> NSColor {
    guard let s = skin.species else { return .labelColor }
    let c = RGB(hex: Theme.accentText(s, currentMode))!
    return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
}

enum Feel {
    private static var ids: [String: SystemSoundID] = [:]
    private static var voices = VoiceLimiter()
    private static var haptics = HapticGate(level: hapticLevel)
    private static let performer = NSHapticFeedbackManager.defaultPerformer

    /// Plays a sound by name if the level and the silence gate allow. System sounds follow the alert volume;
    /// the snore plays quieter through NSSound. The sponsored line never makes a sound.
    static func sound(_ name: String) {
        guard Sounds.plays(name, level: soundLevel, gate: silence) else { return }
        let url = assetsDir.appendingPathComponent("sounds/\(name).wav")
        if Sounds.volume(name) < 1 {
            let s = NSSound(contentsOf: url, byReference: true)
            s?.volume = Sounds.volume(name)
            s?.play()
            return
        }
        if ids[name] == nil {
            var id: SystemSoundID = 0
            if AudioServicesCreateSystemSoundID(url as CFURL, &id) == noErr { ids[name] = id }
        }
        if let id = ids[name] { AudioServicesPlayAlertSound(id) }
    }

    static func event(_ e: String) { if let name = Sounds.events[e] { sound(name) } }

    /// A voice blip alongside a real model bubble, at most once every 20 s.
    static func voice(species: String, mood: String, requestId: String?) {
        let short = species.hasPrefix("gremlo-") ? String(species.dropFirst(7)) : species
        if let name = voices.voice(species: short, mood: mood, requestId: requestId, now: Date()) { sound(name) }
    }

    /// A haptic for something the user is touching; never an alert, never for a sponsored line.
    static func haptic(_ h: Haptic, lineUp: Bool = false) {
        haptics.level = hapticLevel
        guard let recipe = haptics.play(h, now: Date(), screenShared: silence.screenShared, lineUp: lineUp) else { return }
        for (p, delay) in recipe {
            let pattern: NSHapticFeedbackManager.FeedbackPattern = p == .alignment ? .alignment : p == .levelChange ? .levelChange : .generic
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { performer.perform(pattern, performanceTime: .now) }
        }
    }
}

extension Backend {
    /// Settings, Notch and sound: sound level and haptics (R2 §8, HAPTICS.md).
    func feelControls() -> [NSView] {
        let w = pageWidth
        let titles = ["Off", "Approvals", "Pet", "All"]
        return [UI.group("Feel", [
            UI.row("Sound", "Off, approvals only, pet sounds or everything. Silent during screen shares and meetings.",
                   Seg(titles, selected: soundLevel.rawValue, target: self, action: #selector(setSoundLevel(_:))), width: w),
            UI.row("Haptics", "Force Touch trackpad. Never for a sponsored line.",
                   Seg(["On", "Subtle", "Off"], selected: HapticLevel.allCases.firstIndex(of: hapticLevel) ?? 0, target: self, action: #selector(setHaptics(_:))), width: w),
        ], width: w)]
    }
    func themeControl() -> NSView {
        Seg(ThemeSetting.allCases.map { $0.rawValue.capitalized }, selected: ThemeSetting.allCases.firstIndex(of: themeSetting) ?? 0, target: self, action: #selector(setTheme(_:)))
    }
    /// Settings, Earning: amber pulses at a spend you choose. An estimate; it never stops an agent.
    func costAlertGroup() -> NSView {
        let w = pageWidth
        return UI.group("Cost alerts", [
            UI.row("Per run", nil, UI.popup(alertPicker("softAlertRunCents")), width: w),
            UI.row("Per day", nil, UI.popup(alertPicker("softAlertDayCents")), width: w),
        ], note: "An estimate from the transcript's token counts. It never stops an agent.", width: w)
    }

    static let alertSteps = [0, 100, 500, 1000, 2500, 5000]  // cents
    func alertPicker(_ key: String) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        for c in Backend.alertSteps { p.addItem(withTitle: c == 0 ? "Off" : "$\(c / 100)") }
        p.selectItem(at: Backend.alertSteps.firstIndex(of: defaults.integer(forKey: key)) ?? 0)
        p.identifier = NSUserInterfaceItemIdentifier(key)
        p.target = self
        p.action = #selector(setAlert(_:))
        return p
    }
    @objc func setAlert(_ p: NSPopUpButton) {
        guard let key = p.identifier?.rawValue else { return }
        defaults.set(Backend.alertSteps[max(0, p.indexOfSelectedItem)], forKey: key)
    }

    @objc func setTheme(_ s: Seg) {
        themeSetting = ThemeSetting.allCases[max(0, s.selectedSegment)]
        defaults.set(themeSetting.rawValue, forKey: "theme")
        applyTheme()
    }
    @objc func setSoundLevel(_ s: Seg) {
        soundLevel = SoundLevel(rawValue: s.selectedSegment) ?? .default
        defaults.set(soundLevel.rawValue, forKey: "soundLevel")
    }
    @objc func setHaptics(_ s: Seg) {
        hapticLevel = HapticLevel.allCases[max(0, s.selectedSegment)]
        defaults.set(hapticLevel.rawValue, forKey: "haptics")
    }
}
