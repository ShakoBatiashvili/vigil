import Foundation
import Testing
@testable import VigilCore

/// Drives the pure engine the way the app does: mutate the world, then tick.
struct Rig {
    var state = VigilState()
    var settings = Settings()
    var running: [String] = []
    var battery = BatteryReading(percent: 80, onAC: true)
    var now = TestClock.date(h: 10)   // Friday 10:00 UTC

    mutating func start(_ mode: SessionMode) {
        state = Engine.start(state, mode: mode, now: now, battery: battery,
                             settings: settings, calendar: TestClock.calendar)
    }

    mutating func stop() { state = Engine.stop(state) }

    @discardableResult
    mutating func tick() -> Decision {
        let result = Engine.tick(
            state,
            inputs: Inputs(now: now, settings: settings, runningNames: running, battery: battery),
            calendar: TestClock.calendar
        )
        state = result.state
        return result.decision
    }

    mutating func advance(minutes: Int) { now = now.addingTimeInterval(TimeInterval(minutes * 60)) }
    mutating func unplug(at percent: Int) { battery = BatteryReading(percent: percent, onAC: false) }
    mutating func plugIn(at percent: Int) { battery = BatteryReading(percent: percent, onAC: true) }
}

struct EngineTests {
    // MARK: idle

    @Test func doesNothingWhenNothingIsWanted() {
        var rig = Rig()
        let d = rig.tick()
        #expect(d.hold == false)
        #expect(d.reasons.isEmpty)
        #expect(d.effects.isEmpty)
    }

    // MARK: manual sessions

    @Test func anIndefiniteSessionHoldsUntilStopped() {
        var rig = Rig()
        rig.start(.indefinite)
        rig.advance(minutes: 60 * 24)
        let d = rig.tick()
        #expect(d.hold)
        #expect(d.reasons == [.manual(until: nil)])
    }

