import SwiftUI
import VigilCore

/// Title, status line, the master switch, and the one-tap presets.
struct HeaderSection: View {
    var model: AppModel
    @State private var choosingTime = false
    @State private var untilTime = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()

    private var untilSelected: Bool {
        if case .until = model.manualMode { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vigil").font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 6) {
                        Circle()
                            .fill(model.decision.hold ? Theme.hold : Color.secondary.opacity(0.5))
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(model.statusLine)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .animation(.easeOut(duration: 0.25), value: model.decision.hold)
                }
                Spacer(minLength: 8)
                Toggle("Keep awake", isOn: Binding(
                    get: { model.manualActive },
                    set: { $0 ? model.startSession(.indefinite) : model.stopSession() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Theme.hold)
                .accessibilityLabel("Keep awake")
            }

            HStack(spacing: 6) {
                preset("30 min", .timed(seconds: 1_800))
                preset("1 hr", .timed(seconds: 3_600))
                preset("4 hr", .timed(seconds: 14_400))
                Button("Until…") {
                    if untilSelected { model.stopSession() } else { choosingTime.toggle() }
                }
                .buttonStyle(ChipStyle(selected: untilSelected || choosingTime))
                preset("No limit", .indefinite)
            }

            if choosingTime { untilRow.transition(.opacity.combined(with: .move(edge: .top))) }

            if let note = HoldSummary.displayNote(decision: model.decision) {
                HStack(spacing: 6) {
                    Label(note, systemImage: "display")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Keep screen on") { model.setKeepDisplayOn(true) }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.hold)
                        .fixedSize()
                }
            }

            if let note = model.overrideNote {
                Label(note, systemImage: "battery.25")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.easeOut(duration: 0.2), value: choosingTime)
    }

    private func preset(_ title: String, _ mode: SessionMode) -> some View {
        Button(title) { model.toggleSession(mode) }
            .buttonStyle(ChipStyle(selected: model.manualMode == mode))
    }

    private var untilRow: some View {
        HStack(spacing: 8) {
            DatePicker("Until", selection: $untilTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.stepperField)
            Spacer()
            Button("Cancel") { choosingTime = false }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Button("Hold until \(clockText)") {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: untilTime)
                if let mode = SessionMode.makeUntil(hour: parts.hour ?? 18, minute: parts.minute ?? 0) {
                    model.startSession(mode)
                }
                choosingTime = false
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.hold)
            .controlSize(.small)
        }
    }

    private var clockText: String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: untilTime)
        return Formatting.clock(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }
}

/// Watts, time left, and a charge bar with the guard threshold marked on it.
struct BatteryCard: View {
    var model: AppModel

    var body: some View {
        if let percent = model.battery.percent {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(headline)
                                .font(.system(size: 22, weight: .semibold))
                                .monospacedDigit()
                            Text(subline)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("\(percent)%", systemImage: symbol(percent))
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                    }
                    ChargeBar(percent: percent, threshold: model.settings.batteryThreshold, onAC: model.battery.onAC)
                    HStack {
                        Text("Releases below \(model.settings.batteryThreshold)% on battery")
                        Spacer()
                        if let cycles = model.battery.cycleCount { Text("\(cycles) cycles") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var headline: String {
        let b = model.battery
        if !b.onAC { return b.watts.map(Formatting.watts) ?? "—" }
        return b.isCharging ? "Charging" : "Plugged in"
    }

    private var subline: String {
        let b = model.battery
        if !b.onAC {
            guard let minutes = b.timeRemainingMinutes else { return "from the battery · estimating time left…" }
            return "from the battery · ~\(Formatting.duration(Double(minutes) * 60)) left"
        }
        if b.isCharging, let watts = b.watts { return "at \(Formatting.watts(watts))" }
        return "on power adapter"
    }

    private func symbol(_ percent: Int) -> String {
        if model.battery.isCharging { return "battery.100.bolt" }
        switch percent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default:    return "battery.100"
        }
    }
}

/// A 6 pt capsule: neutral fill, orange once below the guard, a tick at the threshold.
struct ChargeBar: View {
    var percent: Int
    var threshold: Int
    var onAC: Bool

    private var below: Bool { !onAC && percent < threshold }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(below ? Theme.hold : Color.primary.opacity(0.55))
                    .frame(width: max(6, width * CGFloat(percent) / 100))
                Rectangle()
                    .fill(Color.primary.opacity(0.75))
                    .frame(width: 2, height: 10)
                    .offset(x: width * CGFloat(threshold) / 100 - 1)
            }
            .animation(.easeOut(duration: 0.3), value: percent)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}
