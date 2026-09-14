import Foundation

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var serverURL: String {
        didSet { defaults.set(serverURL, forKey: Keys.serverURL) }
    }
    @Published var apiToken: String {
        didSet { defaults.set(apiToken, forKey: Keys.apiToken) }
    }
    /// The mini on the home Wi-Fi. Without a VPN the home ISP drops Cloudflare, so at home the app talks to
    /// the mini directly; away from home (or with the VPN routing everything) it falls back to `serverURL`.
    @Published var lanURL: String {
        didSet { defaults.set(lanURL, forKey: Keys.lanURL) }
    }
    @Published private(set) var lanReachable = false
    private var lanProbedAt: Date?

    /// Where every request goes right now.
    var baseURL: String { lanReachable && !lanURL.trimmingCharacters(in: .whitespaces).isEmpty ? lanURL : serverURL }
    var routeName: String { lanReachable ? "домашняя сеть" : "интернет" }

    /// One quick look at the LAN address (1.5 s); the answer is reused for a minute.
    @MainActor
    func probeLAN(force: Bool = false) async {
        let lan = lanURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lan.isEmpty, let url = NetworkClient.shared.absoluteURL(path: "healthz", baseURL: lan) else {
            lanReachable = false
            return
        }
        if !force, let t = lanProbedAt, Date().timeIntervalSince(t) < 60 { return }
        lanProbedAt = Date()
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 3
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let ok: Bool
        if let (_, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse {
            ok = (200..<300).contains(http.statusCode)
        } else {
            ok = false
        }
        if ok != lanReachable {
            ActivityLog.shared.log("Маршрут", detail: ok ? "mini по домашней сети" : "через интернет")
        }
        lanReachable = ok
    }
    @Published var enableWorkouts: Bool {
        didSet { defaults.set(enableWorkouts, forKey: Keys.enableWorkouts) }
    }
    @Published var enableSleep: Bool {
        didSet { defaults.set(enableSleep, forKey: Keys.enableSleep) }
    }
    @Published var enableHRV: Bool {
        didSet { defaults.set(enableHRV, forKey: Keys.enableHRV) }
    }
    @Published var enableRestingHR: Bool {
        didSet { defaults.set(enableRestingHR, forKey: Keys.enableRestingHR) }
    }
    @Published var enableSteps: Bool {
        didSet { defaults.set(enableSteps, forKey: Keys.enableSteps) }
    }
    @Published var enableActiveEnergy: Bool {
        didSet { defaults.set(enableActiveEnergy, forKey: Keys.enableActiveEnergy) }
    }
    @Published var devMode: Bool {
        didSet { defaults.set(devMode, forKey: Keys.devMode) }
    }
    /// Lectures are 150–200 MB each; by default they come down over Wi-Fi only.
    @Published var wifiOnly: Bool {
        didSet {
            defaults.set(wifiOnly, forKey: Keys.wifiOnly)
            DownloadManager.shared.applySettingsChange()
        }
    }

    private let defaults = UserDefaults.standard

    private init() {
        let defaultServerURL = "https://api.bodywithoutorgans.cc"
        let legacyServerURLs = Set(["http://192.168.1.41:8080", "http://192.168.1.149:8080", "https://api.bodywithoutorgans.cc/healthz"])
        if let storedServerURL = defaults.string(forKey: Keys.serverURL)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !storedServerURL.isEmpty,
           !legacyServerURLs.contains(storedServerURL) {
            serverURL = storedServerURL
        } else {
            serverURL = defaultServerURL
            defaults.set(defaultServerURL, forKey: Keys.serverURL)
        }

        let defaultToken = "bd0df0785875e2d54d98f738161f0717812dd3f2b53f74a4"
        if let storedToken = defaults.string(forKey: Keys.apiToken)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !storedToken.isEmpty {
            apiToken = storedToken
        } else {
            apiToken = defaultToken
            defaults.set(defaultToken, forKey: Keys.apiToken)
        }
        lanURL = defaults.string(forKey: Keys.lanURL) ?? "http://192.168.1.40:8787"
        enableWorkouts = defaults.object(forKey: Keys.enableWorkouts) as? Bool ?? true
        enableSleep = defaults.object(forKey: Keys.enableSleep) as? Bool ?? true
        enableHRV = defaults.object(forKey: Keys.enableHRV) as? Bool ?? true
        enableRestingHR = defaults.object(forKey: Keys.enableRestingHR) as? Bool ?? true
        enableSteps = defaults.object(forKey: Keys.enableSteps) as? Bool ?? true
        enableActiveEnergy = defaults.object(forKey: Keys.enableActiveEnergy) as? Bool ?? true
        devMode = defaults.object(forKey: Keys.devMode) as? Bool ?? false
        wifiOnly = defaults.object(forKey: Keys.wifiOnly) as? Bool ?? true
    }

    private enum Keys {
        static let serverURL = "serverURL"
        static let apiToken = "apiToken"
        static let lanURL = "lanURL"
        static let enableWorkouts = "enableWorkouts"
        static let enableSleep = "enableSleep"
        static let enableHRV = "enableHRV"
        static let enableRestingHR = "enableRestingHR"
        static let enableSteps = "enableSteps"
        static let enableActiveEnergy = "enableActiveEnergy"
        static let devMode = "devMode"
        static let wifiOnly = "wifiOnly"
    }
}
