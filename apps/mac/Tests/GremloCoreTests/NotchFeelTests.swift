import CoreGraphics
import Foundation
import Testing
@testable import GremloCore

// One serialized suite: Motion.reduce is global, and only these tests change it.
@Suite(.serialized) struct SpringTests {
    /// Runs a spring at 120 Hz; returns each frame's value and the frame the peak callback fired on.
    func run(_ s: Spring, to t: Double, _ p: SpringParams, frames: Int = 240, hz: Double = 120) -> (values: [Double], peak: Int?) {
        var frame = 0, peak: Int?
        s.animate(to: t, p, onPeak: { peak = frame })
        var values: [Double] = []
        while frame < frames { frame += 1; s.step(1 / hz); values.append(s.value) }
        return (values, peak)
    }

    @Test func openingOvershootsAndThePeakCallbackLandsOnTheOvershootFrame() throws {
        Motion.reduce = false
        let (v, peak) = run(Spring(190), to: 560, .open)
        let top = try #require(v.max()), maxFrame = try #require(v.firstIndex(of: top)) + 1
        let overshoot = (top - 560) / (560 - 190)
        #expect(overshoot > 0.03 && overshoot < 0.08, "a few percent past the target, got \(overshoot)")
        #expect(peak == maxFrame, "the tap fires on frame \(String(describing: peak)), the overshoot is on frame \(maxFrame)")
        #expect(abs(v.last! - 560) < 0.05, "and it settles")
        let (v60, peak60) = run(Spring(190), to: 560, .open, frames: 120, hz: 60)
        #expect(peak60 == v60.firstIndex(of: v60.max()!)! + 1, "on the overshoot frame at the 60 Hz Low Power cap too")
    }

    @Test func closingBarelySettlesAndHeightLandsLater() {
        Motion.reduce = false
        let (v, _) = run(Spring(560), to: 190, .close)
        #expect(v.min()! > 190 - 0.02 * 370, "close is snappy with a tiny settle")
        #expect(SpringParams.open.heavier.response == SpringParams.open.response + 0.03)
    }

    @Test func reduceMotionIsCriticallyDampedAndQuick() throws {
        Motion.reduce = true
        defer { Motion.reduce = false }
        let (v, peak) = run(Spring(190), to: 560, .open, frames: 120)
        #expect(v.max()! <= 560 + 1e-9, "no overshoot")
        let there = try #require(v.firstIndex { abs($0 - 560) < 1 })
        #expect(Double(there) / 120 < 0.3, "within a point in under 0.3 s, got \(Double(there) / 120)")
        let restFrame = try #require(v.firstIndex(of: 560))
        #expect(peak == restFrame + 1, "with no overshoot the tap lands on arrival")
    }

    @Test func retargetingKeepsTheVelocity() {
        Motion.reduce = false
        let s = Spring(0)
        s.animate(to: 100, .open)
        for _ in 0..<10 { s.step(1.0 / 120) }
        let v = s.velocity
        s.animate(to: 50, .close)
        #expect(s.velocity == v && v > 0, "grabbing it mid-flight doesn't jump")
        var woke = 0
        s.wake = { woke += 1 }
        s.kick(5)
        #expect(woke == 1)
    }
}

@Suite struct NotchFeelTests {
    @Test func leanFollowsTheCursorWithin140Points() {
        let at = NotchFeel.lean(dx: 0, dy: 0)
        #expect(at.near == 1 && at.shift == 0 && at.growW == 18 && at.growH == 4)
        let side = NotchFeel.lean(dx: 200, dy: 0)
        #expect(abs(side.distance - 120) < 1e-9 && abs(side.shift - 8 * (1 - 120.0 / 140)) < 1e-9)
        let far = NotchFeel.lean(dx: 0, dy: 200)
        #expect(far.near == 0 && far.shift == 0 && far.growW == 0)
        #expect(NotchFeel.lean(dx: -400, dy: 0).shift <= 0, "toward the cursor on the left too")
    }

    @Test func rowsStaggerAfterTheShapeUnlessMotionIsReduced() {
        #expect(NotchFeel.rowDelay(0, reduce: false) == 0.06)
        #expect(abs(NotchFeel.rowDelay(2, reduce: false) - 0.15) < 1e-9)
        #expect(NotchFeel.rowDelay(3, reduce: true) == 0)
    }

    @Test func theShapeIsOnePathWithEarsHangingFromTheTop() {
        let g = NotchGeometry(width: 190, height: 32, radius: 12)
        let box = g.path(centerX: 400, top: 300).boundingBox
        #expect(abs(box.minX - (400 - 95 - 10)) < 0.01 && abs(box.maxX - (400 + 95 + 10)) < 0.01, "ears 10 pt either side")
        #expect(abs(box.maxY - 300) < 0.01 && abs(box.minY - 268) < 0.01, "top edge at the top, 32 pt down")
        var bowed = g; bowed.bulge = 1
        #expect(bowed.path(centerX: 400, top: 300).boundingBox.width >= box.width, "sides bow out while opening")
    }

    @Test func idleLifeAndOpening() {
        #expect(NotchFeel.idleRow(hour: 23, pick: 0) == .night && NotchFeel.idleRow(hour: 3, pick: 2) == .night)
        #expect([Row.yawn, .peek, .edgepeek, .gaze].contains(NotchFeel.idleRow(hour: 14, pick: 7)))
        #expect(NotchFeel.idleAllowed(state: .rest, screenShared: false, inMeeting: false, focus: false))
        #expect(!NotchFeel.idleAllowed(state: .rest, screenShared: true, inMeeting: false, focus: false), "never during a share")
        #expect(!NotchFeel.idleAllowed(state: .think, screenShared: false, inMeeting: false, focus: false))
        #expect(NotchFeel.isOpening(from: (190, 32), to: (520, 82)) && !NotchFeel.isOpening(from: (520, 82), to: (190, 32)))
        #expect(NotchFeel.rim(.think) == .flow && NotchFeel.rim(.knock) == .solid && NotchFeel.rim(.rest) == .off)
        #expect(NotchFeel.agentColor("Claude Code") == "#D97757" && NotchFeel.agentColor("Codex") == "#10A37F")
    }

