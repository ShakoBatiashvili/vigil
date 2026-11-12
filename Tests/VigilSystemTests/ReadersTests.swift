import Foundation
import Testing
import VigilCore
@testable import VigilSystem

struct BatteryReaderTests {
    @Test func readingIsSaneOnAnyMac() {
        let b = BatteryReader.read()
        if let percent = b.percent { #expect((0...100).contains(percent)) }
        if let watts = b.watts { #expect(watts >= 0 && watts < 250) }
        if let minutes = b.timeRemainingMinutes { #expect(minutes >= 0) }
    }

    @Test func aMacWithABatteryReportsAPercentage() {
        // Skip on desktops (no battery): the guard is meant to be inert there.
        let b = BatteryReader.read()
        guard b.percent != nil else { return }
        #expect(b.cycleCount == nil || b.cycleCount! >= 0)
    }
}

struct ProcessListerTests {
    @Test func listsTheCurrentProcessByItsExecutableName() {
        let names = ProcessLister.runningNames()
        #expect(names.contains(ProcessInfo.processInfo.processName))
    }

    @Test func alsoListsTheNameAProcessWasLaunchedUnder() throws {
        // Claude Code lives at .../versions/2.1.322 but is started through a symlink named "claude".
        // The kernel records the launch name, and that's the name a person would watch for.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vigil-link-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let link = dir.appendingPathComponent("vigiltestlink")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/bin/sleep"))

        let child = Process()
        child.executableURL = link
        child.arguments = ["20"]
        try child.run()
        defer { if child.isRunning { child.terminate() } }

        var names: [String] = []
        let deadline = Date().addingTimeInterval(3)
        repeat {
            names = ProcessLister.runningNames()
            if names.contains("vigiltestlink") { break }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        #expect(names.contains("vigiltestlink"))
        #expect(names.contains("sleep"))   // and still the real executable's name
    }

    // MARK: launch name (argv[0])

    private func spawnViaSymlink(named linkName: String, to target: String) throws -> (child: Process, cleanup: () -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vigil-link-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let link = dir.appendingPathComponent(linkName)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: target))
        let child = Process()
        child.executableURL = link
        child.arguments = ["20"]
        try child.run()
        return (child, {
            if child.isRunning { child.terminate() }
            try? FileManager.default.removeItem(at: dir)
        })
    }

    @Test func launchNameIsWhatTheProcessWasStartedAs() throws {
        let (child, cleanup) = try spawnViaSymlink(named: "vigiltestlink", to: "/bin/sleep")
        defer { cleanup() }
        Thread.sleep(forTimeInterval: 0.2)
        #expect(ProcessLister.launchName(pid: child.processIdentifier) == "vigiltestlink")
        // The kernel's own idea of the name is the resolved executable.
        #expect(ProcessLister.processName(pid: child.processIdentifier) == "sleep")
    }

    @Test func launchNameWorksForTheCurrentProcessAndFailsCleanlyForAMissingOne() {
        #expect(ProcessLister.launchName(pid: ProcessInfo.processInfo.processIdentifier)?.isEmpty == false)
        #expect(ProcessLister.launchName(pid: 999_999) == nil)
    }

    @Test func aVersionNumberedExecutableIsDisplayedByItsLaunchName() throws {
        // Claude Code: .../versions/2.1.322, started as "claude".
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vigil-ver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("9.9.9")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: real)
        let link = dir.appendingPathComponent("fancytool")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let child = Process()
        child.executableURL = link
        child.arguments = ["20"]
        try child.run()
        defer { if child.isRunning { child.terminate() } }
        Thread.sleep(forTimeInterval: 0.3)

        let pid = child.processIdentifier
        let path = ProcessLister.executablePath(pid: pid)
        #expect(path?.hasSuffix("/9.9.9") == true)
        #expect(ProcessLister.displayName(pid: pid, path: path) == "fancytool")
    }

    @Test func onlyIncludesTheCurrentUsersProcesses() {
        // launchd (pid 1) is root's; it must not satisfy a user's "while X runs" trigger.
        #expect(!ProcessLister.runningNames().contains("launchd"))
    }

    @Test func pathAndOwnerLookupsWorkForTheCurrentProcess() {
        let pid = ProcessInfo.processInfo.processIdentifier
        #expect(ProcessLister.executablePath(pid: pid)?.hasPrefix("/") == true)
        #expect(ProcessLister.ownerUID(pid: pid) == getuid())
    }

    @Test func lookupsForAMissingPidReturnNil() {
        #expect(ProcessLister.executablePath(pid: 999_999) == nil)
        #expect(ProcessLister.ownerUID(pid: 999_999) == nil)
    }
}

struct EnergyReaderTests {
    @Test func samplesRealProcessesWithinTheTimeout() async {
        let start = Date()
        let rows = await EnergyReader.sample()
        #expect(Date().timeIntervalSince(start) < 10)
        #expect(!rows.isEmpty)
        #expect(rows.allSatisfy { $0.pid > 0 && $0.power >= 0 && !$0.fallbackName.isEmpty })
    }
}

struct SettingsStoreTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vigil-test-\(UUID().uuidString)")
    }

    @Test func loadingWhenNothingIsSavedGivesDefaults() {
        #expect(SettingsStore(directory: tempDir()).load() == Settings())
    }

    @Test func saveThenLoadRoundTrips() throws {
        let store = SettingsStore(directory: tempDir())
        var s = Settings()
        s.batteryThreshold = 30
        s.watchedProcesses = ["Xcode"]
        try store.save(s)
        #expect(store.load() == s)
    }

    @Test func theFileIsPrivateToTheUser() throws {
        let dir = tempDir()
        let store = SettingsStore(directory: dir)
        try store.save(Settings())
        let file = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("settings.json").path)
        let folder = try FileManager.default.attributesOfItem(atPath: dir.path)
        #expect((file[.posixPermissions] as? Int) == 0o600)
        #expect((folder[.posixPermissions] as? Int) == 0o700)
    }

    @Test func aCorruptedFileFallsBackToDefaults() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: dir.appendingPathComponent("settings.json"))
        #expect(SettingsStore(directory: dir).load() == Settings())
    }

    @Test func savingValidatesBeforeWriting() throws {
        let store = SettingsStore(directory: tempDir())
        var s = Settings()
        s.batteryThreshold = 999
        try store.save(s)
        #expect(store.load().batteryThreshold == Settings.thresholdRange.upperBound)
    }
}
