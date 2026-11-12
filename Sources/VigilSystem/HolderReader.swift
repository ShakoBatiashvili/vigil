import Foundation
import IOKit.pwr_mgt
import VigilCore

/// Who is holding the Mac awake right now (`IOPMCopyAssertionsByProcess`, the
/// data behind `pmset -g assertions`; public API, no privileges).
public enum HolderReader {
    public static func read(now: Date = Date()) -> [SleepHolder] {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [Int: [[String: Any]]]
        else { return [] }

        var holders: [SleepHolder] = []
        for (rawPID, assertions) in byProcess {
            let pid = Int32(truncatingIfNeeded: rawPID)
            let path = ProcessLister.executablePath(pid: pid)
            let name = ProcessLister.displayName(pid: pid, path: path)
            let uid = ProcessLister.ownerUID(pid: pid)
            let parent = ProcessLister.parentPID(pid: pid).map {
                ProcessLister.displayName(pid: $0, path: ProcessLister.executablePath(pid: $0))
            }

            for assertion in assertions {
                let type = (assertion["AssertType"] as? String)
                    ?? (assertion["AssertionTrueType"] as? String) ?? ""
                guard let kind = HolderAssessment.kind(forAssertionType: type) else { continue }
                if let level = assertion["AssertLevel"] as? Int, level == 0 { continue }   // off

                let started = (assertion["AssertStartWhen"] as? Date) ?? now
                holders.append(SleepHolder(
                    pid: pid,
                    processName: name,
                    executablePath: path,
                    kind: kind,
                    reason: (assertion["AssertName"] as? String) ?? "",
                    heldSeconds: max(0, now.timeIntervalSince(started)),
                    ownerUID: uid,
                    parentName: parent
                ))
            }
        }
        return HolderAssessment.sorted(holders)
    }
}

/// The only action the app takes against another process.
public enum HolderControl {
    /// Politely asks a stray `caffeinate` to quit. The decision is made from the
    /// LIVE process (its real executable path and owner right now), never from the
    /// holder description, which may be stale or forged. Returns whether a signal was sent.
    @discardableResult
    public static func stop(_ holder: SleepHolder) -> Bool {
        let pid = holder.pid
        guard pid > 1 else { return false }
        guard HolderAssessment.isStoppable(
            executablePath: ProcessLister.executablePath(pid: pid),
            ownerUID: ProcessLister.ownerUID(pid: pid),
            currentUID: getuid()
        ) else { return false }
        return kill(pid, SIGTERM) == 0
    }
}
