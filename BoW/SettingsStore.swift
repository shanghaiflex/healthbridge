import Foundation

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var serverURL: String {
        didSet { defaults.set(serverURL, forKey: Keys.serverURL) }
    }
    @Published var apiToken: String {
        didSet { defaults.set(apiToken, forKey: Keys.apiToken) }
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
