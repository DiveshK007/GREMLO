// MacEvents.swift · the pet reacts to the Mac (idea 24). Reference code, not compiled here.
// All public APIs. What's NOT here on purpose: brightness (no public API; DisplayServices is private),
// and riding the system volume HUD itself (we show our own volume row in the notch instead).

import AppKit
import CoreAudio
import IOKit.ps

final class MacEvents {
    static let shared = MacEvents()
    weak var notch: NotchController?
    private var lastBattery = 100, wasCharging = false
    private var screenshotQuery: NSMetadataQuery?

    func start() {
        watchVolume(); watchPower(); watchScreenshots(); watchNight()
    }

    // Volume: CoreAudio property listener on the default output device. Shows .volume for 1.8 s, pet rides the bar.
    private func watchVolume() {
        var dev = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &dev)
        var vol = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        // Some devices only expose per-channel volume (element 1 and 2): fall back to element 1 if main isn't settable.
        if !AudioObjectHasProperty(dev, &vol) { vol.mElement = 1 }
        AudioObjectAddPropertyListenerBlock(dev, &vol, .main) { [weak self] _, _ in
            var v: Float32 = 0; var s = UInt32(MemoryLayout<Float32>.size)
            AudioObjectGetPropertyData(dev, &vol, 0, nil, &s, &v)
            VolumeRow.level = Int(v * 100)
            self?.notch?.go(.volume, back: 1.8); Haptics.shared.play(.tick)
        }
    }

    // Battery: IOKit power-source notifications. Low (≤ 10%, once per discharge) → sweat; plugged in → eats a lightning bolt.
    private func watchPower() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            Unmanaged<MacEvents>.fromOpaque(ctx!).takeUnretainedValue().powerChanged()
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        powerChanged()
    }
    private func powerChanged() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let ps = list.first, let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any] else { return }
        let pct = d[kIOPSCurrentCapacityKey] as? Int ?? 100
        let charging = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        if charging && !wasCharging { notch?.go(.charging, back: 2.6); SoundKit.shared.play(.chomp); Haptics.shared.play(.boop) }
        if !charging && pct <= 10 && lastBattery > 10 { notch?.go(.battery, back: 3); Haptics.shared.play(.knock) }
        wasCharging = charging; lastBattery = pct
    }

    // Screenshots: Spotlight marks them kMDItemIsScreenCapture. No folder access needed, nothing read from the image.
    private func watchScreenshots() {
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "kMDItemIsScreenCapture = 1")
        q.searchScopes = [NSMetadataQueryUserHomeScope]
        var seen = 0
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: q, queue: .main) { [weak self] _ in
            guard q.resultCount > seen else { seen = q.resultCount; return }
            seen = q.resultCount
            self?.notch?.go(.screenshot, back: 2.2); SoundKit.shared.play(.shutter)
        }
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { _ in seen = q.resultCount }
        q.start(); screenshotQuery = q
    }

    // Night: after 22:00 local or when the Mac's appearance is Dark and it's after sunset → the pet sleeps with a moon between runs.
    private func watchNight() {
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            let h = Calendar.current.component(.hour, from: Date())
            if (h >= 22 || h < 6), self?.notch?.mode == .rest { self?.notch?.go(.peekOut(.night), back: 2.6) }
        }.tolerance = 60
    }
}
