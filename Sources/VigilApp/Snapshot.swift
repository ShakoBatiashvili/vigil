import AppKit
import SwiftUI
import VigilCore
import VigilSystem

/// Canned data for screenshots, so the UI can be reviewed without a live Mac state.
struct PreviewScenario {
    var tab: PanelTab
    var now: Date
    var settings: Settings
    var battery: BatterySnapshot
    var state: VigilState
    var decision: Decision
    var holders: [SleepHolder]
    var drain: [AppDrain]
    var sampling = false
    var launchAtLogin = false

    static func holding(tab: PanelTab, now: Date = Date()) -> PreviewScenario {
        var settings = Settings()
        settings.watchedProcesses = ["Xcode", "Docker Desktop"]
        settings.scheduleEnabled = true
        settings.schedule = TimeWindow.make(weekdays: [2, 3, 4, 5, 6], startMinute: 9 * 60, endMinute: 18 * 60)

        var state = VigilState()
        state.manual = ManualSession(mode: .timed(seconds: 14_400), started: now.addingTimeInterval(-2_880),
                                     end: now.addingTimeInterval(11_520))
        state.holding = true

        let me = getuid()
        let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        return PreviewScenario(
            tab: tab, now: now, settings: settings,
            battery: BatterySnapshot(percent: 46, onAC: false, isCharging: false, watts: 12.1,
                                     timeRemainingMinutes: 157, cycleCount: 428),
            state: state,
            decision: Decision(hold: true, holdDisplay: false, reasons: [.manual(until: state.manual?.end)],
                               blockedByGuard: false, effects: []),
            holders: [
                SleepHolder(pid: 44321, processName: "caffeinate", executablePath: "/usr/bin/caffeinate", kind: .system,
                            reason: "caffeinate command-line tool", heldSeconds: 293_346, ownerUID: me, parentName: "zsh"),
                SleepHolder(pid: 400, processName: "powerd", executablePath: "/usr/libexec/powerd", kind: .system,
                            reason: "Powerd - Prevent sleep while display is on", heldSeconds: 5_820, ownerUID: 0),
                SleepHolder(pid: 2456, processName: "Google Chrome", executablePath: chrome, kind: .system,
                            reason: "Playing audio", heldSeconds: 660, ownerUID: me),
                SleepHolder(pid: 66876, processName: "caffeinate", executablePath: "/usr/bin/caffeinate", kind: .system,
                            reason: "caffeinate command-line tool", heldSeconds: 70, ownerUID: me, parentName: "claude"),
                SleepHolder(pid: ProcessInfo.processInfo.processIdentifier, processName: "Vigil", executablePath: nil,
                            kind: .system, reason: "Vigil: manual hold", heldSeconds: 2_880, ownerUID: me),
            ],
            drain: [
                AppDrain(id: "chrome", name: "Google Chrome", bundlePath: "/Applications/Google Chrome.app",
                         power: 29, share: 0.29, processCount: 6, isOther: false),
                AppDrain(id: "ws", name: "WindowServer", bundlePath: nil, power: 12, share: 0.12, processCount: 1, isOther: false),
                AppDrain(id: "term", name: "Terminal", bundlePath: "/System/Applications/Utilities/Terminal.app",
                         power: 10, share: 0.10, processCount: 1, isOther: false),
                AppDrain(id: "claude", name: "claude", bundlePath: nil, power: 8, share: 0.08, processCount: 5, isOther: false),
                AppDrain(id: "audio", name: "coreaudiod", bundlePath: nil, power: 8, share: 0.08, processCount: 1, isOther: false),
                AppDrain(id: "xcode", name: "Xcode", bundlePath: "/Applications/Xcode.app",
                         power: 7, share: 0.07, processCount: 3, isOther: false),
                AppDrain(id: "other", name: "Other", bundlePath: nil, power: 26, share: 0.26, processCount: 38, isOther: true),
            ]
        )
    }

    /// Nothing held, first drain sample still loading: the skeleton state.
    static func idleLoading(now: Date = Date()) -> PreviewScenario {
        var scenario = holding(tab: .drain, now: now)
        scenario.state = VigilState()
        scenario.decision = Decision(hold: false, holdDisplay: false, reasons: [], blockedByGuard: false, effects: [])
        scenario.drain = []
        scenario.holders = []
        scenario.sampling = true
        scenario.battery = BatterySnapshot(percent: 82, onAC: true, isCharging: true, watts: 24.3,
                                           timeRemainingMinutes: nil, cycleCount: 428)
        scenario.settings = Settings()
        return scenario
    }

    /// The battery guard released a rule-driven hold.
    static func guardPaused(now: Date = Date()) -> PreviewScenario {
        var scenario = holding(tab: .awake, now: now)
        scenario.state = VigilState()
        scenario.state.guardTripped = true
        scenario.decision = Decision(hold: false, holdDisplay: false, reasons: [.process("Xcode")],
                                     blockedByGuard: true, effects: [])
        scenario.battery = BatterySnapshot(percent: 17, onAC: false, isCharging: false, watts: 9.4,
                                           timeRemainingMinutes: 48, cycleCount: 428)
        scenario.holders = []
        return scenario
    }
}

/// A borderless window that may become key, so snapshot controls render as they do in the live popover.
private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
enum Snapshot {
    static func run(outputDirectory: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)   // so controls draw in their active, tinted style

        let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let jobs: [(String, PreviewScenario, NSAppearance.Name)] = [
            ("holding-drain-light", .holding(tab: .drain), .aqua),
            ("holding-drain-dark", .holding(tab: .drain), .darkAqua),
            ("holding-awake-light", .holding(tab: .awake), .aqua),
            ("holding-awake-dark", .holding(tab: .awake), .darkAqua),
            ("holding-rules-light", .holding(tab: .rules), .aqua),
            ("holding-rules-dark", .holding(tab: .rules), .darkAqua),
            ("idle-loading-light", .idleLoading(), .aqua),
            ("guard-paused-dark", .guardPaused(), .darkAqua),
        ]
        for (name, scenario, appearance) in jobs {
            render(name: name, scenario: scenario, appearance: appearance, into: directory)
        }
        // Everything in Rules, including what scrolls below the fold.
        Theme.panelHeight = 700
        render(name: "rules-full-light", scenario: .holding(tab: .rules), appearance: .aqua, into: directory)
        print("Wrote \(jobs.count + 1) screenshots to \(directory.path)")
        exit(0)
    }

    private static func render(name: String, scenario: PreviewScenario, appearance: NSAppearance.Name, into directory: URL) {
        let model = AppModel(preview: scenario)
        // Opaque background (the real popover's material is drawn by the window, not the view).
        let root = PanelView(model: model).background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)

        let window = KeyWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -6_000, y: -6_000))   // rendered, but never on screen
        window.makeKeyAndOrderFront(nil)   // key, so controls draw in their active (tinted) style

        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        window.orderOut(nil)
    }
}
