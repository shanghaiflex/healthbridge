import SwiftUI

struct ContentView: View {
    @StateObject private var coordinator = SyncCoordinator()

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    statusRow(title: "Server reachable", value: coordinator.serverReachable ? "Yes" : "No")
                    statusRow(title: "Queue size", value: "\(coordinator.queueCount)")
                    statusRow(title: "Last sync", value: coordinator.lastSync?.formatted(date: .numeric, time: .standard) ?? "Never")
                    statusRow(title: "Last error", value: coordinator.lastError ?? "None")
                }

                Section("Actions") {
                    Button("Sync now") {
                        Task { await coordinator.syncNow() }
                    }

                    if SettingsStore.shared.devMode {
                        Button("Import sample JSON") {
                            Task { await coordinator.importSampleJSON() }
                        }
                    }
                }

                Section("Settings") {
                    NavigationLink("Server settings") {
                        SettingsView()
                    }
                }
            }
            .navigationTitle("Health Bridge")
        }
        .task {
            await coordinator.bootstrap()
        }
        .onAppear {
            BackgroundScheduler.shared.register()
            BackgroundScheduler.shared.schedule()
        }
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
