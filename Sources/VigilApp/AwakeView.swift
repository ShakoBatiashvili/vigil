import SwiftUI
import VigilCore

/// Everything currently holding the Mac awake, oldest first, with stale holds flagged.
struct AwakeView: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Keeping this Mac awake").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            if model.hasStaleHolder { staleBanner }
            if model.holders.isEmpty {
                EmptyState(symbol: "moon.zzz", title: "Nothing is holding it awake",
                           message: "Your Mac will sleep on its normal schedule.")
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.holders) { HolderRow(holder: $0, model: model) }
                    }
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.never)
                .bottomFade()
            }
        }
    }

    private var staleBanner: some View {
        Label("Something has held your Mac awake for 12 hours or more.", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.primary)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).fill(Theme.hold.opacity(0.18)))
            .symbolRenderingMode(.multicolor)
    }
}

struct HolderRow: View {
    var holder: SleepHolder
    var model: AppModel

    private var severity: HolderSeverity { HolderAssessment.severity(heldSeconds: holder.heldSeconds) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ProcessIcon(
                bundlePath: holder.executablePath.flatMap(DrainModel.bundlePath(fromPath:)),
                fallbackSymbol: holder.kind == .display ? "display" : "moon.zzz.fill"
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(holder.processName).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if model.isOwn(holder) { tag("this app") }
                    if holder.kind == .display { tag("display") }
                }
                if let parent = holder.parentName, !model.isOwn(holder) {
                    Text("started by \(parent)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                if !holder.reason.isEmpty {
                    Text(holder.reason).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                heldBadge
                if model.isStoppable(holder) { StopButton(processName: holder.processName) { model.stopHolder(holder) } }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
                .fill(severity == .stale ? Theme.hold.opacity(0.14) : Color.primary.opacity(0.04))
        )
        .accessibilityElement(children: .contain)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(Color.primary.opacity(0.10)))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var heldBadge: some View {
        let text = Formatting.duration(holder.heldSeconds)
        switch severity {
        case .normal:
            Text(text).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        case .long:
            Label(text, systemImage: "clock.fill").font(.caption.weight(.semibold).monospacedDigit())
                .symbolRenderingMode(.multicolor).foregroundStyle(.primary)
        case .stale:
            Label(text, systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.bold).monospacedDigit())
                .symbolRenderingMode(.multicolor).foregroundStyle(.primary)
        }
    }
}

/// Two-step stop: the first click arms it (the second is ignored for half a second
/// so a double-click can't confirm), it turns red, and it disarms itself after 4 seconds.
struct StopButton: View {
    var processName: String
    var action: () -> Void
    @State private var armed = false
    @State private var confirmable = false
    @State private var disarm: Task<Void, Never>?

    var body: some View {
        Button(armed ? "Confirm stop" : "Stop") {
            if !armed {
                armed = true
                confirmable = false
                disarm?.cancel()
                disarm = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if !Task.isCancelled { confirmable = true }
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    if !Task.isCancelled { armed = false; confirmable = false }
                }
            } else if confirmable {
                disarm?.cancel()
                armed = false
                confirmable = false
                action()
            }
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
        .tint(armed ? .red : nil)
        .animation(.easeOut(duration: 0.15), value: armed)
        .help("Ask \(processName) to quit. Only your own caffeinate can be stopped from here.")
        .accessibilityLabel(armed ? "Confirm stopping \(processName)" : "Stop \(processName)")
    }
}
