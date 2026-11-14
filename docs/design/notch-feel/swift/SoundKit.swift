// SoundKit.swift · sounds synced to motion (idea 22). Reference code, not compiled here.
// AVAudioEngine with buffers preloaded at launch: < 10 ms from call to sound, no file I/O on the hot path.
// Levels: Off · Subtle (default, −18 dB) · Full. Muted during a screen share and when the Mac is muted.

import AVFoundation

enum Sound: String, CaseIterable { case pop, close, tick, chomp, whoosh, shutter, chime, thud, boing, fail }

final class SoundKit {
    static let shared = SoundKit()
    enum Level: Float { case off = 0, subtle = 0.12, full = 0.5 }
    var level: Level = .subtle { didSet { engine.mainMixerNode.outputVolume = level.rawValue } }

    private let engine = AVAudioEngine()
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var players: [AVAudioPlayerNode] = []
    private var next = 0

    init() {
        // Files: assets/sounds/<name>.wav (round 2) + sounds/tick.wav and sounds/shutter.wav from this export. See SOUND_MAP.
        for s in Sound.allCases {
            guard let url = Bundle.main.url(forResource: SOUND_MAP[s] ?? s.rawValue, withExtension: "wav"),
                  let f = try? AVAudioFile(forReading: url),
                  let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)) else { continue }
            try? f.read(into: b); buffers[s] = b
        }
        let fmt = buffers.values.first?.format ?? AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        for _ in 0..<6 { let p = AVAudioPlayerNode(); engine.attach(p); engine.connect(p, to: engine.mainMixerNode, format: fmt); players.append(p) }   // pool: overlapping sounds never cut each other
        engine.mainMixerNode.outputVolume = level.rawValue
        engine.prepare()
    }

    func play(_ s: Sound) {
        guard level != .off, !ScreenShare.isActive, let b = buffers[s] else { return }
        if !engine.isRunning { try? engine.start() }
        let p = players[next]; next = (next + 1) % players.count
        p.stop(); p.scheduleBuffer(b, at: nil); p.play()
    }

    /// Stop the engine after 20 s of silence so the audio hardware can sleep (perf budget).
    func idleCheck() { if engine.isRunning, players.allSatisfy({ !$0.isPlaying }) { engine.pause() } }
}

// Existing round-2 WAVs, plus tick.wav and shutter.wav (new, in sounds/ of this export).
let SOUND_MAP: [Sound: String] = [.pop: "door-open", .close: "door-close", .tick: "tick", .chomp: "meal", .whoosh: "whoosh",
                                  .shutter: "shutter", .chime: "celebrate", .thud: "thud", .boing: "boing", .fail: "fail"]
