import Foundation

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var serverURL: String {
        didSet { defaults.set(serverURL, forKey: Keys.serverURL) }
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

    private let defaults = UserDefaults.standard

    private init() {
        serverURL = defaults.string(forKey: Keys.serverURL) ?? "http://192.168.1.149:8080"
        enableWorkouts = defaults.object(forKey: Keys.enableWorkouts) as? Bool ?? true
        enableSleep = defaults.object(forKey: Keys.enableSleep) as? Bool ?? true
        enableHRV = defaults.object(forKey: Keys.enableHRV) as? Bool ?? true
        enableRestingHR = defaults.object(forKey: Keys.enableRestingHR) as? Bool ?? true
        enableSteps = defaults.object(forKey: Keys.enableSteps) as? Bool ?? true
        enableActiveEnergy = defaults.object(forKey: Keys.enableActiveEnergy) as? Bool ?? true
        devMode = defaults.object(forKey: Keys.devMode) as? Bool ?? false
    }

    private enum Keys {
        static let serverURL = "serverURL"
        static let enableWorkouts = "enableWorkouts"
        static let enableSleep = "enableSleep"
        static let enableHRV = "enableHRV"
        static let enableRestingHR = "enableRestingHR"
        static let enableSteps = "enableSteps"
        static let enableActiveEnergy = "enableActiveEnergy"
        static let devMode = "devMode"
    }
}
