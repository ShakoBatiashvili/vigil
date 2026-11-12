import AppKit
import Observation
import ServiceManagement
import SwiftUI
import VigilCore
import VigilSystem

enum PanelTab: String, CaseIterable, Identifiable {
    case drain, awake, rules
    var id: String { rawValue }
}

enum SaveStatus: Equatable {
    case idle
    case saved
    case failed(String)
}

/// Orchestration only. Every decision ("should the Mac stay awake?", "is this
/// holder stoppable?", "what should the status line say?") lives in the tested
/// VigilCore / VigilSystem layers; this class feeds them facts and applies the answers.
@MainActor
@Observable
final class AppModel {
    // MARK: Policy state

    private(set) var state = VigilState()
    private(set) var decision = Decision(hold: false, holdDisplay: false, reasons: [], blockedByGuard: false, effects: [])
    private(set) var settings: Settings
    private(set) var battery: BatterySnapshot
    private(set) var now = Date()

    // MARK: Panel data (only refreshed while the panel is open)

    private(set) var holders: [SleepHolder] = []
    private(set) var drain: [AppDrain] = []
    private(set) var drainUpdated: Date?
    private(set) var isSamplingDrain = false
    private(set) var saveStatus: SaveStatus = .idle
    private(set) var launchAtLogin = false
    private(set) var launchNote: String?
    private(set) var panelVisible = false
    var selectedTab: PanelTab = .drain

    // MARK: Plumbing

    let isLive: Bool
    @ObservationIgnored private let power = PowerHold()
    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private var tickTimer: Timer?
    @ObservationIgnored private var tickInterval: TimeInterval = 0
    @ObservationIgnored private var panelTimer: Timer?
    @ObservationIgnored private var drainTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var saveResetTask: Task<Void, Never>?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    // MARK: Init

