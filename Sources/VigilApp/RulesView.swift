import SwiftUI
import VigilCore

/// Settings. Everything applies instantly; "Saved" appears only once the write has landed.
struct RulesView: View {
    var model: AppModel
    @State private var typedName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                batterySection
                displaySection
                appsSection
                scheduleSection
            }
            .padding(.trailing, 4)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.automatic)
        .bottomFade()
    }

    // MARK: Save status (shown beside the first section title; appears only after the write landed)

    @ViewBuilder
    private var saveBadge: some View {
        switch model.saveStatus {
        case .idle:
            EmptyView()
        case .saved:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.secondary)
                .transition(.opacity)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).symbolRenderingMode(.multicolor).lineLimit(1)
        }
    }

    // MARK: Sections

    private var batterySection: some View {
        RuleSection("On battery", trailing: { saveBadge.animation(.easeOut(duration: 0.2), value: model.saveStatus) }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Release below").font(.system(size: 12))
                    Spacer()
                    if model.settings.batteryThreshold != 20 {
                        Button("Reset") { model.setThreshold(20) }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("\(model.settings.batteryThreshold)%")
                        .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { Double(model.settings.batteryThreshold) },
                        set: { model.setThreshold(Int($0)) }
                    ),
                    in: Double(Settings.thresholdRange.lowerBound)...Double(Settings.thresholdRange.upperBound),
                    step: 5
                )
                .tint(Theme.hold)
                .accessibilityLabel("Release below percent")
                hint("Below this on battery, your Mac can sleep again.")
            }
        }
    }

    private var displaySection: some View {
        RuleSection("Display") {
            Toggle("Also keep the display on", isOn: Binding(
                get: { model.settings.keepDisplayOn }, set: { model.setKeepDisplayOn($0) }
            ))
            .toggleStyle(.switch).tint(Theme.hold).font(.system(size: 12))
            hint("Off: the screen can still sleep.")
        }
    }

    private var appsSection: some View {
        RuleSection("Keep awake while these apps run") {
            if model.settings.watchedProcesses.isEmpty {
                hint("None yet. Pick an open app, or type its name.")
            } else {
                VStack(spacing: 4) {
                    ForEach(model.settings.watchedProcesses, id: \.self) { name in
                        HStack {
                            Text(name).font(.system(size: 12)).lineLimit(1)
                            Spacer()
                            Button { model.removeWatchedProcess(name) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Stop watching \(name)")
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
                            .fill(Color.primary.opacity(0.05)))
                    }
                }
            }
            HStack(spacing: 8) {
                Menu {
                    let names = model.runningAppNames()
                    if names.isEmpty { Text("No other apps are open") }
                    ForEach(names, id: \.self) { name in Button(name) { model.addWatchedProcess(name) } }
                } label: {
                    Label("Add open app", systemImage: "plus")
                }
                .menuStyle(.borderlessButton).fixedSize()
                TextField("or type a name", text: $typedName)
                    .textFieldStyle(.roundedBorder).font(.system(size: 12))
                    .onSubmit {
                        if let name = ProcessTrigger.normalize(typedName) { model.addWatchedProcess(name) }
                        typedName = ""
                    }
            }
            if model.settings.watchedProcesses.count >= Settings.maxWatchedProcesses {
                hint("That's the limit of \(Settings.maxWatchedProcesses) apps.")
            }
        }
    }

    private var scheduleSection: some View {
        RuleSection("Schedule") {
            Toggle("Keep awake on a schedule", isOn: Binding(
                get: { model.settings.scheduleEnabled }, set: { model.setScheduleEnabled($0) }
            ))
            .toggleStyle(.switch).tint(Theme.hold).font(.system(size: 12))

            if model.settings.scheduleEnabled, let window = model.settings.schedule {
                HStack(spacing: 4) {
                    ForEach(Self.days, id: \.number) { day in
                        Button(day.letter) { toggle(day: day.number, in: window) }
                            .buttonStyle(ChipStyle(selected: window.weekdays.contains(day.number), minWidth: 28))
                            .accessibilityLabel(day.name)
                            .accessibilityAddTraits(window.weekdays.contains(day.number) ? .isSelected : [])
                    }
                }
                HStack(spacing: 8) {
                    DatePicker("From", selection: timeBinding(window, start: true), displayedComponents: .hourAndMinute)
                        .labelsHidden().datePickerStyle(.stepperField)
                    Text("to").font(.system(size: 12)).foregroundStyle(.secondary)
                    DatePicker("To", selection: timeBinding(window, start: false), displayedComponents: .hourAndMinute)
                        .labelsHidden().datePickerStyle(.stepperField)
                }
                if window.endMinute <= window.startMinute { hint("Ends the next morning.") }
            }
        }
    }

    // MARK: Helpers

    private static let days: [(number: Int, letter: String, name: String)] = [
        (2, "M", "Monday"), (3, "T", "Tuesday"), (4, "W", "Wednesday"), (5, "T", "Thursday"),
        (6, "F", "Friday"), (7, "S", "Saturday"), (1, "S", "Sunday"),
    ]

    private func hint(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    /// The last selected day can't be switched off: a window needs at least one day.
    private func toggle(day: Int, in window: TimeWindow) {
        var days = window.weekdays
        if days.contains(day) { days.remove(day) } else { days.insert(day) }
        if let next = TimeWindow.make(weekdays: days, startMinute: window.startMinute, endMinute: window.endMinute) {
            model.setSchedule(next)
        }
    }

    /// Picking identical start and end times is ignored rather than silently switching the schedule off.
    private func timeBinding(_ window: TimeWindow, start: Bool) -> Binding<Date> {
        Binding(
            get: {
                let minutes = start ? window.startMinute : window.endMinute
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                let next = TimeWindow.make(
                    weekdays: window.weekdays,
                    startMinute: start ? minutes : window.startMinute,
                    endMinute: start ? window.endMinute : minutes
                )
                if let next { model.setSchedule(next) }
            }
        )
    }
}

struct RuleSection<Content: View, Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    init(_ title: String,
         @ViewBuilder trailing: @escaping () -> Trailing,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                trailing()
            }
            content()
        }
    }
}

extension RuleSection where Trailing == EmptyView {
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title, trailing: { EmptyView() }, content: content)
    }
}
