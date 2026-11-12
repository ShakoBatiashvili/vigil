import Foundation

/// How long a manual keep-awake session lasts.
public enum SessionMode: Equatable, Codable, Sendable {
    /// Until the user stops it (or the battery guard intervenes).
    case indefinite
    /// For a fixed duration.
    case timed(seconds: TimeInterval)
    /// Until the next occurrence of a wall-clock time (24-hour).
    case until(hour: Int, minute: Int)

    /// Upper bound for a typed-in duration. Input sanity only: `indefinite` exists
    /// for "until I say so", and the battery guard still applies to every mode.
    public static let maxTimedMinutes: Double = 7 * 24 * 60

    public static func makeTimed(minutes: Double) -> SessionMode? {
        guard minutes.isFinite, minutes > 0, minutes <= maxTimedMinutes else { return nil }
        return .timed(seconds: minutes * 60)
    }

    public static func makeUntil(hour: Int, minute: Int) -> SessionMode? {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return .until(hour: hour, minute: minute)
    }

    /// When a session started at `now` should end; `nil` means it never expires.
    /// `until` always resolves strictly after `now`, so "until 18:00" typed at
    /// exactly 18:00 means tomorrow rather than ending instantly.
    public func endDate(from now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .indefinite:
            return nil
        case .timed(let seconds):
            return now.addingTimeInterval(seconds)
        case .until(let hour, let minute):
            return calendar.nextDate(
                after: now,
                matching: DateComponents(hour: hour, minute: minute, second: 0),
                matchingPolicy: .nextTime
            )
        }
    }
}
