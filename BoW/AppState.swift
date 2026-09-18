import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    enum Tab: Hashable { case site, lectures, mixes, home, more }
    @Published var tab: Tab = .site
    /// Страница сайта из «Ещё», которую надо открыть (тап по уведомлению).
    @Published var morePage: SiteController.Page?
}
