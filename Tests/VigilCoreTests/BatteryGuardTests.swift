import Testing
@testable import VigilCore

struct BatteryGuardTests {
    @Test func doesNotTripOnACPowerEvenWhenNearlyEmpty() {
        #expect(!BatteryGuard.isTripped(percent: 3, onAC: true, threshold: 20, wasTripped: false))
    }

    @Test func doesNotTripAboveTheThreshold() {
        #expect(!BatteryGuard.isTripped(percent: 21, onAC: false, threshold: 20, wasTripped: false))
    }

    @Test func doesNotTripExactlyAtTheThreshold() {
        // "Release below 20%": 20 is still fine, 19 is not.
        #expect(!BatteryGuard.isTripped(percent: 20, onAC: false, threshold: 20, wasTripped: false))
    }

    @Test func tripsBelowTheThresholdOnBattery() {
        #expect(BatteryGuard.isTripped(percent: 19, onAC: false, threshold: 20, wasTripped: false))
    }

    @Test func staysTrippedWhileOnBatteryEvenIfTheReadingJitters() {
        // Once released we must not re-engage just because the gauge wobbled up.
        #expect(BatteryGuard.isTripped(percent: 24, onAC: false, threshold: 20, wasTripped: true))
    }

    @Test func clearsTheLatchOnceThePowerAdapterIsConnected() {
        #expect(!BatteryGuard.isTripped(percent: 15, onAC: true, threshold: 20, wasTripped: true))
    }

    @Test func neverTripsWhenThereIsNoBattery() {
        // A desktop Mac reports no percentage; the guard must be inert there.
        #expect(!BatteryGuard.isTripped(percent: nil, onAC: false, threshold: 20, wasTripped: false))
    }

    @Test func aTrippedLatchSurvivesAMissingReadingOnBattery() {
        #expect(BatteryGuard.isTripped(percent: nil, onAC: false, threshold: 20, wasTripped: true))
    }
}
