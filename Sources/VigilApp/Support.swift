import AppKit
import SwiftUI
import VigilCore

/// SwiftUI has its own `Settings` scene type; ours is VigilCore's configuration struct.
typealias Settings = VigilCore.Settings

// MARK: - Design tokens (4 px spacing scale; radii 8 / 12)

enum Theme {
    /// The single accent: "the Mac is being held awake". Red is reserved for destructive confirmation.
    static let hold = Color(nsColor: .systemOrange)
    static let cardRadius: CGFloat = 12
    static let chipRadius: CGFloat = 8
    nonisolated(unsafe) static var panelHeight: CGFloat = 284
}

// MARK: - Scroll affordance

extension View {
    /// Softly fades the bottom edge so scrollable content signals there is more below.
    func bottomFade(_ height: CGFloat = 20) -> some View {
        mask(
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: height)
            }
        )
    }
}

// MARK: - Chips

/// A compact pill button. Selected state is tinted AND outlined, never color alone.
struct ChipStyle: ButtonStyle {
    var selected = false
    var minWidth: CGFloat? = nil
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minWidth: minWidth, minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
                    .fill(selected ? Theme.hold.opacity(0.20) : Color.primary.opacity(hovering ? 0.10 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
                    .strokeBorder(selected ? Theme.hold.opacity(0.60) : Color.clear, lineWidth: 1)
            )
            .foregroundStyle(Color.primary)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onHover { hovering = $0 }
            .contentShape(RoundedRectangle(cornerRadius: Theme.chipRadius))
    }
}

// MARK: - Card

struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
    }
}

// MARK: - App icons

@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(forBundlePath path: String) -> NSImage {
        if let hit = cache[path] { return hit }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
    }
}

/// An app icon, or a neutral glyph tile for daemons and CLI tools.
struct ProcessIcon: View {
    var bundlePath: String?
    var fallbackSymbol: String
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let bundlePath, FileManager.default.fileExists(atPath: bundlePath) {
                Image(nsImage: AppIcons.icon(forBundlePath: bundlePath)).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .overlay(Image(systemName: fallbackSymbol)
                        .font(.system(size: size * 0.5, weight: .medium))
                        .foregroundStyle(.secondary))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Skeleton

/// Placeholder row matching the real drain row's layout; pulses unless Reduce Motion is on.
struct SkeletonRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bright = false

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5).frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3).frame(width: 110, height: 9)
                Capsule().frame(height: 4)
            }
        }
        .foregroundStyle(Color.primary.opacity(bright ? 0.14 : 0.07))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { bright = true }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Empty state

struct EmptyState: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 26, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Panel visibility

/// Reports whether the panel's window is actually on screen, so sampling
/// (which costs energy) only happens while someone is looking.
struct WindowVisibilityReader: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> Tracker { Tracker(onChange: onChange) }
    func updateNSView(_ view: Tracker, context: Context) { view.onChange = onChange }

    final class Tracker: NSView {
        var onChange: (Bool) -> Void
        private var observers: [NSObjectProtocol] = []

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { onChange(false); return }
            let names: [Notification.Name] = [
                NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
            ]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.report()
                }
            }
            report()
        }

        private func report() {
            guard let window else { return onChange(false) }
            onChange(window.isVisible && window.occlusionState.contains(.visible))
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
