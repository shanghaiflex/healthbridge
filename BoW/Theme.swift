import SwiftUI

/// The site's warm palette (theme.css on bodywithoutorgans.cc, dark half): warm charcoal ground, two warm
/// surfaces, terracotta accent, sage for «ok». Values are the same hex numbers as in theme.css.
enum Theme {
    static let bg = Color(red: 0.086, green: 0.082, blue: 0.075)         // #161513
    static let surface = Color(red: 0.125, green: 0.118, blue: 0.106)    // #201e1b
    static let surface2 = Color(red: 0.165, green: 0.153, blue: 0.137)   // #2a2723
    static let text = Color(red: 0.937, green: 0.91, blue: 0.863)        // #efe8dc
    static let text2 = Color(red: 0.651, green: 0.616, blue: 0.561)      // #a69d8f
    static let text3 = Color(red: 0.435, green: 0.408, blue: 0.369)      // #6f685e
    static let accent = Color(red: 0.878, green: 0.498, blue: 0.341)     // #e07f57 terracotta
    static let ok = Color(red: 0.576, green: 0.635, blue: 0.518)         // #93a284 sage
    static let warn = Color(red: 0.941, green: 0.627, blue: 0.439)       // #f0a070
    static let line = Color(red: 1.0, green: 0.94, blue: 0.86).opacity(0.09)
    static let radius: CGFloat = 18

    static let bgUI = UIColor(red: 0.086, green: 0.082, blue: 0.075, alpha: 1)
    static let text2UI = UIColor(red: 0.651, green: 0.616, blue: 0.561, alpha: 1)
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
