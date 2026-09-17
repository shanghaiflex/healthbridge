import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    enum Tab: Hashable { case site, lectures, mixes, home, more }
    @Published var tab: Tab = .site
}
