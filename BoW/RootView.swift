import SwiftUI

struct RootView: View {
    @ObservedObject private var app = AppState.shared

    var body: some View {
        TabView(selection: $app.tab) {
            SitePage(page: SiteController.main)
                .tabItem { Label(SiteController.main.title, systemImage: SiteController.main.icon) }
                .tag(AppState.Tab.site)
                // Health permission on the very first launch, whichever tab is open: a background relaunch never asks.
                .task { await SyncCoordinator.shared.bootstrap() }
            LecturesView()
                .tabItem { Label("Лекции", systemImage: "headphones") }
                .tag(AppState.Tab.lectures)
            SitePage(page: SiteController.mixesPage)
                .tabItem { Label(SiteController.mixesPage.title, systemImage: SiteController.mixesPage.icon) }
                .tag(AppState.Tab.mixes)
            SitePage(page: SiteController.homePage)
                .tabItem { Label(SiteController.homePage.title, systemImage: SiteController.homePage.icon) }
                .tag(AppState.Tab.home)
            MoreView()
                .tabItem { Label("Ещё", systemImage: "ellipsis") }
                .tag(AppState.Tab.more)
        }
    }
}

#Preview {
    RootView()
        .preferredColorScheme(.dark)
}
