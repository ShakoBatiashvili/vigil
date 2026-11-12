import Foundation
import Testing
@testable import VigilCore

/// Fixed UTC calendar so every test is independent of the machine's timezone.
enum TestClock {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 2026-11-13 is a Friday.
    static func date(_ y: Int = 2026, _ m: Int = 11, _ d: Int = 13, h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
}

struct SessionTests {
    @Test func indefiniteSessionNeverEnds() {
        let end = SessionMode.indefinite.endDate(from: TestClock.date(h: 10), calendar: TestClock.calendar)
        #expect(end == nil)
    }

    @Test func timedSessionEndsAfterItsDuration() throws {
        let mode = try #require(SessionMode.makeTimed(minutes: 90))
        let end = mode.endDate(from: TestClock.date(h: 10), calendar: TestClock.calendar)
        #expect(end == TestClock.date(h: 11, 30))
    }

    @Test func untilLaterTodayEndsToday() throws {
        let mode = try #require(SessionMode.makeUntil(hour: 18, minute: 0))
        let end = mode.endDate(from: TestClock.date(h: 10), calendar: TestClock.calendar)
        #expect(end == TestClock.date(h: 18))
    }

    @Test func untilAlreadyPassedRollsToTomorrow() throws {
        let mode = try #require(SessionMode.makeUntil(hour: 18, minute: 0))
        let end = mode.endDate(from: TestClock.date(h: 19), calendar: TestClock.calendar)
        #expect(end == TestClock.date(2026, 11, 14, h: 18))
    }

    @Test func untilExactlyNowRollsToTomorrowSoItNeverEndsInstantly() throws {
        let mode = try #require(SessionMode.makeUntil(hour: 18, minute: 0))
        let end = mode.endDate(from: TestClock.date(h: 18), calendar: TestClock.calendar)
        #expect(end == TestClock.date(2026, 11, 14, h: 18))
    }

    @Test func untilRollsAcrossAMonthBoundary() throws {
        let mode = try #require(SessionMode.makeUntil(hour: 8, minute: 30))
        let end = mode.endDate(from: TestClock.date(2026, 11, 30, h: 22), calendar: TestClock.calendar)
        #expect(end == TestClock.date(2026, 12, 1, h: 8, 30))
    }

    @Test(arguments: [0.0, -5.0, .nan, .infinity])
    func timedRejectsNonPositiveOrNonFiniteDurations(minutes: Double) {
        #expect(SessionMode.makeTimed(minutes: minutes) == nil)
    }

    @Test func timedRejectsDurationsBeyondTheSanityLimit() {
        #expect(SessionMode.makeTimed(minutes: SessionMode.maxTimedMinutes + 1) == nil)
        #expect(SessionMode.makeTimed(minutes: SessionMode.maxTimedMinutes) != nil)
    }

    @Test(arguments: [(-1, 0), (24, 0), (12, 60), (12, -1), (99, 99)])
    func untilRejectsInvalidClockTimes(hour: Int, minute: Int) {
        #expect(SessionMode.makeUntil(hour: hour, minute: minute) == nil)
    }

    @Test func untilAcceptsTheEdgesOfTheDay() {
        #expect(SessionMode.makeUntil(hour: 0, minute: 0) != nil)
        #expect(SessionMode.makeUntil(hour: 23, minute: 59) != nil)
    }
}
