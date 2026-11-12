import Testing
@testable import VigilCore

struct FormattingTests {
    static let durationCases: [(Double, String)] = [
        (0, "<1m"),
        (59, "<1m"),
        (60, "1m"),
        (720, "12m"),
        (3_600, "1h"),
        (4_320, "1h 12m"),
        (86_340, "23h 59m"),
        (86_400, "1d"),
        (293_346, "3d 9h"),
    ]

    @Test(arguments: durationCases)
    func durationsReadNaturally(seconds: Double, expected: String) {
        #expect(Formatting.duration(seconds) == expected)
    }

    @Test func negativeDurationsAreTreatedAsZero() {
        #expect(Formatting.duration(-30) == "<1m")
    }

    @Test func wattsShowOneDecimalAndAUnit() {
        #expect(Formatting.watts(9.52) == "9.5 W")
        #expect(Formatting.watts(0) == "0.0 W")
    }

    @Test func clockTimesAreZeroPaddedTwentyFourHour() {
        #expect(Formatting.clock(hour: 9, minute: 5) == "09:05")
        #expect(Formatting.clock(hour: 18, minute: 0) == "18:00")
    }
}
