import Foundation

/// A weekly time window, e.g. weekdays 09:00 to 18:00.
///
/// `weekdays` use `Calendar` numbering (Sunday = 1 ... Saturday = 7) and name the
/// day the window STARTS. A window whose end is at or before its start crosses
/// midnight: Friday 22:00 to 06:00 is active until Saturday 06:00.
public struct TimeWindow: Equatable, Codable, Sendable {
    public var weekdays: Set<Int>
    public var startMinute: Int   // minutes since midnight, 0..<1440
    public var endMinute: Int     // exclusive

    public init(weekdays: Set<Int>, startMinute: Int, endMinute: Int) {
        self.weekdays = weekdays
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    public static func make(weekdays: Set<Int>, startMinute: Int, endMinute: Int) -> TimeWindow? {
        let window = TimeWindow(weekdays: weekdays, startMinute: startMinute, endMinute: endMinute)
        return window.isValid ? window : nil
    }

    public var isValid: Bool {
        !weekdays.isEmpty
            && weekdays.allSatisfy { (1...7).contains($0) }
            && (0..<1_440).contains(startMinute)
            && (0..<1_440).contains(endMinute)
            && startMinute != endMinute
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute else {
            return false
        }
        let now = hour * 60 + minute

        if startMinute < endMinute {
            return weekdays.contains(weekday) && now >= startMinute && now < endMinute
        }
        // Crosses midnight: the evening part belongs to today's start, the
        // early-morning part belongs to yesterday's.
        if now >= startMinute { return weekdays.contains(weekday) }
        if now < endMinute { return weekdays.contains(weekday == 1 ? 7 : weekday - 1) }
        return false
    }
}
