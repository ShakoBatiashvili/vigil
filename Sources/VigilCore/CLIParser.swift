import Foundation

public enum CLICommand: Equatable, Sendable {
    case help
    case version
    case status
    case holders
    case drain
    case hold(mode: SessionMode, display: Bool)
    case stop(pid: Int32)
}

public enum CLIError: Error, Equatable, Sendable {
    case unknownCommand(String)
    case unknownOption(String)
    case unexpectedArgument(String)
    case missingValue(String)
    case invalidDuration(String)
    case invalidTime(String)
    case invalidPID(String)
    case conflictingOptions

    public var message: String {
        switch self {
        case .unknownCommand(let c):      return "Unknown command '\(c)'. Run 'vigil help'."
        case .unknownOption(let o):       return "Unknown option '\(o)'."
        case .unexpectedArgument(let a):  return "Unexpected argument '\(a)'."
        case .missingValue(let n):        return "Missing value for \(n)."
        case .invalidDuration(let v):     return "'\(v)' isn't a valid duration. Try 30m, 2h or 1h30m (max 7d)."
        case .invalidTime(let v):         return "'\(v)' isn't a valid time. Use 24-hour HH:MM, for example 18:00."
        case .invalidPID(let v):          return "'\(v)' isn't a valid process id."
        case .conflictingOptions:         return "Use either --for or --until, not both."
        }
    }
}

/// "90m", "2h", "1h30m", "1d2h", or a bare number of minutes. Units must descend
/// (d, h, m) and appear at most once; no fractions.
public enum DurationParser {
    public static func minutes(from text: String) -> Double? {
        let s = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }

        let multipliers: [Character: (rank: Int, minutes: Double)] = [
            "d": (0, 1_440), "h": (1, 60), "m": (2, 1),
        ]
        var total = 0.0
        var digits = ""
        var lastRank = -1
        var sawUnit = false

        for ch in s {
            if ch.isASCII && ch.isNumber {
                digits.append(ch)
            } else if let unit = multipliers[ch], !digits.isEmpty, unit.rank > lastRank, let n = Double(digits) {
                total += n * unit.minutes
                lastRank = unit.rank
                digits = ""
                sawUnit = true
            } else {
                return nil
            }
        }
        if !digits.isEmpty {
            guard !sawUnit, let bare = Double(digits) else { return nil }   // trailing digits only valid alone
            total = bare
        } else if !sawUnit {
            return nil
        }
        return SessionMode.makeTimed(minutes: total) == nil ? nil : total
    }
}

public enum CLIParser {
    public static func parse(_ args: [String]) -> Result<CLICommand, CLIError> {
        guard let first = args.first else { return .success(.help) }
        let rest = Array(args.dropFirst())

        switch first {
        case "help", "--help", "-h":  return noExtras(rest, .help)
        case "version", "--version":  return noExtras(rest, .version)
        case "status":                return noExtras(rest, .status)
        case "holders":               return noExtras(rest, .holders)
        case "drain":                 return noExtras(rest, .drain)
        case "hold":                  return parseHold(rest)
        case "stop":                  return parseStop(rest)
        default:                      return .failure(.unknownCommand(first))
        }
    }

    private static func noExtras(_ rest: [String], _ command: CLICommand) -> Result<CLICommand, CLIError> {
        if let stray = rest.first { return .failure(.unexpectedArgument(stray)) }
        return .success(command)
    }

    private static func parseHold(_ args: [String]) -> Result<CLICommand, CLIError> {
        var forValue: String?
        var untilValue: String?
        var display = false

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--for", "--until":
                guard i + 1 < args.count else { return .failure(.missingValue(arg)) }
                if arg == "--for" { forValue = args[i + 1] } else { untilValue = args[i + 1] }
                i += 2
            case "--display":
                display = true
                i += 1
            default:
                return .failure(arg.hasPrefix("-") ? .unknownOption(arg) : .unexpectedArgument(arg))
            }
        }

        if forValue != nil && untilValue != nil { return .failure(.conflictingOptions) }

        if let value = forValue {
            guard let minutes = DurationParser.minutes(from: value),
                  let mode = SessionMode.makeTimed(minutes: minutes)
            else { return .failure(.invalidDuration(value)) }
            return .success(.hold(mode: mode, display: display))
        }
        if let value = untilValue {
            guard let (hour, minute) = clock(from: value),
                  let mode = SessionMode.makeUntil(hour: hour, minute: minute)
            else { return .failure(.invalidTime(value)) }
            return .success(.hold(mode: mode, display: display))
        }
        return .success(.hold(mode: .indefinite, display: display))
    }

    private static func parseStop(_ args: [String]) -> Result<CLICommand, CLIError> {
        guard let raw = args.first else { return .failure(.missingValue("pid")) }
        guard let pid = Int32(raw), pid > 1 else { return .failure(.invalidPID(raw)) }
        if args.count > 1 { return .failure(.unexpectedArgument(args[1])) }
        return .success(.stop(pid: pid))
    }

    /// "18:00" or "9:05": exactly two groups of one or two ASCII digits.
    private static func clock(from text: String) -> (Int, Int)? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts.allSatisfy({ (1...2).contains($0.count) && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let hour = Int(parts[0]), let minute = Int(parts[1])
        else { return nil }
        return (hour, minute)
    }
}

public enum CLIHelp {
    public static let version = "0.1.1"

    public static let text = """
    vigil \(version): keep your Mac awake, safely.

    USAGE
      vigil status                  Battery, power source and what is holding the Mac awake
      vigil holders                 Every process holding sleep off, and for how long
      vigil drain                   Which apps use the most energy right now (takes ~2 s)
      vigil hold [options]          Hold the Mac awake until Ctrl-C, a timer, or the battery guard
      vigil stop <pid>              Stop a stray `caffeinate` of yours (nothing else)
      vigil help | version

    HOLD OPTIONS
      --for <duration>              30m, 2h, 1h30m, 1d (max 7d)
      --until <HH:MM>               Until the next occurrence of a 24-hour clock time
      --display                     Also keep the display on

    The battery guard from your settings applies: on battery, below the threshold
    (default 20%) the hold is released.
    """
}
