import Foundation
import Combine
import UserNotifications

@MainActor final class PhoneReminders: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var permission = "Optional: enable iPhone notifications for intake and movement reminders."
    private let center = UNUserNotificationCenter.current()
    private var generation = UUID()
    override init() { super.init(); center.delegate = self }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
    func requestPermission() async {
        do { let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge]); permission = granted ? "iPhone notifications enabled." : "Notifications are off. You can enable them in iPhone Settings." }
        catch { permission = "Could not request notifications: \(error.localizedDescription)" }
    }
    func apply(_ state: JournalState) async {
        let operation = UUID(); generation = operation
        let settings = await center.notificationSettings()
        let pending = await center.pendingNotificationRequests()
        guard generation == operation else { return }
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("bite-move-") }.map(\.identifier))
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let date = JournalDates.key(Date()), today = JournalSummary(entries: state.entries.filter { $0.date == date })
        if state.notifications, today.intake >= Int(ceil(Double(state.goal) * 0.85)) {
            let level = today.intake >= state.goal ? 100 : 85, key = "bite-intake-\(date)-\(level)"
            if !UserDefaults.standard.bool(forKey: key) {
                UserDefaults.standard.set(true, forKey: key)
                if level == 100 { UserDefaults.standard.set(true, forKey: "bite-intake-\(date)-85") }
                let content = UNMutableNotificationContent(); content.title = "Bite by Bite · Daily check-in"
                content.body = "You’ve logged \(Int((Double(today.intake) / Double(state.goal) * 100).rounded()))% of today’s food target. Use this estimate to plan your next meal, and listen to your hunger."
                try? await center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
            }
        }
        guard generation == operation, state.wellness.reminder.enabled else { return }
        let r = state.wellness.reminder, now = Date(), interval = Double(r.minutes * 60)
        let last = r.lastMovedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? now
        let snooze = r.snoozedUntil.map { Date(timeIntervalSince1970: $0 / 1000) } ?? now
        var next = max(now.addingTimeInterval(60), last.addingTimeInterval(interval), snooze)
        let end = now.addingTimeInterval(24 * 3600); var count = 0
        while next < end && count < 50 {
            let hour = Calendar.current.component(.hour, from: next)
            if hour >= r.startHour && hour < r.endHour {
                guard generation == operation else { return }
                let content = UNMutableNotificationContent(); content.title = "A moment to move?"
                content.body = "If you’ve been sitting, take a short walk or stretch when it suits you. Tap “I moved” in Bite by Bite to reset your timer."
                let id = "bite-move-\(operation.uuidString)-\(count)"
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: next)
                try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
                if generation != operation { center.removePendingNotificationRequests(withIdentifiers: [id]); return }
                count += 1
            }
            next = next.addingTimeInterval(interval)
        }
    }
}
