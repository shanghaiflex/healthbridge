import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            LecturesView()
                // Health permission on the very first launch, whichever tab is open: a background relaunch never asks.
                .task { await SyncCoordinator.shared.bootstrap() }
                .tabItem { Label("Лекции", systemImage: "headphones") }
            HealthView()
                .tabItem { Label("Здоровье", systemImage: "heart.text.square") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Настройки", systemImage: "gearshape") }
        }
    }
}

#Preview {
    RootView()
        .preferredColorScheme(.dark)
        .environmentObject(LectureStore.preview)
        .environmentObject(PlayerEngine.preview)
}
