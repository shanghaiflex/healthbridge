import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section("Сервер") {
                TextField("URL", text: $settings.serverURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("Токен", text: $settings.apiToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Toggle("Качать только по Wi-Fi", isOn: $settings.wifiOnly)
            } header: {
                Text("Лекции")
            } footer: {
                Text("Одна лекция — 150–200 МБ. Уже начатые загрузки продолжают по старому правилу.")
            }

            Section("Что отправлять в Здоровье") {
                Toggle("Тренировки", isOn: $settings.enableWorkouts)
                Toggle("Сон", isOn: $settings.enableSleep)
                Toggle("Вариабельность пульса", isOn: $settings.enableHRV)
                Toggle("Пульс покоя", isOn: $settings.enableRestingHR)
                Toggle("Шаги", isOn: $settings.enableSteps)
                Toggle("Активные калории", isOn: $settings.enableActiveEnergy)
            }

            Section("Разработка") {
                Toggle("Режим разработчика", isOn: $settings.devMode)
                if settings.devMode {
                    Button("Импортировать пример JSON") {
                        Task { await SyncCoordinator.shared.importSampleJSON() }
                    }
                }
                LabeledContent("Версия", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Настройки")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .preferredColorScheme(.dark)
}
