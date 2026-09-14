import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section {
                TextField("URL", text: $settings.serverURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("Токен", text: $settings.apiToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Адрес mini в домашней сети", text: $settings.lanURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                LabeledContent("Сейчас", value: settings.routeName)
            } header: {
                Text("Сервер")
            } footer: {
                Text("Дома без VPN интернет-адрес не работает (провайдер режет Cloudflare), поэтому приложение сначала пробует mini напрямую по Wi-Fi, а иначе идёт через интернет.")
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
                    Button("Сбросить очередь и перечитать год", role: .destructive) {
                        Task { await SyncCoordinator.shared.resetImport(reason: "вручную") }
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
