import Foundation

/// User configuration. Tolerant on the way in (missing keys take defaults,
/// unknown keys are ignored, bad values are clamped or dropped) so a hand-edited
/// or future-version file can never crash the app or widen its behaviour.
public struct Settings: Equatable, Codable, Sendable {
    public static let thresholdRange = 5...50
    public static let maxWatchedProcesses = 20

    /// Release the hold when unplugged and below this percentage.
    public var batteryThreshold: Int = 20
    /// Also stop the display from sleeping (off by default: system sleep only).
    public var keepDisplayOn: Bool = false
    public var watchedProcesses: [String] = []
    public var scheduleEnabled: Bool = false
    public var schedule: TimeWindow?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case batteryThreshold, keepDisplayOn, watchedProcesses, scheduleEnabled, schedule
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        batteryThreshold = try c.decodeIfPresent(Int.self, forKey: .batteryThreshold) ?? defaults.batteryThreshold
        keepDisplayOn = try c.decodeIfPresent(Bool.self, forKey: .keepDisplayOn) ?? defaults.keepDisplayOn
        watchedProcesses = try c.decodeIfPresent([String].self, forKey: .watchedProcesses) ?? defaults.watchedProcesses
        scheduleEnabled = try c.decodeIfPresent(Bool.self, forKey: .scheduleEnabled) ?? defaults.scheduleEnabled
        schedule = try c.decodeIfPresent(TimeWindow.self, forKey: .schedule)
    }

    /// A copy with every field forced into its legal range.
    public func validated() -> Settings {
        var s = self
        s.batteryThreshold = min(max(batteryThreshold, Self.thresholdRange.lowerBound), Self.thresholdRange.upperBound)

        var seen = Set<String>()
        s.watchedProcesses = Array(
            watchedProcesses
                .compactMap(ProcessTrigger.normalize)
                .filter { seen.insert($0.lowercased()).inserted }
                .prefix(Self.maxWatchedProcesses)
        )

        if let window = schedule, window.isValid {
            s.scheduleEnabled = scheduleEnabled
        } else {
            s.schedule = nil
            s.scheduleEnabled = false
        }
        return s
    }

    /// Decodes and validates; any failure yields the defaults.
    public static func decode(from data: Data) -> Settings {
        guard let decoded = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return decoded.validated()
    }

    public func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(self)
    }
}
