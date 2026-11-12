import Testing
@testable import VigilCore

struct BatteryMathTests {
    /// IORegistry reports a discharge of 837 mA as the unsigned 64-bit two's complement.
    @Test func decodesANegativeAmperageStoredAsUnsigned() {
        #expect(BatteryMath.signedAmperage(raw: 18_446_744_073_709_550_779) == -837)
    }

    @Test func decodesAPositiveAmperageUnchanged() {
        #expect(BatteryMath.signedAmperage(raw: 2_000) == 2_000)
        #expect(BatteryMath.signedAmperage(raw: 0) == 0)
    }

    @Test func wattsAreAmperageTimesVoltage() {
        // 837 mA at 11.383 V is about 9.53 W.
        let w = BatteryMath.watts(amperageMilliamps: -837, voltageMillivolts: 11_383)
        #expect(abs(w - 9.527) < 0.001)
    }

    @Test func wattsAreReportedAsAMagnitude() {
        #expect(BatteryMath.watts(amperageMilliamps: -2_000, voltageMillivolts: 12_000) == 24)
        #expect(BatteryMath.watts(amperageMilliamps: 2_000, voltageMillivolts: 12_000) == 24)
    }

    @Test func zeroAmperageIsZeroWatts() {
        #expect(BatteryMath.watts(amperageMilliamps: 0, voltageMillivolts: 11_383) == 0)
    }

    @Test func aNegativeVoltageIsTreatedAsZero() {
        #expect(BatteryMath.watts(amperageMilliamps: -500, voltageMillivolts: -1) == 0)
    }
}
