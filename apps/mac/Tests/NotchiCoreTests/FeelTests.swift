import Foundation
import Testing
@testable import NotchiCore

@Suite struct ThemeTests {
    @Test func themeResolvesAndAccentTextUsesThePaperSafeShadeOnLight() {
        #expect(Theme.resolve(.system, systemIsDark: true) == .dark && Theme.resolve(.system, systemIsDark: false) == .light)
        #expect(Theme.resolve(.light, systemIsDark: true) == .light && Theme.resolve(.dark, systemIsDark: false) == .dark)
        let paper = RGB(hex: Theme.background(.light))!, ink = RGB(hex: Theme.background(.dark))!
        for s in Roster.all {
            #expect(RGB.contrast(RGB(hex: Theme.accentText(s, .light))!, paper) >= 4.5, "\(s.name) accent text on paper")
            #expect(RGB.contrast(RGB(hex: Theme.accentText(s, .dark))!, ink) >= 4.5, "\(s.name) accent text on ink")
            #expect(Theme.accentText(s, .light) == s.paperSafe)
        }
        #expect(Theme.notch == "#000000", "the notch is black in both themes")
    }
}

@Suite struct SoundTests {
    @Test func levelsFromTheSpecDefaultingToApprovalsOnly() {
        #expect(SoundLevel.default == .approvalsOnly)
        let g = SilenceGate()
        #expect(Sounds.plays("approval", level: .approvalsOnly, gate: g))
        #expect(!Sounds.plays("celebrate", level: .approvalsOnly, gate: g))
        #expect(Sounds.plays("celebrate", level: .petSounds, gate: g) && Sounds.plays("door-open", level: .petSounds, gate: g))
        #expect(!Sounds.plays("whoosh", level: .petSounds, gate: g) && Sounds.plays("whoosh", level: .everything, gate: g))
        #expect(!Sounds.plays("approval", level: .off, gate: g))
        #expect(!Sounds.plays("voice-pip-say", level: .approvalsOnly, gate: g) && Sounds.plays("voice-pip-say", level: .petSounds, gate: g))
        #expect(!Sounds.plays("not-a-sound", level: .everything, gate: g))
        #expect(Sounds.volume("snore") == 0.3 && Sounds.volume("meal") == 1)
        #expect(Sounds.poke(click: 2) == "poke-2" && Sounds.poke(click: 5) == "stomp")
    }

    @Test func theSilenceGateMutesEveryLevelAndTheLineNeverPlays() {
        for gate in [SilenceGate(screenShared: true), SilenceGate(inMeeting: true), SilenceGate(focus: true), SilenceGate(fullScreenVideo: true)] {
            for level in SoundLevel.allCases { #expect(!Sounds.plays("approval", level: level, gate: gate)) }
        }
        #expect(!Sounds.plays("approval", level: .everything, gate: SilenceGate(), forSponsoredLine: true))
    }

    @Test func voicesNeedARequestIdAndWait20Seconds() {
        var v = VoiceLimiter()
        let t = Date(timeIntervalSince1970: 1000)
        #expect(v.voice(species: "pip", mood: "stable", requestId: nil, now: t) == nil, "no model bubble, no voice")
        #expect(v.voice(species: "pip", mood: "stable", requestId: "chatcmpl-1", now: t) == "voice-pip-say")
        #expect(v.voice(species: "pip", mood: "happy", requestId: "chatcmpl-2", now: t.addingTimeInterval(19)) == nil)
        #expect(v.voice(species: "pip", mood: "happy", requestId: "chatcmpl-2", now: t.addingTimeInterval(20)) == "voice-pip-happy")
        // every species has its three voice files
        let dir = repo.appendingPathComponent("assets/sounds")
        for s in ["notchi", "pip", "moss", "gloop", "byte", "puff", "wisp", "tako"] {
            for k in ["say", "happy", "grumpy"] { #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("voice-\(s)-\(k).wav").path)) }
        }
        for name in Sounds.level.keys { #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(name).wav").path), "\(name).wav") }
    }
}

@Suite struct HapticTests {
    @Test func everyMacMomentResolvesToARecipe() {
        for (moment, h) in Haptics.macMap { #expect(Haptics.recipes[h]?.isEmpty == false, "\(moment)") }
        for h in Haptic.allCases { #expect(Haptics.recipes[h] != nil, "\(h)") }
        #expect(Haptics.macMap["celebrate"] == nil, "no haptic for celebrate on the Mac")
    }

    @Test func rateLimitsWithAnInjectedClock() {
        var g = HapticGate()
        let t = Date(timeIntervalSince1970: 0)
        #expect(g.play(.boop, now: t, screenShared: false, lineUp: false) != nil)
        #expect(g.play(.boop, now: t.addingTimeInterval(0.05), screenShared: false, lineUp: false) == nil, "100 ms apart")
        #expect(g.play(.boop, now: t.addingTimeInterval(0.1), screenShared: false, lineUp: false) != nil)
        #expect(g.play(.purr, now: t.addingTimeInterval(1), screenShared: false, lineUp: false) != nil)
        #expect(g.play(.purr, now: t.addingTimeInterval(5), screenShared: false, lineUp: false) == nil, "purr at most every 10 s")
        #expect(g.play(.purr, now: t.addingTimeInterval(11), screenShared: false, lineUp: false) != nil)
        var subtle = HapticGate(level: .subtle)
        #expect(subtle.play(.boop, now: t, screenShared: false, lineUp: false) == nil && subtle.play(.tick, now: t, screenShared: false, lineUp: false) != nil)
        var off = HapticGate(level: .off)
        #expect(off.play(.tick, now: t, screenShared: false, lineUp: false) == nil)
    }

    @Test func nothingDuringAScreenShareOrWhileALineIsUp() {
        var g = HapticGate()
        let t = Date(timeIntervalSince1970: 0)
        #expect(g.play(.snap, now: t, screenShared: true, lineUp: false) == nil)
        #expect(g.play(.snap, now: t, screenShared: false, lineUp: true) == nil)
    }
}
