import SwiftUI

/// «Ещё»: the pages of the site that do not earn a place in the bottom bar (iOS shows five tabs and turns a
/// sixth into a system list of its own), and the app's own two screens — sync journal and settings.
struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Сайт") {
                    ForEach(SiteController.others) { page in
                        NavigationLink {
                            SitePage(page: page)
                                .navigationTitle(page.title)
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Label(page.title, systemImage: page.icon)
                        }
                        .listRowBackground(Theme.surface)
                    }
                }
                Section("Приложение") {
                    NavigationLink {
                        HealthView()
                    } label: {
                        Label("Синк и журнал", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .listRowBackground(Theme.surface)
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Настройки", systemImage: "gearshape")
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Ещё")
        }
    }
}

#Preview {
    MoreView()
        .preferredColorScheme(.dark)
}
