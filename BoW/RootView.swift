import SwiftUI

struct RootView: View {
    @ObservedObject private var app = AppState.shared

    var body: some View {
        TabView(selection: $app.tab) {
            SiteView()
                .tabItem { Label("Сайт", systemImage: "globe") }
                .tag(AppState.Tab.site)
                // Health permission on the very first launch, whichever tab is open: a background relaunch never asks.
                .task { await SyncCoordinator.shared.bootstrap() }
            SiteView(site: .home)
                .tabItem { Label("Дом", systemImage: "lamp.desk") }
                .tag(AppState.Tab.home)
            LecturesView()
                .tabItem { Label("Лекции", systemImage: "headphones") }
                .tag(AppState.Tab.lectures)
            HealthView()
                .tabItem { Label("Здоровье", systemImage: "heart.text.square") }
                .tag(AppState.Tab.health)
            NavigationStack { SettingsView() }
                .tabItem { Label("Настройки", systemImage: "gearshape") }
                .tag(AppState.Tab.settings)
        }
    }
}

#Preview {
    RootView()
        .preferredColorScheme(.dark)
}
