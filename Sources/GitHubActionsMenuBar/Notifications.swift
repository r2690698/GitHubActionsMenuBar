import Foundation
import UserNotifications

struct NotificationManager {
    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    func sendTestNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "GitHub Actions Menu Bar"
        content.body = "Test notification delivered successfully."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "test-notification",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    func notifyLatestRun(for repoStatus: RepoActionStatus, preferences: NotificationPreferences) async {
        guard let latestRun = repoStatus.latestRun else { return }

        let runState = latestRun.runState
        let body: String

        switch runState {
        case .running, .queued:
            guard preferences.notifyOnStarted else { return }
            body = "\(latestRun.displayTitle) started"
        case .failure:
            guard preferences.notifyOnFailed else { return }
            body = "\(latestRun.displayTitle) failed"
        case .success:
            guard preferences.notifyOnPassed else { return }
            body = "\(latestRun.displayTitle) passed"
        default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(repoStatus.repository.fullName)"
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "workflow-run-\(repoStatus.repository.id)-\(latestRun.id)",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}