    @Test func textureTicksMayBeDenseButNotUnder35ms() {
        var g = HapticGate()
        let t = Date(timeIntervalSince1970: 0)
        #expect(g.play(.tick, now: t, screenShared: false, lineUp: false) != nil)
        #expect(g.play(.tick, now: t.addingTimeInterval(0.02), screenShared: false, lineUp: false) == nil)
        #expect(g.play(.tick, now: t.addingTimeInterval(0.04), screenShared: false, lineUp: false) != nil, "35 ms for ticks")
        #expect(g.play(.snap, now: t.addingTimeInterval(0.05), screenShared: false, lineUp: false) != nil, "ticks don't hold up the snap")
        #expect(g.play(.tick, now: t.addingTimeInterval(1), screenShared: true, lineUp: false) == nil, "nothing during a share")
    }

    @Test func pullFlickAndParticleNumbers() {
        #expect(NotchFeel.band(0) == 0 && NotchFeel.band(-20) == 0)
        #expect(abs(NotchFeel.band(100) - 100 * 0.55 / (1 + 100.0 / 320) * 2) < 1e-9)
        #expect(NotchFeel.band(80) < NotchFeel.pullThreshold && NotchFeel.band(200) > NotchFeel.pullThreshold, "about 160 pt of drag opens the room")
        #expect(NotchFeel.band(1000) - NotchFeel.band(900) < 100 - 1, "it resists the further you pull")
        #expect(NotchFeel.pullEnd(band: 131, upwardSpeed: 0, big: false, roomOpen: false) == .openRoom)
        #expect(NotchFeel.pullEnd(band: 129, upwardSpeed: 0, big: false, roomOpen: false) == .release, "a short pull springs back")
        #expect(NotchFeel.pullEnd(band: 200, upwardSpeed: 0, big: true, roomOpen: true) == .release, "the room is already open")
        #expect(NotchFeel.pullEnd(band: 0, upwardSpeed: 501, big: true, roomOpen: false) == .dismiss)
        #expect(NotchFeel.pullEnd(band: 0, upwardSpeed: 501, big: false, roomOpen: false) == .release)
        let stretch = NotchFeel.stretch(squash: NotchFeel.squashOpen, press: 1)
        #expect(abs(stretch.x - (1 - NotchFeel.squashOpen * NotchFeel.squashScale)) < 1e-9)
        #expect(abs(stretch.y - (1 + NotchFeel.squashOpen * NotchFeel.squashScale)) < 1e-9)
        #expect(NotchFeel.particles(.confetti, lowPower: false) == 60 && NotchFeel.particles(.confetti, lowPower: true) == 50)
        #expect(NotchFeel.particles(.sweat, lowPower: true) == 6)
        #expect(NotchLive.size(.drop) == (320, 92) && NotchLive.size(.quick) == (460, 62))
        var i = NotchLive.Inputs(); i.quick = true; i.waiting = 1
        #expect(NotchLive.resolve(i, now: Date()) == .quick, "asked for this moment, it sits over a waiting approval")
        #expect(Haptics.recipes[.heartbeat]?.count == 2)
    }

    @Test func macEventsAndEasterEggs() {
        var b = BatteryWatch()
        #expect(b.update(percent: 50, onAC: false) == nil)
        #expect(b.update(percent: 10, onAC: false) == .low(10) && b.update(percent: 8, onAC: false) == nil, "once per discharge")
        #expect(b.update(percent: 8, onAC: true) == .pluggedIn && b.update(percent: 9, onAC: true) == nil)
        #expect(b.update(percent: 9, onAC: false) == .low(9), "a new discharge warns again")
        var fresh = BatteryWatch()
        #expect(fresh.update(percent: 80, onAC: true) == nil, "launching on AC isn't a plug-in")

        var k = Konami()
        let code: [UInt16] = [126, 126, 125, 125, 123, 124, 123, 124, 11, 0]
        var early: [Bool] = []
        for key in [UInt16(53)] + code.dropLast() { early.append(k.feed(key)) }
        let last = k.feed(0)
        #expect(!early.contains(true) && last, "only the last key of the code fires")

        var t = TypingPace(), slow: [Bool] = []
        for i in 0..<9 { slow.append(t.key(at: Double(i) * 0.2)) }
        #expect(!slow.contains(true), "5 a second isn't a sprint")
        var fast = TypingPace(), quick = false
        for i in 0..<12 { quick = fast.key(at: Double(i) * 0.1) }
        #expect(quick, "10 a second is")
        #expect(MacMoment.volume(0.5).size == (330, 60) && MacMoment.trick(.backflip).hold == 2.4 && MacMoment.over.contains(.rest))
    }

    @Test func theRestingShapeHidesInsideTheHardwareNotch() {
        let rest = NotchFeel.restSize(hardware: (179, 32))
        #expect(rest.w < 179 && rest.h < 32, "fully under the real notch")
        #expect(NotchFeel.ear(width: rest.w, hardwareWidth: 179) == 0, "no ears at rest")
        #expect(NotchFeel.ear(width: 199, hardwareWidth: 179) == 10 && NotchFeel.ear(width: 185, hardwareWidth: 179) == 3, "ears grow past its edges")
        #expect(NotchFeel.ear(width: 190, hardwareWidth: 0) == 10, "no hardware notch: the drawn notch keeps its ears")
    }
}
