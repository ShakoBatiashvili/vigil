import Foundation

/// Human-readable strings shared by the CLI and the menu-bar app.
public enum Formatting {
    /// "<1m", "12m", "1h 12m", "3d 9h".
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }

    public static func watts(_ value: Double) -> String {
        String(format: "%.1f W", value)
    }

    public static func clock(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }
}
