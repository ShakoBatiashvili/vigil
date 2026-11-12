import Foundation

/// "Keep awake while this app/process is running."
///
/// Matching is on whole names, case-insensitively. Substring matching is
/// deliberately not supported: watching "ssh" must not trigger on "sshd".
public enum ProcessTrigger {
    public static let maxNameLength = 128

    /// Cleans user input into a displayable name, or `nil` if it can't be one:
    /// trims whitespace, drops a trailing ".app", and rejects empty names, paths
    /// and control characters.
    public static func normalize(_ raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasSuffix(".app") {
            name = String(name.dropLast(4)).trimmingCharacters(in: .whitespaces)
        }
        guard !name.isEmpty, name.count <= maxNameLength else { return nil }
        let forbidden = name.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) || $0 == "/"
        }
        return forbidden ? nil : name
    }

    /// The first watched name (in watch order, normalised) that is running.
    public static func firstMatch(running: [String], watching: [String]) -> String? {
        let runningNames = Set(running.map { $0.lowercased() })
        for entry in watching {
            guard let name = normalize(entry) else { continue }
            if runningNames.contains(name.lowercased()) { return name }
        }
        return nil
    }
}
