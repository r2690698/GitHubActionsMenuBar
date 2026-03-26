import Foundation

enum PreferencesStore {
    private static let notificationsKey = "notification-preferences"

    static func loadNotificationPreferences() -> NotificationPreferences {
        guard
            let data = UserDefaults.standard.data(forKey: notificationsKey),
            let preferences = try? JSONDecoder().decode(NotificationPreferences.self, from: data)
        else {
            return NotificationPreferences()
        }

        return preferences
    }

    static func saveNotificationPreferences(_ preferences: NotificationPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else {
            return
        }

        UserDefaults.standard.set(data, forKey: notificationsKey)
    }
}
