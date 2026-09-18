import SwiftUI

/// Журнальная палитра сайта (theme.css на bodywithoutorgans.cc, тёмная половина, 18.09.2026): чёрная
/// бумага, киноварь вместо терракоты, волосяные линейки вместо теней. Цифры — те же hex, что в theme.css,
/// чтобы вебвью и родные экраны не расходились: приложение — это пять табов вокруг того же сайта.
enum Theme {
    static let bg = Color(red: 0.075, green: 0.071, blue: 0.063)         // #131210
    static let surface = Color(red: 0.106, green: 0.098, blue: 0.086)    // #1b1916
    static let surface2 = Color(red: 0.149, green: 0.137, blue: 0.118)   // #26231e
    static let text = Color(red: 0.953, green: 0.941, blue: 0.910)       // #f3f0e8
    static let text2 = Color(red: 0.647, green: 0.627, blue: 0.600)      // #a5a099
    static let text3 = Color(red: 0.447, green: 0.424, blue: 0.388)      // #726c63
    static let accent = Color(red: 0.890, green: 0.376, blue: 0.302)     // #e3604d киноварь
    static let ok = Color(red: 0.541, green: 0.718, blue: 0.624)         // #8ab79f
    static let warn = Color(red: 0.847, green: 0.647, blue: 0.282)       // #d8a548
    static let line = Color(red: 0.953, green: 0.941, blue: 0.910).opacity(0.16)
    /// Прямой угол: бумага режется ровно — как карточки на сайте после журнальной перекраски.
    static let radius: CGFloat = 0

    static let bgUI = UIColor(red: 0.075, green: 0.071, blue: 0.063, alpha: 1)
    static let text2UI = UIColor(red: 0.647, green: 0.627, blue: 0.600, alpha: 1)
    static let text3UI = UIColor(red: 0.447, green: 0.424, blue: 0.388, alpha: 1)
    static let textUI = UIColor(red: 0.953, green: 0.941, blue: 0.910, alpha: 1)
    static let accentUI = UIColor(red: 0.890, green: 0.376, blue: 0.302, alpha: 1)

    /// Антиква для заголовков. Своего Playfair в приложении нет и не нужно: системная New York — тот же
    /// журнальный рисунок с засечками, приезжает с iOS и умеет динамический кегль.
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func displayUI(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Заголовки навигации — антиквой, таб-бар — с разрядкой и волосяной линейкой сверху: в журнале
    /// рубрики набраны именно так. Вызывается один раз при запуске.
    static func configureAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.font: displayUI(17, weight: .semibold), .foregroundColor: textUI]
        nav.largeTitleTextAttributes = [.font: displayUI(34), .foregroundColor: textUI]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = bgUI
        tab.shadowColor = UIColor(red: 0.953, green: 0.941, blue: 0.910, alpha: 0.22)
        for layout in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            layout.normal.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 10, weight: .medium),
                                                 .kern: 0.6, .foregroundColor: text3UI]
            layout.selected.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 10, weight: .medium),
                                                   .kern: 0.6, .foregroundColor: accentUI]
            layout.normal.iconColor = text3UI
            layout.selected.iconColor = accentUI
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

/// Карточка: прямоугольник с волосяной рамкой, без тени и скругления — вырезка из бумаги.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.surface)
            .overlay(Rectangle().strokeBorder(Theme.line))
    }
}

/// Подпись рубрики: прописные с разрядкой, киноварью. Тот же приём, что у `.eyebrow` на сайте.
struct SectionLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 11, weight: .medium))
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(Theme.accent)
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
    func sectionLabel() -> some View { modifier(SectionLabel()) }
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
