import Darwin
import Foundation
import VigilCore

/// Reads and writes `settings.json` in a private (0700) folder. Loading never
/// fails: anything unreadable becomes the defaults.
public struct SettingsStore {
    public let directory: URL

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vigil", isDirectory: true)
    }

    public init(directory: URL = SettingsStore.defaultDirectory) {
        self.directory = directory
    }

    var fileURL: URL { directory.appendingPathComponent("settings.json") }

    public func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL) else { return Settings() }
        return Settings.decode(from: data)
    }

    /// Validates, then writes atomically with owner-only permissions (never a
    /// moment where the file exists world-readable).
    public func save(_ settings: Settings) throws {
        guard let data = settings.validated().encoded() else {
            throw CocoaError(.coderInvalidValue)
        }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let temporary = directory.appendingPathComponent(".settings.json.tmp")
        guard FileManager.default.createFile(
            atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]
        ) else { throw CocoaError(.fileWriteUnknown) }

        guard rename(temporary.path, fileURL.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