    @Test func aTimedSessionHoldsThenEndsExactlyAtItsEnd() throws {
        var rig = Rig()
        rig.start(try #require(SessionMode.makeTimed(minutes: 30)))

        rig.advance(minutes: 29)
        let before = rig.tick()
        #expect(before.hold)
        #expect(before.effects.isEmpty)

        rig.advance(minutes: 1)
        let after = rig.tick()
        #expect(after.hold == false)
        #expect(after.effects == [.sessionEnded])
        #expect(rig.state.manual == nil)
    }

    @Test func startingANewSessionReplacesTheOldOne() throws {
        var rig = Rig()
        rig.start(try #require(SessionMode.makeTimed(minutes: 30)))
        rig.start(.indefinite)
        #expect(rig.tick().reasons == [.manual(until: nil)])
    }

    @Test func stoppingEndsTheManualSession() {
        var rig = Rig()
        rig.start(.indefinite)
        rig.stop()
        #expect(rig.tick().hold == false)
    }

    @Test func stoppingDoesNotSilenceAProcessTrigger() {
        var rig = Rig()
        rig.settings.watchedProcesses = ["Xcode"]
        rig.running = ["Xcode"]
        rig.start(.indefinite)
        rig.stop()
        let d = rig.tick()
        #expect(d.hold)
        #expect(d.reasons == [.process("Xcode")])
    }

    // MARK: triggers and schedule

    @Test func aRunningWatchedProcessHolds() {
        var rig = Rig()
        rig.settings.watchedProcesses = ["Xcode"]
        rig.running = ["zsh", "xcode"]
        let d = rig.tick()
        #expect(d.hold)
        #expect(d.reasons == [.process("Xcode")])
    }

    @Test func releasesWhenTheWatchedProcessQuits() {
        var rig = Rig()
        rig.settings.watchedProcesses = ["Xcode"]
        rig.running = ["Xcode"]
        #expect(rig.tick().hold)
        rig.running = []
        #expect(rig.tick().hold == false)
    }

    @Test func theScheduleHoldsInsideItsWindowWhenEnabled() throws {
        var rig = Rig()   // Friday 10:00
        rig.settings.scheduleEnabled = true
        rig.settings.schedule = try #require(TimeWindow.make(weekdays: [6], startMinute: 9 * 60, endMinute: 18 * 60))
        let d = rig.tick()
        #expect(d.hold)
        #expect(d.reasons == [.schedule])
    }

    @Test func aDisabledScheduleNeverHolds() throws {
        var rig = Rig()
        rig.settings.scheduleEnabled = false
        rig.settings.schedule = try #require(TimeWindow.make(weekdays: [6], startMinute: 9 * 60, endMinute: 18 * 60))
        #expect(rig.tick().hold == false)
    }

    @Test func theScheduleReleasesOutsideItsWindow() throws {
        var rig = Rig()
        rig.settings.scheduleEnabled = true
        rig.settings.schedule = try #require(TimeWindow.make(weekdays: [6], startMinute: 9 * 60, endMinute: 18 * 60))
        rig.now = TestClock.date(h: 18)
        #expect(rig.tick().hold == false)
    }

    @Test func reasonsAreListedManualThenProcessThenSchedule() throws {
        var rig = Rig()
        rig.settings.watchedProcesses = ["Xcode"]
        rig.running = ["Xcode"]
        rig.settings.scheduleEnabled = true
        rig.settings.schedule = try #require(TimeWindow.make(weekdays: [6], startMinute: 9 * 60, endMinute: 18 * 60))
        rig.start(.indefinite)
        #expect(rig.tick().reasons == [.manual(until: nil), .process("Xcode"), .schedule])
    }

    // MARK: display

    @Test func theDisplayIsHeldOnlyWhenAskedAndOnlyWhileHolding() {
        var rig = Rig()
        rig.settings.keepDisplayOn = true
        #expect(rig.tick().holdDisplay == false)   // not holding
        rig.start(.indefinite)
        #expect(rig.tick().holdDisplay == true)
        rig.settings.keepDisplayOn = false
        #expect(rig.tick().holdDisplay == false)
    }

    // MARK: battery guard

    @Test func theGuardReleasesAManualSessionBelowTheThresholdOnBattery() {
        var rig = Rig()
        rig.unplug(at: 25)
        rig.start(.indefinite)
        #expect(rig.tick().hold)

        rig.unplug(at: 19)
        let d = rig.tick()
        #expect(d.hold == false)
        #expect(d.effects == [.guardReleased(percent: 19)])
        #expect(rig.state.manual == nil)
        #expect(rig.state.guardTripped)
    }

    @Test func theGuardNotifiesOnlyOnce() {
        var rig = Rig()
        rig.unplug(at: 25)
        rig.start(.indefinite)
        rig.unplug(at: 19)
        #expect(rig.tick().effects == [.guardReleased(percent: 19)])
        #expect(rig.tick().effects.isEmpty)
    }

    @Test func aTriggerCannotReengageWhileTheGuardIsTripped() {
        var rig = Rig()
        rig.settings.watchedProcesses = ["Xcode"]
        rig.running = ["Xcode"]
        rig.unplug(at: 50)
        #expect(rig.tick().hold)

        rig.unplug(at: 19)
        let tripped = rig.tick()
        #expect(tripped.hold == false)
        #expect(tripped.blockedByGuard)
        #expect(tripped.effects == [.guardReleased(percent: 19)])

        rig.unplug(at: 24)          // gauge jitter must not re-engage
        #expect(rig.tick().hold == false)
    }

    @Test func pluggingInReleasesTheGuardAndTheTriggerHoldsAgain() {
        var rig = Rig()
        rig.settings.watchedProcesses = ["Xcode"]
        rig.running = ["Xcode"]
        rig.unplug(at: 19)
        _ = rig.tick()
        rig.plugIn(at: 19)
        let d = rig.tick()
        #expect(d.hold)
        #expect(d.reasons == [.process("Xcode")])
        #expect(rig.state.guardTripped == false)
    }

    @Test func theGuardStaysSilentWhenNothingWasBeingHeld() {
        var rig = Rig()
        rig.unplug(at: 10)
        let d = rig.tick()
        #expect(d.hold == false)
        #expect(d.effects.isEmpty)
        #expect(rig.state.guardTripped)   // still latched for later
    }

    // MARK: deliberate override

    @Test func aManualStartBelowTheThresholdOverridesDownToTheHardFloor() {
        var rig = Rig()
        rig.unplug(at: 15)
        rig.start(.indefinite)

        #expect(rig.tick().hold)                 // 15% < 20% but the user asked for it

        rig.unplug(at: 6)
        #expect(rig.tick().hold)                 // still above the 5% floor

        rig.unplug(at: 4)
        let d = rig.tick()
        #expect(d.hold == false)
        #expect(d.effects == [.guardReleased(percent: 4)])
    }

    @Test func aManualStartAfterATripLiftsTheLatchButKeepsTheFloor() {
        var rig = Rig()
        rig.unplug(at: 25)
        rig.start(.indefinite)
        rig.unplug(at: 19)
        _ = rig.tick()                           // guard releases the session

        rig.start(.indefinite)                   // user turns it on again
        #expect(rig.tick().hold)
    }

    @Test func theOverrideEndsWhenPluggedInSoTheNextUnplugUsesTheNormalThreshold() {
        var rig = Rig()
        rig.unplug(at: 15)
        rig.start(.indefinite)
        _ = rig.tick()

        rig.plugIn(at: 15)
        #expect(rig.tick().hold)

        rig.unplug(at: 15)                       // normal 20% threshold applies again
        let d = rig.tick()
        #expect(d.hold == false)
        #expect(d.effects == [.guardReleased(percent: 15)])
    }

    @Test func startingOnACPowerNeverNeedsAnOverride() {
        var rig = Rig()
        rig.plugIn(at: 10)
        rig.start(.indefinite)
        #expect(rig.state.guardOverride == false)
        #expect(rig.tick().hold)
    }
}
