import SwiftUI
import VigilCore

/// What uses the most energy right now: honest numbers, grouped by app.
struct DrainView: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
            Spacer(minLength: 0)
            Text("Energy impact is the same score as in Activity Monitor. It's sampled only while this panel is open.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Biggest drains right now").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            if model.isSamplingDrain { ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 14, height: 14) }
            if let updated = model.drainUpdated {
                Text(updatedText(updated)).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.drain.isEmpty {
            if model.isSamplingDrain || model.drainUpdated == nil {
                VStack(spacing: 10) { ForEach(0..<6, id: \.self) { _ in SkeletonRow() } }   // known shape, ~2 s wait
            } else {
                EmptyState(symbol: "bolt.slash", title: "No energy data yet",
                           message: "macOS didn't return a sample. It will try again in a few seconds.")
            }
        } else {
            VStack(spacing: 8) {
                ForEach(model.drain) { item in DrainRow(item: item, maxShare: model.drain.map(\.share).max() ?? 1) }
            }
        }
    }

    private func updatedText(_ date: Date) -> String {
        let seconds = max(0, Int(model.now.timeIntervalSince(date)))
        return seconds < 5 ? "Updated just now" : "Updated \(seconds)s ago"
    }
}

struct DrainRow: View {
    var item: AppDrain
    var maxShare: Double

    var body: some View {
        HStack(spacing: 8) {
            ProcessIcon(bundlePath: item.bundlePath,
                        fallbackSymbol: item.isOther ? "ellipsis" : "gearshape.fill")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if item.processCount > 1 {
                        Text("×\(item.processCount)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text(String(format: "%.0f%%", item.share * 100))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(item.isOther ? Color.primary.opacity(0.25) : Color.primary.opacity(0.55))
                            .frame(width: max(4, proxy.size.width * CGFloat(item.share / max(maxShare, 0.0001))))
                    }
                    .animation(.easeOut(duration: 0.3), value: item.share)
                }
                .frame(height: 4)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(Int((item.share * 100).rounded())) percent of energy impact")
    }
}
