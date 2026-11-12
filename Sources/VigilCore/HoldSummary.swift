import Foundation

/// The words the app uses about what it's doing: kept pure so they're tested.
public enum HoldSummary {
    /// The name shown by `pmset -g assertions` for our hold.
    public static func assertionName(for reasons: [HoldReason]) -> String {
        let parts = reasons.map { reason -> String in
            switch reason {
            case .manual:             return "manual hold"
            case .process(let name):  return "\(name) is running"
            case .schedule:           return "schedule"
            }
        }
        return parts.isEmpty ? "Vigil" : "Vigil: " + parts.joined(separator: " + ")
    }

    /// One line under the main toggle. A manual hold outranks rules, which
    /// outrank the schedule, because that's the order of the user's intent.
    public static func statusLine(decision: Decision, now: Date, threshold: Int) -> String {
        if decision.blockedByGuard && !decision.hold { return "Paused: battery below \(threshold)%" }
        guard decision.hold else { return "Not holding" }

        for case .manual(let until) in decision.reasons {
            if let until { return "Holding awake · \(Formatting.duration(until.timeIntervalSince(now))) left" }
            return "Holding awake until you stop it"
        }
        for case .process(let name) in decision.reasons {
            return "Holding awake while \(name) is running"
        }
        return "Holding awake on schedule"
    }

    /// Compact countdown beside the menu-bar icon, only for a timed manual hold.
    public static func menuBarText(decision: Decision, now: Date) -> String? {
        guard decision.hold else { return nil }
        for case .manual(let until?) in decision.reasons {
            let seconds = until.timeIntervalSince(now)
            if seconds >= 3_600 {
                return String(format: "%d:%02d", Int(seconds) / 3_600, (Int(seconds) % 3_600) / 60)
            }
            if seconds >= 60 { return "\(Int(seconds) / 60)m" }
            return "<1m"
        }
        return nil
    }
}

public struct Notice: Equatable, Sendable {
    public var title: String
    public var body: String
}

public enum Notices {
    public static func notice(for effect: Effect, threshold: Int) -> Notice {
        switch effect {
        case .sessionEnded:
            return Notice(title: "Keep-awake finished", body: "Your Mac can sleep again.")
        case .guardReleased(let percent):
            let title = percent.map { "Battery at \($0)%: sleep allowed again" } ?? "Battery low: sleep allowed again"
            return Notice(
                title: title,
                body: "You're on battery and below \(threshold)%, so Vigil stopped holding your Mac awake. "
                    + "Plug in to resume your rules, or turn it on again to continue down to \(Settings.thresholdRange.lowerBound)%."
            )
        }
    }
}
