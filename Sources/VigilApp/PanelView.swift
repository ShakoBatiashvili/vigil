import AppKit
import SwiftUI
import VigilCore

struct PanelView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            HeaderSection(model: model)
            BatteryCard(model: model)

            Picker("View", selection: $model.selectedTab) {
                ForEach(PanelTab.allCases) { tab in Text(model.tabLabel(tab)).tag(tab) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Fixed height: switching tabs never moves anything else.
            Group {
                switch model.selectedTab {
                case .drain: DrainView(model: model)
                case .awake: AwakeView(model: model)
                case .rules: RulesView(model: model)
                }
            }
            .id(model.selectedTab)
            .transition(.opacity)
            .frame(height: Theme.panelHeight, alignment: .top)
            .clipped()
            .animation(.easeOut(duration: 0.15), value: model.selectedTab)

            Divider()
            FooterBar(model: model)
        }
        .padding(16)
        .frame(width: 340)
        .background(WindowVisibilityReader { visible in
            Task { @MainActor in model.setPanelVisible(visible) }
        })
    }
}

struct FooterBar: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
                .disabled(!Notifier.isBundledApp && model.isLive)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if let note = model.launchNote {
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// The status-item label: a cup (filled while holding) and a compact countdown for timed holds.
struct MenuBarLabel: View {
    var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: model.decision.hold ? "cup.and.saucer.fill" : "cup.and.saucer")
            if let text = model.menuBarText { Text(text).monospacedDigit() }
        }
        .accessibilityLabel(model.decision.hold ? "Vigil: holding awake" : "Vigil: not holding")
    }
}
