import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section("Server") {
                TextField("Server URL", text: $settings.serverURL)
                    .serverTextFieldStyle()
            }

            Section("Data types") {
                Toggle("Workouts", isOn: $settings.enableWorkouts)
                Toggle("Sleep", isOn: $settings.enableSleep)
                Toggle("HRV (SDNN)", isOn: $settings.enableHRV)
                Toggle("Resting Heart Rate", isOn: $settings.enableRestingHR)
                Toggle("Steps", isOn: $settings.enableSteps)
                Toggle("Active Energy", isOn: $settings.enableActiveEnergy)
            }

            Section("Developer") {
                Toggle("Enable dev mode", isOn: $settings.devMode)
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}

private extension View {
    @ViewBuilder
    func serverTextFieldStyle() -> some View {
        #if os(iOS)
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }
}
