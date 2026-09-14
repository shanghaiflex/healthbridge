import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    enum Tab: Hashable { case site, lectures, health, settings }
    @Published var tab: Tab = .site
}