    init(store: SettingsStore = SettingsStore()) {
        isLive = true
        self.store = store
        settings = store.load()
        battery = BatteryReader.read()
        refreshLaunchAtLogin()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushSave(); self?.power.releaseAll() }
        }
        tick()
    }

    /// Static data for screenshots and previews: no timers, no assertions, no disk.
    init(preview: PreviewScenario) {
        isLive = false
        store = SettingsStore(directory: URL(fileURLWithPath: "/dev/null"))
        settings = preview.settings
        battery = preview.battery
        now = preview.now
        state = preview.state
        decision = preview.decision
        holders = preview.holders
        drain = preview.drain
        drainUpdated = preview.drain.isEmpty ? nil : preview.now.addingTimeInterval(-4)
        isSamplingDrain = preview.sampling
        selectedTab = preview.tab
        launchAtLogin = preview.launchAtLogin
    }

    // MARK: Derived text (all wording is in VigilCore)

    var statusLine: String {
        HoldSummary.statusLine(decision: decision, now: now, threshold: settings.batteryThreshold)
    }

    var menuBarText: String? { HoldSummary.menuBarText(decision: decision, now: now) }

    var manualMode: SessionMode? { state.manual?.mode }
    var manualActive: Bool { state.manual != nil }

    /// A note shown when the user deliberately started below the guard threshold.
    var overrideNote: String? {
        guard state.guardOverride, manualActive, let percent = battery.percent else { return nil }
        return "Battery is at \(percent)%, below your \(settings.batteryThreshold)% guard. "
            + "Continuing because you asked; it stops at \(Settings.thresholdRange.lowerBound)%."
    }

    var hasStaleHolder: Bool {
        holders.contains { HolderAssessment.severity(heldSeconds: $0.heldSeconds) == .stale }
    }

    func tabLabel(_ tab: PanelTab) -> String {
        switch tab {
        case .drain: return "Drain"
        case .rules: return "Rules"
        case .awake:
            if hasStaleHolder { return "Awake ⚠︎" }
            return holders.isEmpty ? "Awake" : "Awake \(holders.count)"
        }
    }

    func isOwn(_ holder: SleepHolder) -> Bool { holder.pid == ProcessInfo.processInfo.processIdentifier }

    func isStoppable(_ holder: SleepHolder) -> Bool {
        !isOwn(holder) && HolderAssessment.isStoppable(
            executablePath: holder.executablePath, ownerUID: holder.ownerUID, currentUID: getuid()
        )
    }

    // MARK: Sessions

    func startSession(_ mode: SessionMode) {
        guard isLive else { return }
        now = Date()
        battery = BatteryReader.read()
        state = Engine.start(state, mode: mode, now: now, battery: battery.reading, settings: settings)
        Notifier.requestAuthorizationIfNeeded()
        tick()
    }

    func stopSession() {
        guard isLive else { return }
        state = Engine.stop(state)
        tick()
    }

    /// Chips behave like toggles: tapping the active one stops the session.
    func toggleSession(_ mode: SessionMode) {
        manualMode == mode ? stopSession() : startSession(mode)
    }

    // MARK: The tick

    func tick() {
        guard isLive else { return }
        now = Date()
        battery = BatteryReader.read()
        // Only scan processes if a rule actually needs them (self-cost).
        let names = settings.watchedProcesses.isEmpty ? [] : ProcessLister.runningNames()
        let result = Engine.tick(
            state,
            inputs: Inputs(now: now, settings: settings, runningNames: names, battery: battery.reading)
        )
        state = result.state
        decision = result.decision

        power.apply(
            system: decision.hold,
            display: decision.holdDisplay,
            reason: HoldSummary.assertionName(for: decision.reasons)
        )
        for effect in decision.effects {
            Notifier.post(Notices.notice(for: effect, threshold: settings.batteryThreshold))
        }
        scheduleTick()
    }

    /// Wake every 5 s while there's something to watch; every 30 s when idle.
    private func scheduleTick() {
        let busy = state.manual != nil || state.holding
            || !settings.watchedProcesses.isEmpty
            || (settings.scheduleEnabled && settings.schedule != nil)
        let interval: TimeInterval = busy ? 5 : 30
        guard interval != tickInterval || tickTimer == nil else { return }
        tickInterval = interval
        tickTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = interval * 0.25
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    // MARK: Panel visibility

    func setPanelVisible(_ visible: Bool) {
        guard isLive, visible != panelVisible else { return }
        panelVisible = visible
        visible ? startPanelUpdates() : stopPanelUpdates()
    }

    private func startPanelUpdates() {
        refreshLive()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshLive() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        panelTimer = timer

        drainTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.sampleDrain()
                try? await Task.sleep(nanoseconds: 8_000_000_000)
            }
        }
    }

    private func stopPanelUpdates() {
        panelTimer?.invalidate()
        panelTimer = nil
        drainTask?.cancel()
        drainTask = nil
    }

    private func refreshLive() {
        now = Date()
        battery = BatteryReader.read()
        holders = HolderReader.read()
    }

    private func sampleDrain() async {
        isSamplingDrain = true
        let rows = await EnergyReader.sample()
        let grouped = DrainModel.group(rows, top: 6)
        // A failed sample must not wipe good data already on screen.
        if !grouped.isEmpty || drain.isEmpty {
            drain = grouped
            drainUpdated = Date()
        }
        isSamplingDrain = false
    }

    func stopHolder(_ holder: SleepHolder) {
        guard isLive, isStoppable(holder), HolderControl.stop(holder) else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self?.refreshLive()
        }
    }

    // MARK: Settings (applied immediately, written to disk after a short debounce)

    private func update(_ change: (inout Settings) -> Void) {
        var next = settings
        change(&next)
        settings = next.validated()
        persistSoon()
        tick()
    }

    func setThreshold(_ value: Int) { update { $0.batteryThreshold = value } }
    func setKeepDisplayOn(_ on: Bool) { update { $0.keepDisplayOn = on } }
    func addWatchedProcess(_ name: String) { update { $0.watchedProcesses.append(name) } }
    func removeWatchedProcess(_ name: String) {
        update { $0.watchedProcesses.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame } }
    }

    func setScheduleEnabled(_ on: Bool) {
        update {
            if on && $0.schedule == nil {
                $0.schedule = TimeWindow.make(weekdays: [2, 3, 4, 5, 6], startMinute: 9 * 60, endMinute: 18 * 60)
            }
            $0.scheduleEnabled = on
        }
    }

    func setSchedule(_ window: TimeWindow) { update { $0.schedule = window } }

    private func persistSoon() {
        guard isLive else { return }
        pendingSave?.cancel()
        pendingSave = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.writeSettings()
        }
    }

    func flushSave() {
        guard isLive, pendingSave != nil else { return }
        pendingSave?.cancel()
        writeSettings()
    }

    private func writeSettings() {
        pendingSave = nil
        do {
            try store.save(settings)
            saveStatus = .saved   // only after the write actually landed
            saveResetTask?.cancel()
            saveResetTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                if !Task.isCancelled { self?.saveStatus = .idle }
            }
        } catch {
            saveStatus = .failed("Couldn't save settings: \(error.localizedDescription)")
        }
    }

    // MARK: Launch at login

    private func refreshLaunchAtLogin() {
        guard Notifier.isBundledApp else {
            launchAtLogin = false
            launchNote = "Available when running as Vigil.app"
            return
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ on: Bool) {
        guard isLive, Notifier.isBundledApp else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchNote = nil
        } catch {
            launchNote = "Couldn't change login item: \(error.localizedDescription)"
        }
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if on && status == .requiresApproval {
            launchNote = "Approve Vigil in System Settings ▸ General ▸ Login Items."
        }
    }

    // MARK: Running apps for the "add" menu

    func runningAppNames() -> [String] {
        let taken = Set(settings.watchedProcesses.map { $0.lowercased() })
        let names = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.localizedName)
            .filter { !taken.contains($0.lowercased()) && $0 != "Vigil" }
        return Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
