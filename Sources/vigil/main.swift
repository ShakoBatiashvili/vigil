import Foundation
import VigilCore
import VigilSystem

// vigil: the command-line face of the same tested core the menu-bar app uses.
// No network, no privileges. The only subprocess is /usr/bin/top (see EnergyReader).

// MARK: - Output helpers

func printErr(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? String(text.prefix(width)) : text + String(repeating: " ", count: width - text.count)
}

func severityMark(_ s: HolderSeverity) -> String {
    switch s {
    case .normal: return " "
    case .long:   return "!"
    case .stale:  return "!!"
    }
}

// MARK: - Commands

func runStatus() {
    let battery = BatteryReader.read()
    let settings = SettingsStore().load()
    let holders = HolderReader.read()

    var line = "Battery   "
    if let percent = battery.percent {
        line += "\(percent)%"
        line += battery.onAC ? " · plugged in" : " · on battery"
        if battery.isCharging { line += " · charging" }
        if let watts = battery.watts, !battery.onAC || battery.isCharging {
            line += " · " + Formatting.watts(watts)
        }
        if let minutes = battery.timeRemainingMinutes, !battery.onAC {
            line += " · ~\(Formatting.duration(Double(minutes) * 60)) left"
        }
        if let cycles = battery.cycleCount { line += " · \(cycles) cycles" }
    } else {
        line += "no battery"
    }
    print(line)
    print("Guard     release below \(settings.batteryThreshold)% on battery")

    if holders.isEmpty {
        print("Holding   nothing is keeping this Mac awake")
    } else {
        let longest = holders[0]
        print("Holding   \(holders.count) assertion\(holders.count == 1 ? "" : "s") keeping this Mac awake "
              + "(longest: \(longest.processName), \(Formatting.duration(longest.heldSeconds)))")
        if holders.contains(where: { HolderAssessment.severity(heldSeconds: $0.heldSeconds) == .stale }) {
            print("          ! something has held it awake for 12h+. Run: vigil holders")
        }
    }
}

func runHolders() {
    let holders = HolderReader.read()
    guard !holders.isEmpty else {
        print("Nothing is holding this Mac awake.")
        return
    }
    print("\(pad("PID", 7)) \(pad("HELD", 9)) \(pad("KEEPS", 8)) \(pad("PROCESS (started by)", 30)) REASON")
    for h in holders {
        let sev = HolderAssessment.severity(heldSeconds: h.heldSeconds)
        let stoppable = HolderAssessment.isStoppable(executablePath: h.executablePath, ownerUID: h.ownerUID, currentUID: getuid())
        let kind = h.kind == .system ? "system" : "display"
        let who = h.processName + (h.parentName.map { " ← \($0)" } ?? "")
        var row = "\(pad(String(h.pid), 7)) \(pad(Formatting.duration(h.heldSeconds), 9)) \(pad(kind, 8)) \(pad(who, 30)) \(h.reason)"
        if sev != .normal { row += "  \(severityMark(sev))" }
        if stoppable { row += "   -> vigil stop \(h.pid)" }
        print(row)
    }
}

func runDrain() async {
    print("Sampling energy impact (about 2 seconds)...")
    let rows = await EnergyReader.sample()
    let drain = DrainModel.group(rows, top: 8)
    guard !drain.isEmpty else {
        print("No energy data available.")
        return
    }
    let top = drain.map(\.share).max() ?? 1
    for item in drain {
        let filled = Int((item.share / top * 20).rounded())
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: 20 - filled)
        let procs = item.processCount > 1 ? " (\(item.processCount) processes)" : ""
        print("\(bar) \(pad(String(format: "%2.0f%%", item.share * 100), 4)) \(item.name)\(procs)")
    }
    let battery = BatteryReader.read()
    if let watts = battery.watts, !battery.onAC {
        print("\nWhole Mac right now: \(Formatting.watts(watts)) from the battery. Bars show Energy Impact, the Activity Monitor score.")
    }
}

func runStop(pid: Int32) {
    guard let holder = HolderReader.read().first(where: { $0.pid == pid }) else {
        printErr("pid \(pid) isn't holding sleep off. Run 'vigil holders' to see what is.")
        exit(1)
    }
    if HolderControl.stop(holder) {
        print("Asked \(holder.processName) (pid \(pid)) to quit.")
    } else {
        printErr("Refused: only your own /usr/bin/caffeinate can be stopped from here. "
                 + "\(holder.processName) (pid \(pid)) is not one; quit it the normal way.")
        exit(1)
    }
}

func runHold(mode: SessionMode, display: Bool) -> Never {
    var settings = SettingsStore().load()
    settings.keepDisplayOn = display
    // Triggers and schedules belong to the menu-bar app; this is a manual hold.
    settings.watchedProcesses = []
    settings.scheduleEnabled = false

    let power = PowerHold()
    let battery = BatteryReader.read()
    var state = Engine.start(VigilState(), mode: mode, now: Date(), battery: battery.reading, settings: settings)

    func describe(_ mode: SessionMode) -> String {
        switch mode {
        case .indefinite: return "until you press Ctrl-C"
        case .timed(let seconds): return "for \(Formatting.duration(seconds))"
        case .until(let h, let m): return "until \(Formatting.clock(hour: h, minute: m))"
        }
    }
    print("Holding this Mac awake \(describe(mode))\(display ? ", display on" : "").")
    if !display { print("\(HoldSummary.screenMayTurnOff) Add --display to keep it on.") }
    if state.guardOverride, let percent = battery.percent {
        print("Battery is at \(percent)%, below your \(settings.batteryThreshold)% guard. Continuing because you asked; "
              + "the guard still stops it at \(Settings.thresholdRange.lowerBound)%.")
    } else {
        print("Battery guard: released below \(settings.batteryThreshold)% on battery.")
    }

    func finish(_ message: String, code: Int32) -> Never {
        power.releaseAll()
        print(message)
        exit(code)
    }

    func tick() {
        let reading = BatteryReader.read().reading
        let result = Engine.tick(
            state,
            inputs: Inputs(now: Date(), settings: settings, runningNames: [], battery: reading)
        )
        state = result.state
        let decision = result.decision
        power.apply(system: decision.hold, display: decision.holdDisplay, reason: "Vigil: manual hold")

        if decision.effects.contains(.sessionEnded) { finish("Timer finished. Sleep is allowed again.", code: 0) }
        for effect in decision.effects {
            if case .guardReleased(let percent) = effect {
                finish("Battery guard: released at \(percent.map { "\($0)%" } ?? "low battery"). Plug in to hold again.", code: 3)
            }
        }
    }

    for sig in [SIGINT, SIGTERM] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler { finish("\nStopped. Sleep is allowed again.", code: 0) }
        source.resume()
        signalSources.append(source)
    }

    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now(), repeating: 5)
    timer.setEventHandler(handler: tick)
    timer.resume()
    holdTimer = timer
    dispatchMain()
}

var signalSources: [DispatchSourceSignal] = []
var holdTimer: DispatchSourceTimer?

// MARK: - Entry point

switch CLIParser.parse(Array(CommandLine.arguments.dropFirst())) {
case .failure(let error):
    printErr("vigil: \(error.message)")
    exit(2)
case .success(let command):
    switch command {
    case .help:    print(CLIHelp.text)
    case .version: print("vigil \(CLIHelp.version)")
    case .status:  runStatus()
    case .holders: runHolders()
    case .drain:   await runDrain()
    case .stop(let pid): runStop(pid: pid)
    case .hold(let mode, let display): runHold(mode: mode, display: display)
    }
}
