import SwiftUI

/// The site's dark palette (bodywithoutorgans.cc): pure black ground, two grey surfaces, one blue accent.
enum Theme {
    static let bg = Color.black
    static let surface = Color(red: 0.11, green: 0.11, blue: 0.118)      // #1c1c1e
    static let surface2 = Color(red: 0.173, green: 0.173, blue: 0.18)    // #2c2c2e
    static let text2 = Color(red: 0.631, green: 0.631, blue: 0.651)      // #a1a1a6
    static let text3 = Color.white.opacity(0.48)
    static let accent = Color(red: 0.161, green: 0.592, blue: 1.0)       // #2997ff
    static let ok = Color(red: 0.188, green: 0.82, blue: 0.345)          // #30d158
    static let warn = Color(red: 1.0, green: 0.624, blue: 0.039)         // #ff9f0a
    static let line = Color.white.opacity(0.1)
    static let radius: CGFloat = 18
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.line))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

enum Fmt {
    /// 1:02:03 / 12:03, like the site.
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        let h = s / 3600, m = s % 3600 / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// «2 ч 51 мин» / «47 мин».
    static func duration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        let t = Int((Double(seconds) / 60).rounded()), h = t / 60, m = t % 60
        return h > 0 ? "\(h) ч \(m) мин" : "\(m) мин"
    }

    static func megabytes(_ bytes: Int?) -> String {
        guard let bytes, bytes > 0 else { return "" }
        return "\(bytes / 1_000_000) МБ"
    }

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM, HH:mm"
        return f
    }()

    static let clockOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f
    }()
}
