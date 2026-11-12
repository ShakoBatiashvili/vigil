import Foundation

public struct EnergyRow: Equatable, Sendable {
    public var pid: Int32
    /// Energy Impact, the same unitless score Activity Monitor shows.
    public var power: Double
}

/// Parses `/usr/bin/top -l 2 -s 1 -o power -stats pid,power`.
///
/// `top` prints one table per sample. The first sample has no delta yet (all
/// zeros), so only the LAST table is meaningful. A table ends at the first blank
/// line or any line that doesn't start with a PID.
public enum TopParser {
    static let maxRows = 5_000

    public static func parse(_ output: String) -> [EnergyRow] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        guard let header = lines.lastIndex(where: { $0.hasPrefix("PID") }) else { return [] }

        var rows: [EnergyRow] = []
        for line in lines[lines.index(after: header)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2, let pid = Int32(parts[0]) else { break }
            guard pid > 0 else { continue }

            var token = String(parts[1])
            if token.hasSuffix("+") || token.hasSuffix("-") { token.removeLast() }   // trend marker
            guard let power = Double(token), power.isFinite, power >= 0 else { continue }

            rows.append(EnergyRow(pid: pid, power: power))
            if rows.count >= maxRows { break }
        }
        return rows
    }
}
