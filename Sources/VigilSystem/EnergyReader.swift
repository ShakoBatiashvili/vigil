import Foundation
import VigilCore

/// Per-process Energy Impact (the Activity Monitor metric, including system
/// processes) from Apple's own `/usr/bin/top`.
///
/// The only subprocess in the whole project: absolute path, fixed arguments, no
/// user input, a scrubbed environment, and a hard timeout. It takes about two
/// seconds, so callers sample only while the panel is open.
public enum EnergyReader {
    private static let top = "/usr/bin/top"
    private static let arguments = ["-l", "2", "-s", "1", "-n", "60", "-o", "power", "-stats", "pid,power"]

    public static func sample(timeout: TimeInterval = 8) async -> [ProcessEnergy] {
        guard let output = await run(timeout: timeout) else { return [] }
        return TopParser.parse(output).map { row in
            ProcessEnergy(
                pid: row.pid,
                power: row.power,
                path: ProcessLister.executablePath(pid: row.pid),
                fallbackName: ProcessLister.launchName(pid: row.pid) ?? ProcessLister.processName(pid: row.pid) ?? "pid \(row.pid)"
            )
        }
    }

    private static func run(timeout: TimeInterval) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: top)
                process.arguments = arguments
                // LC_ALL=C: decimal points, not commas, whatever the user's locale.
                process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                process.standardInput = FileHandle.nullDevice

                do { try process.run() } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()

                continuation.resume(returning: process.terminationStatus == 0
                                    ? String(decoding: data, as: UTF8.self) : nil)
            }
        }
    }
}
