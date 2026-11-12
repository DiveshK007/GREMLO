import AppKit
import AudioToolbox
import NotchiCore

// Theme, sound and haptics on the Mac (spec R2 §7-8, HAPTICS.md). Rules in NotchiCore/Feel.swift.

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
        let short = species.hasPrefix("notchi-") ? String(species.dropFirst(7)) : species
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
    /// Settings rows: theme, sound level, haptics.
    func feelControls() -> [NSView] {
        let theme = NSSegmentedControl(labels: ThemeSetting.allCases.map { $0.rawValue.capitalized }, trackingMode: .selectOne, target: self, action: #selector(setTheme(_:)))
        theme.selectedSegment = ThemeSetting.allCases.firstIndex(of: themeSetting) ?? 0
        let sound = NSPopUpButton(frame: .zero, pullsDown: false)
        for l in SoundLevel.allCases { sound.addItem(withTitle: l.title) }
        sound.selectItem(at: soundLevel.rawValue)
        sound.target = self
        sound.action = #selector(setSoundLevel(_:))
        let haptic = NSSegmentedControl(labels: ["On", "Subtle", "Off"], trackingMode: .selectOne, target: self, action: #selector(setHaptics(_:)))
        haptic.selectedSegment = HapticLevel.allCases.firstIndex(of: hapticLevel) ?? 0
        return [caption("Theme"), theme, caption("Sound"), sound, caption("Haptics (Force Touch trackpad)"), haptic]
    }

    @objc func setTheme(_ s: NSSegmentedControl) {
        themeSetting = ThemeSetting.allCases[max(0, s.selectedSegment)]
        defaults.set(themeSetting.rawValue, forKey: "theme")
        applyTheme()
    }
    @objc func setSoundLevel(_ s: NSPopUpButton) {
        soundLevel = SoundLevel(rawValue: s.indexOfSelectedItem) ?? .default
        defaults.set(soundLevel.rawValue, forKey: "soundLevel")
    }
    @objc func setHaptics(_ s: NSSegmentedControl) {
        hapticLevel = HapticLevel.allCases[max(0, s.selectedSegment)]
        defaults.set(hapticLevel.rawValue, forKey: "haptics")
    }
}
