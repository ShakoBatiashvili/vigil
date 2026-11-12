import Foundation
import Testing
@testable import VigilCore

/// Calendar weekdays: Sunday = 1 ... Saturday = 7. 2026-11-13 is a Friday.
struct ScheduleTests {
    static let monToFri: Set<Int> = [2, 3, 4, 5, 6]

    private func workHours() throws -> TimeWindow {
        try #require(TimeWindow.make(weekdays: Self.monToFri, startMinute: 9 * 60, endMinute: 18 * 60))
    }

    private func fridayNight() throws -> TimeWindow {
        // Fri 22:00 -> Sat 06:00. The weekday names the day the window STARTS.
        try #require(TimeWindow.make(weekdays: [6], startMinute: 22 * 60, endMinute: 6 * 60))
    }

    // MARK: same-day windows

    @Test func isActiveInsideTheWindowOnAListedWeekday() throws {
        #expect(try workHours().contains(TestClock.date(h: 10), calendar: TestClock.calendar))
    }

    @Test func startIsInclusive() throws {
        #expect(try workHours().contains(TestClock.date(h: 9), calendar: TestClock.calendar))
    }

    @Test func endIsExclusive() throws {
        #expect(try !workHours().contains(TestClock.date(h: 18), calendar: TestClock.calendar))
    }

    @Test func isInactiveJustBeforeStart() throws {
        #expect(try !workHours().contains(TestClock.date(h: 8, 59), calendar: TestClock.calendar))
    }

    @Test func isInactiveOnAnUnlistedWeekday() throws {
        // Saturday 10:00
        #expect(try !workHours().contains(TestClock.date(2026, 11, 14, h: 10), calendar: TestClock.calendar))
    }

    // MARK: overnight windows

    @Test func overnightWindowIsActiveLateOnItsStartDay() throws {
        #expect(try fridayNight().contains(TestClock.date(h: 23), calendar: TestClock.calendar))
    }

    @Test func overnightWindowSpillsIntoTheNextMorning() throws {
        // Saturday 03:00 belongs to Friday's window even though Saturday isn't listed.
        #expect(try fridayNight().contains(TestClock.date(2026, 11, 14, h: 3), calendar: TestClock.calendar))
    }

    @Test func overnightWindowEndsAtItsEndMinute() throws {
        #expect(try !fridayNight().contains(TestClock.date(2026, 11, 14, h: 6), calendar: TestClock.calendar))
    }

    @Test func overnightWindowDoesNotStartOnAnUnlistedDay() throws {
        // Saturday 23:00: Saturday isn't a start day.
        #expect(try !fridayNight().contains(TestClock.date(2026, 11, 14, h: 23), calendar: TestClock.calendar))
    }

    @Test func overnightWindowIsInactiveBeforeItStarts() throws {
        #expect(try !fridayNight().contains(TestClock.date(h: 21, 59), calendar: TestClock.calendar))
    }

    // MARK: validation

    @Test func rejectsAnEmptyWeekdaySet() {
        #expect(TimeWindow.make(weekdays: [], startMinute: 540, endMinute: 1080) == nil)
    }

    @Test(arguments: [0, 8, -1, 100])
    func rejectsOutOfRangeWeekdays(day: Int) {
        #expect(TimeWindow.make(weekdays: [day], startMinute: 540, endMinute: 1080) == nil)
    }

    @Test func rejectsAZeroLengthWindow() {
        #expect(TimeWindow.make(weekdays: [2], startMinute: 540, endMinute: 540) == nil)
    }

    @Test(arguments: [(-1, 600), (600, -1), (1440, 600), (600, 1440)])
    func rejectsMinutesOutsideTheDay(start: Int, end: Int) {
        #expect(TimeWindow.make(weekdays: [2], startMinute: start, endMinute: end) == nil)
    }
}
