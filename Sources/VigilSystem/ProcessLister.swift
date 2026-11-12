import Darwin
import Foundation
import VigilCore

/// Read-only process inspection through libproc (public API, no privileges).
public enum ProcessLister {
    private static let pathBufferSize = 4 * Int(MAXPATHLEN)   // PROC_PIDPATHINFO_MAXSIZE

    public static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard got > 0 else { return [] }
        return pids.prefix(Int(got)).filter { $0 > 0 }
    }

    public static func executablePath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: pathBufferSize)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }

    public static func processName(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }

    public static func ownerUID(pid: pid_t) -> UInt32? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
        return info.pbsi_uid
    }

    /// The name the process was started as (basename of argv[0]): "claude" for a
    /// binary that lives at .../versions/2.1.322. Readable for your own processes
    /// through the public KERN_PROCARGS2 sysctl; nil for anyone else's.
    public static func launchName(pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        // Layout: int argc, exec path (NUL-terminated), NUL padding, argv[0], argv[1], ...
        var i = MemoryLayout<Int32>.size
        while i < size, buffer[i] != 0 { i += 1 }   // skip the exec path
        while i < size, buffer[i] == 0 { i += 1 }   // skip padding
        let start = i
        while i < size, buffer[i] != 0 { i += 1 }
        guard i > start else { return nil }

        var name = ((String(decoding: buffer[start..<i], as: UTF8.self)) as NSString).lastPathComponent
        if name.hasPrefix("-") { name.removeFirst() }   // login shells run as "-zsh"
        return name.isEmpty ? nil : name
    }

    public static func parentPID(pid: pid_t) -> pid_t? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbsi_ppid)
    }

    /// A name a person would recognise: the app for app helpers, else the executable.
    public static func displayName(pid: pid_t, path: String?) -> String {
        if let path {
            if let app = DrainModel.appName(fromPath: path) { return app }
            let base = (path as NSString).lastPathComponent
            if !base.isEmpty {
                if DrainModel.isVersionLike(base), let launch = launchName(pid: pid) { return launch }
                return base
            }
        }
        return launchName(pid: pid) ?? processName(pid: pid) ?? "pid \(pid)"
    }

    /// Names of the CURRENT USER's running processes (executable name and, for
    /// app processes, the app's name), for "while X is running" triggers. Other
    /// users' and root's processes are deliberately excluded.
    public static func runningNames() -> [String] {
        let me = getuid()
        var names = Set<String>()
        for pid in allPIDs() {
            guard ownerUID(pid: pid) == me else { continue }
            if let path = executablePath(pid: pid) {
                let base = (path as NSString).lastPathComponent
                if !base.isEmpty { names.insert(base) }
                if let app = DrainModel.appName(fromPath: path) { names.insert(app) }
            }
            // The names it is known by: the kernel's, and what it was started as
            // ("claude" for a binary that lives at .../2.1.322).
            if let name = processName(pid: pid), !name.isEmpty { names.insert(name) }
            if let name = launchName(pid: pid) { names.insert(name) }
        }
        return Array(names)
    }
}
