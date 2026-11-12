import AppKit
import SwiftUI

/// Entry point. `--snapshot <dir>` renders the panel to PNGs (light and dark) from
/// canned data and exits; it never touches power state, settings, or the network.
@main
struct VigilMain {
    static func main() {
        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: "--snapshot") {
            let directory = args.indices.contains(flag + 1) ? args[flag + 1] : "."
            MainActor.assumeIsolated { Snapshot.run(outputDirectory: directory) }
        } else {
            VigilApp.main()
        }
    }
}

struct VigilApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
