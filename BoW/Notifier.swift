import Foundation
import UserNotifications

/// Уведомления о том, что появилось на сервере: новая заметка о самочувствии и утренняя сводка советов.
/// Пуша нет и быть не может — Personal Team не даёт APNs, — поэтому уведомление ставит сам телефон,
/// когда iOS будит приложение (HealthKit, BGTask, открытие). Apple Watch зеркалят уведомление телефона
/// сами, пока он заперт, так что отдельного приложения для часов не нужно.
///
/// Что показывать, решает сервер (`GET /api/updates`, scripts/notify.py): он же следит, чтобы ночная
/// заметка не звонила и чтобы советы, приходящие четырьмя заходами, стали одной сводкой. Телефон помнит
/// только id того, что уже показал.
@MainActor
final class Notifier: ObservableObject {
    static let shared = Notifier()

    struct Item: Codable {
        let id: String
        let kind: String
        let title: String
        let body: String
        let page: String?
    }

    private struct Response: Codable { let items: [Item] }

    private let defaults = UserDefaults.standard
    private let seenKey = "notifiedIds"
    private let primedKey = "notifierPrimed"
    private let settings = SettingsStore.shared
    private let network = NetworkClient.shared
    /// Синк дёргается на каждое движение HealthKit; чаще раза в две минуты спрашивать нечего.
    private let minInterval: TimeInterval = 120
    private var lastCheck: Date?

    /// Спрашивать разрешение можно только там, где есть кому ответить, — из UI, не из фонового запуска.
    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .notDetermined else { return }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        ActivityLog.shared.log("Уведомления", detail: granted ? "разрешены" : "запрещены")
    }

    func check(trigger: String) async {
        guard settings.notifications else { return }
        if let t = lastCheck, Date().timeIntervalSince(t) < minInterval { return }
        lastCheck = Date()
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        do {
            let data = try await network.get(path: "api/updates", baseURL: settings.baseURL, authToken: settings.apiToken)
            let items = try JSONDecoder().decode(Response.self, from: data).items
            var seen = defaults.stringArray(forKey: seenKey) ?? []
            let known = Set(seen)
            let fresh = items.filter { !known.contains($0.id) }
            guard !fresh.isEmpty else { return }
            seen.append(contentsOf: fresh.map(\.id))
            if seen.count > 50 { seen.removeFirst(seen.count - 50) }
            defaults.set(seen, forKey: seenKey)
            // Первый запуск (или новая установка): то, что уже лежало на сервере, — не новость, а фон.
            guard defaults.bool(forKey: primedKey) else {
                defaults.set(true, forKey: primedKey)
                return
            }
            for item in fresh { await post(item) }
            ActivityLog.shared.log("Уведомление (\(trigger))", detail: fresh.map(\.title).joined(separator: ", "))
        } catch {
            // Сети может не быть — это не повод писать в журнал на каждом синке.
        }
    }

    private func post(_ item: Item) async {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        content.threadIdentifier = item.kind
        content.userInfo = ["page": item.page ?? ""]
        // trigger: nil — показать сейчас; id от сервера, так что повтор ничего не задвоит.
        let request = UNNotificationRequest(identifier: item.id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Тап по уведомлению: «site» — главная, остальное — страница сайта из «Ещё».
    static func open(page: String) {
        if let p = SiteController.others.first(where: { $0.id == page }) {
            AppState.shared.tab = .more
            AppState.shared.morePage = p
        } else {
            AppState.shared.morePage = nil
            AppState.shared.tab = .site
        }
    }
}
