import AppKit
import ApplicationServices
import CoreAudio
import GremloCore
import IOKit.ps

// Notch feel #24-27: the notch reacts to the Mac (volume, battery, plugging in, screenshots), and, only if you turn
// them on in Settings, to your typing pace and your music. Public APIs only: no brightness (there is no public API),
// no MediaRemote, and the system volume overlay is left alone.

final class MacEvents {
    unowned let live: NotchLiveController
    private var battery = BatteryWatch()
    private var watchedDevices: Set<AudioObjectID> = []
    private var screenshots: NSMetadataQuery?
    private var lastVolume: Float32?

    init(live: NotchLiveController) {
        self.live = live
        startVolume()
        startBattery()
        startScreenshots()
    }

    // MARK: Volume: a CoreAudio listener on the default output device

    private func startVolume() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in self?.watchOutput() }
        watchOutput()
    }

    private func watchOutput() {
        var dev = AudioObjectID(0), size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr, dev != 0, !watchedDevices.contains(dev) else { return }
        watchedDevices.insert(dev)
        lastVolume = volume(of: dev)
        // some devices have one master volume, others only per channel
        for element in [kAudioObjectPropertyElementMain, 1] {
            var v = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            guard AudioObjectHasProperty(dev, &v) else { continue }
            AudioObjectAddPropertyListenerBlock(dev, &v, .main) { [weak self] _, _ in self?.volumeChanged(dev) }
            break
        }
    }

    private func volume(of dev: AudioObjectID) -> Float32? {
        for element in [kAudioObjectPropertyElementMain, 1] {
            var v = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var out = Float32(0), size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectHasProperty(dev, &v), AudioObjectGetPropertyData(dev, &v, 0, nil, &size, &out) == noErr { return out }
        }
        return nil
    }

    private func volumeChanged(_ dev: AudioObjectID) {
        guard let v = volume(of: dev), v != lastVolume else { return }
        lastVolume = v
        // The Mac draws its own volume overlay. The notch stays out of it.
    }

    // MARK: Battery: IOKit power-source notifications

    private func startBattery() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<MacEvents>.fromOpaque(ctx).takeUnretainedValue().readBattery()
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        readBattery()
    }

    private func readBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0, max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let onAC = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            switch battery.update(percent: max > 0 ? cur * 100 / max : 0, onAC: onAC) {
            case .low(let p)?: live.batteryLow(p)
            case .pluggedIn?: live.pluggedIn()
            case nil: break
            }
        }
    }

    // MARK: Screenshots: a Spotlight query for new screen captures (from now on, so it stays small)

    private func startScreenshots() {
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1 AND kMDItemContentCreationDate >= %@", Date() as NSDate)
        q.searchScopes = [NSMetadataQueryUserHomeScope]
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: q, queue: .main) { [weak self] n in
            if let added = n.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [Any], !added.isEmpty { self?.live.screenshot() }
        }
        q.start()
        screenshots = q
    }
}

/// #25, opt-in: a cheer when you type fast, a nap after 5 minutes without typing. Needs Accessibility; it keeps only
/// when keys were pressed in the last 1.5 s, never which keys.
final class TypingWatch {
    private var monitor: Any?
    private var pace = TypingPace()
    private var nap: Timer?

    func set(_ on: Bool, live: NotchLiveController) {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        nap?.invalidate()
        pace = TypingPace()
        guard on else { return }
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(prompt) else { return }  // asks once; turn it on again after granting
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self, weak live] e in
            guard let self, let live else { return }
            if self.pace.key(at: e.timestamp) { live.show(.typing) }
            self.nap?.invalidate()
            self.nap = Timer.scheduledTimer(withTimeInterval: TypingPace.napAfter, repeats: false) { [weak live] _ in live?.show(.nap) }
            self.nap?.tolerance = 10
        }
    }
}

/// #27, opt-in: AppleScript asks Music and Spotify what's playing every 5 s while it's on (Automation consent), and
/// the pet bops at a steady 2 Hz under the track name. No beat detection, no MediaRemote.
final class MusicWatch {
    func set(_ on: Bool, live: NotchLiveController) {
        _ = (on, live)
        // The track name used to sit in the notch for as long as something was playing. The Mac already shows that.
    }
}
