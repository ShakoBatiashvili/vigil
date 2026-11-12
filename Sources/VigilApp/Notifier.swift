import Foundation
import UserNotifications
import VigilCore

/// Local notifications only. Everything is a no-op outside a real .app bundle
/// (UNUserNotificationCenter traps when there's no bundle identifier).
enum Notifier {
    static var isBundledApp: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    /// Asked lazily, the first time the user starts a session, never at launch.
    static func requestAuthorizationIfNeeded() {
        guard isBundledApp else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(_ notice: Notice) {
        guard isBundledApp else { return }
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
