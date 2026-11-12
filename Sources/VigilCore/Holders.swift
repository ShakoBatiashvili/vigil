import Foundation

public enum HolderKind: Equatable, Sendable {
    case system     // keeps the Mac from idle-sleeping
    case display    // keeps the screen on (which also keeps the Mac awake)
}

public enum HolderSeverity: Int, Comparable, Sendable {
    case normal, long, stale

    public static func < (lhs: HolderSeverity, rhs: HolderSeverity) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A process currently holding a sleep-preventing power assertion.
public struct SleepHolder: Equatable, Sendable, Identifiable {
    public var pid: Int32
    public var processName: String
    public var executablePath: String?
    public var kind: HolderKind
    public var reason: String
    public var heldSeconds: TimeInterval
    public var ownerUID: UInt32?
    /// Who started it (e.g. "zsh" vs "claude"), to tell identical-looking holders apart.
    public var parentName: String?

    public var id: String { "\(pid)-\(kind)-\(reason)" }

    public init(pid: Int32, processName: String, executablePath: String?, kind: HolderKind,
                reason: String, heldSeconds: TimeInterval, ownerUID: UInt32?, parentName: String? = nil) {
        self.pid = pid
        self.processName = processName
        self.executablePath = executablePath
        self.kind = kind
        self.reason = reason
        self.heldSeconds = heldSeconds
        self.ownerUID = ownerUID
        self.parentName = parentName
    }
}

public enum HolderAssessment {
    public static let longThreshold: TimeInterval = 3_600       // 1 hour
    public static let staleThreshold: TimeInterval = 43_200     // 12 hours

    /// The one binary the app is willing to signal.
    static let stoppableExecutable = "/usr/bin/caffeinate"

    public static func kind(forAssertionType type: String) -> HolderKind? {
        switch type {
        case "PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion":
            return .system
        case "PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion":
            return .display
        default:
            return nil
        }
    }

    public static func severity(heldSeconds: TimeInterval) -> HolderSeverity {
        if heldSeconds >= staleThreshold { return .stale }
        if heldSeconds >= longThreshold { return .long }
        return .normal
    }

    /// Only the user's own `/usr/bin/caffeinate`: never another user's process,
    /// never an app, never a system daemon.
    public static func isStoppable(executablePath: String?, ownerUID: UInt32?, currentUID: UInt32) -> Bool {
        guard executablePath == stoppableExecutable, let ownerUID else { return false }
        return ownerUID == currentUID
    }

    public static func sorted(_ holders: [SleepHolder]) -> [SleepHolder] {
        holders.sorted { $0.heldSeconds > $1.heldSeconds }
    }
}
