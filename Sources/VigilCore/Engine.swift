import Foundation

// MARK: - Value types

public struct BatteryReading: Equatable, Sendable {
    /// `nil` on a Mac without a battery (the guard is inert there).
    public var percent: Int?
    public var onAC: Bool

    public init(percent: Int?, onAC: Bool) {
        self.percent = percent
        self.onAC = onAC
    }
}

public struct ManualSession: Equatable, Sendable {
    public var mode: SessionMode
    public var started: Date
    /// `nil` for an indefinite session.
    public var end: Date?

    public init(mode: SessionMode, started: Date, end: Date?) {
        self.mode = mode
        self.started = started
        self.end = end
    }
}

/// Everything the engine remembers between ticks.
public struct VigilState: Equatable, Sendable {
    public var manual: ManualSession?
    /// Latched once the battery guard released the hold; cleared by AC power or
    /// by the user deliberately starting a session again.
    public var guardTripped = false
    /// The user restarted a session while already under the threshold, so the
    /// guard only applies at the hard floor until the next time the Mac is plugged in.
    public var guardOverride = false
    /// Whether the previous tick held the Mac awake (to word the notification).
    public var holding = false

    public init() {}
}

public struct Inputs: Equatable, Sendable {
    public var now: Date
    public var settings: Settings
    public var runningNames: [String]
    public var battery: BatteryReading

    public init(now: Date, settings: Settings, runningNames: [String], battery: BatteryReading) {
        self.now = now
        self.settings = settings
        self.runningNames = runningNames
        self.battery = battery
    }
}

public enum HoldReason: Equatable, Sendable {
    case manual(until: Date?)
    case process(String)
    case schedule
}

public enum Effect: Equatable, Sendable {
    /// A timed manual session reached its end.
    case sessionEnded
    /// The battery guard released a hold the user (or a rule) wanted.
    case guardReleased(percent: Int?)
}

public struct Decision: Equatable, Sendable {
    /// Whether the Mac should be kept from idle-sleeping right now.
    public var hold: Bool
    /// Whether the display should be kept on too (never without `hold`).
    public var holdDisplay: Bool
    /// Why we want to hold. Empty means nothing is asking.
    public var reasons: [HoldReason]
    /// Something wanted to hold but the battery guard said no.
    public var blockedByGuard: Bool
    public var effects: [Effect]

    public init(hold: Bool, holdDisplay: Bool, reasons: [HoldReason], blockedByGuard: Bool, effects: [Effect]) {
        self.hold = hold
        self.holdDisplay = holdDisplay
        self.reasons = reasons
        self.blockedByGuard = blockedByGuard
        self.effects = effects
    }
}

// MARK: - Engine

/// The whole "should the Mac stay awake?" policy as pure functions.
/// The app feeds it facts (clock, running processes, battery) and applies the answer.
public enum Engine {
    /// The lowest the guard ever goes, even after a deliberate override.
    static var hardFloor: Int { Settings.thresholdRange.lowerBound }

    public static func start(
        _ state: VigilState,
        mode: SessionMode,
        now: Date,
        battery: BatteryReading,
        settings: Settings,
        calendar: Calendar = .current
    ) -> VigilState {
        var next = state
        next.manual = ManualSession(mode: mode, started: now, end: mode.endDate(from: now, calendar: calendar))

        // Turning it on is an explicit request. If we're already under the
        // threshold (or the guard just released), honour it down to the hard floor.
        let belowThreshold = battery.percent.map { $0 < settings.batteryThreshold } ?? false
        if !battery.onAC && (state.guardTripped || belowThreshold) {
            next.guardOverride = true
        }
        next.guardTripped = false
        return next
    }

    public static func stop(_ state: VigilState) -> VigilState {
        var next = state
        next.manual = nil
        next.guardOverride = false
        return next
    }

    public static func tick(
        _ state: VigilState,
        inputs: Inputs,
        calendar: Calendar = .current
    ) -> (state: VigilState, decision: Decision) {
        var next = state
        var effects: [Effect] = []

        // Plugging in is the one thing that always resets the guard.
        if inputs.battery.onAC {
            next.guardTripped = false
            next.guardOverride = false
        }

        // Timed manual sessions expire.
        if let manual = next.manual, let end = manual.end, inputs.now >= end {
            next.manual = nil
            effects.append(.sessionEnded)
        }

        let process = ProcessTrigger.firstMatch(
            running: inputs.runningNames,
            watching: inputs.settings.watchedProcesses
        )
        let scheduled: Bool = {
            guard inputs.settings.scheduleEnabled, let window = inputs.settings.schedule else { return false }
            return window.contains(inputs.now, calendar: calendar)
        }()
        let anyWanted = next.manual != nil || process != nil || scheduled

        // Battery guard (latched).
        let threshold = next.guardOverride ? hardFloor : inputs.settings.batteryThreshold
        let tripped = BatteryGuard.isTripped(
            percent: inputs.battery.percent,
            onAC: inputs.battery.onAC,
            threshold: threshold,
            wasTripped: next.guardTripped
        )
        if tripped && !next.guardTripped {
            if anyWanted || state.holding {
                effects.append(.guardReleased(percent: inputs.battery.percent))
            }
            // The guard ends the manual session; the user must turn it on again.
            next.manual = nil
            next.guardOverride = false
        }
        next.guardTripped = tripped

        var reasons: [HoldReason] = []
        if let manual = next.manual { reasons.append(.manual(until: manual.end)) }
        if let process { reasons.append(.process(process)) }
        if scheduled { reasons.append(.schedule) }

        let hold = !reasons.isEmpty && !tripped
        next.holding = hold

        let decision = Decision(
            hold: hold,
            holdDisplay: hold && inputs.settings.keepDisplayOn,
            reasons: reasons,
            blockedByGuard: tripped && (process != nil || scheduled),
            effects: effects
        )
        return (next, decision)
    }
}
