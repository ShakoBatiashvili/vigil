import Foundation
import Testing
import VigilCore
@testable import VigilSystem

/// Spawns real child processes. The stop button must only ever signal the user's
/// own /usr/bin/caffeinate, even when handed a forged description.
@Suite(.serialized)
struct HolderControlTests {
    private func spawn(_ path: String, _ args: [String]) throws -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try p.run()
        return p
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return condition()
    }

    @Test func aSpawnedCaffeinateIsListedAsAStoppableHolder() throws {
        let child = try spawn("/usr/bin/caffeinate", ["-i", "-t", "120"])
        defer { if child.isRunning { child.terminate() } }

        var holder: SleepHolder?
        #expect(waitUntil {
            holder = HolderReader.read().first { $0.pid == child.processIdentifier }
            return holder != nil
        })
        let found = try #require(holder)
        #expect(found.kind == .system)
        #expect(found.executablePath == "/usr/bin/caffeinate")
        #expect(HolderAssessment.isStoppable(executablePath: found.executablePath,
                                             ownerUID: found.ownerUID, currentUID: getuid()))
    }

    @Test func aHolderRemembersWhichProcessStartedIt() throws {
        // The two caffeinates on a real Mac look identical; the parent tells them apart.
        let child = try spawn("/usr/bin/caffeinate", ["-i", "-t", "120"])
        defer { if child.isRunning { child.terminate() } }

        var holder: SleepHolder?
        #expect(waitUntil {
            holder = HolderReader.read().first { $0.pid == child.processIdentifier }
            return holder != nil
        })
        let me = ProcessInfo.processInfo.processIdentifier
        let expected = ProcessLister.displayName(pid: me, path: ProcessLister.executablePath(pid: me))
        #expect(try #require(holder).parentName == expected)
    }

    @Test func parentPIDLookupWorksForTheCurrentProcess() throws {
        let child = try spawn("/bin/sleep", ["5"])
        defer { if child.isRunning { child.terminate() } }
        #expect(ProcessLister.parentPID(pid: child.processIdentifier) == ProcessInfo.processInfo.processIdentifier)
        #expect(ProcessLister.parentPID(pid: 999_999) == nil)
    }

    @Test func stoppingACaffeinateEndsIt() throws {
        let child = try spawn("/usr/bin/caffeinate", ["-i", "-t", "120"])
        defer { if child.isRunning { child.terminate() } }

        var holder: SleepHolder?
        #expect(waitUntil {
            holder = HolderReader.read().first { $0.pid == child.processIdentifier }
            return holder != nil
        })
        #expect(HolderControl.stop(try #require(holder)))
        #expect(waitUntil { !child.isRunning })
    }

    @Test func refusesToStopAnythingThatIsNotCaffeinateEvenIfTheHolderLiesAboutIt() throws {
        let victim = try spawn("/bin/sleep", ["30"])
        defer { if victim.isRunning { victim.terminate() } }

        // A forged holder: claims to be caffeinate, but the pid is really /bin/sleep.
        let forged = SleepHolder(
            pid: victim.processIdentifier, processName: "caffeinate",
            executablePath: "/usr/bin/caffeinate", kind: .system,
            reason: "forged", heldSeconds: 99_999, ownerUID: getuid()
        )
        #expect(HolderControl.stop(forged) == false)
        Thread.sleep(forTimeInterval: 0.2)
        #expect(victim.isRunning)
    }

    @Test func refusesToStopAnAppProcess() throws {
        // Our own test process is the easiest non-caffeinate pid to name.
        let me = SleepHolder(
            pid: ProcessInfo.processInfo.processIdentifier, processName: "self",
            executablePath: "/usr/bin/caffeinate", kind: .system,
            reason: "forged", heldSeconds: 99_999, ownerUID: getuid()
        )
        #expect(HolderControl.stop(me) == false)
    }

    @Test func refusesNonPositivePids() {
        for pid: Int32 in [0, 1, -1] {
            let forged = SleepHolder(pid: pid, processName: "x", executablePath: "/usr/bin/caffeinate",
                                     kind: .system, reason: "", heldSeconds: 1, ownerUID: getuid())
            #expect(HolderControl.stop(forged) == false)
        }
    }
}
