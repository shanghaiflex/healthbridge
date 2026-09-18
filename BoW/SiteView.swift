import SwiftUI
import WebKit

/// The whole site (bodywithoutorgans.cc) inside the app: one WKWebView that lives for the app's lifetime,
/// logged in through `/app/login` with the bearer token. The site knows it runs here (`window.BoW`) and hands
/// downloaded lectures to the native player instead of playing them itself.
@MainActor
final class SiteController: NSObject, ObservableObject {
    /// A page of the site with its own place in the app: a tab at the bottom, or a row in «Ещё».
    /// `id` is what the page itself sees as `window.BoW.tab`; inside the app the site hides its own menu.
    struct Page: Hashable, Identifiable {
        let id: String
        let path: String
        let title: String
        let icon: String
    }

    static let main = Page(id: "site", path: "/", title: "Главная", icon: "house")
    static let mixesPage = Page(id: "mixes", path: "/mixes.html", title: "Миксы", icon: "music.note")
    static let homePage = Page(id: "home", path: "/home.html", title: "Дом", icon: "lamp.desk")
    /// The rest of the site, behind «Ещё»: the bottom bar shows five tabs and no more, and a sixth would send
    /// the others into a system «More» list we neither order nor style. «Еда» (pantry.html) is deliberately
    /// nowhere in the app — no tab, no row.
    static let others: [Page] = [
        Page(id: "french", path: "/french.html", title: "Французский", icon: "character.bubble"),
        Page(id: "films", path: "/films.html", title: "Фильмы", icon: "film"),
        Page(id: "books", path: "/books.html", title: "Книги", icon: "books.vertical"),
        Page(id: "reads", path: "/reads.html", title: "Почитать", icon: "doc.richtext"),
        Page(id: "health", path: "/health.html", title: "Well-being", icon: "heart.text.square"),
    ]
    static let handlerName = "bow"

    private static var live: [String: SiteController] = [:]

    /// The controller of a page, made on its first visit. A web view per page, all built at launch, is memory
    /// spent on pages nobody opened — and each one would load the site behind the user's back.
    static func controller(for page: Page) -> SiteController {
        if let existing = live[page.id] { return existing }
        let made = SiteController(page: page)
        live[page.id] = made
        return made
    }

    /// The first tab, the one the rest of the app talks to.
    static var shared: SiteController { controller(for: main) }

    /// Which lectures are on the phone goes to every page that is open: `lectures.html` can be in any tab.
    static func pushDownloadedEverywhere() { live.values.forEach { $0.pushDownloaded() } }

    /// Back to the foreground: every page ever opened may need a reload (see `resume`).
    static func resumeAll() { live.values.forEach { $0.resume() } }

    let page: Page
    var path: String { page.path }
    let webView: WKWebView
    @Published private(set) var loaded = false
    @Published private(set) var loading = false
    @Published private(set) var lastError: String?
    private let refresh = UIRefreshControl()

    private init(page: Page) {
        self.page = page
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.applicationNameForUserAgent = "BoW/2"
        let bridge = WKUserScript(source: "window.BoW = { app: 2, downloaded: [], tab: '\(page.id)' };", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(bridge)
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = Theme.bgUI
        webView.scrollView.backgroundColor = Theme.bgUI
        super.init()
        config.userContentController.add(self, name: Self.handlerName)
        webView.navigationDelegate = self
        refresh.tintColor = Theme.text2UI
        refresh.addTarget(self, action: #selector(pull), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
    }

    /// `https://api.bodywithoutorgans.cc` → `https://bodywithoutorgans.cc`; on the home network the mini itself.
    static var siteURL: URL? {
        guard let api = NetworkClient.shared.absoluteURL(path: "", baseURL: SettingsStore.shared.baseURL),
              var comps = URLComponents(url: api, resolvingAgainstBaseURL: false) else { return nil }
        if let host = comps.host, host.hasPrefix("api.") { comps.host = String(host.dropFirst(4)) }
        comps.path = ""
        return comps.url
    }

    /// Always after the home-network probe: the tab used to load whatever address was current the instant it
    /// appeared, which at launch is the internet one, and without a VPN that address does not answer.
    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        Task { @MainActor in
            await SettingsStore.shared.probeLAN()
            guard let site = Self.siteURL else {
                ActivityLog.shared.log("Сайт: не гружу", detail: "адрес сайта не собрался")
                loaded = false
                return
            }
            ActivityLog.shared.log("Сайт: гружу", detail: site.absoluteString + path)
            var comps = URLComponents(url: site.appendingPathComponent("app/login"), resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "t", value: SettingsStore.shared.apiToken), URLQueryItem(name: "next", value: path)]
            webView.load(URLRequest(url: comps.url!))
        }
    }

    func reload() {
        loaded = false
        loadIfNeeded()
    }

    /// Called when the app comes back to the foreground. While we were suspended iOS may have killed the
    /// web content process (a black tab with nothing in it) or the page may never have loaded — either way, reload.
    func resume() {
        Task { @MainActor in
            await SettingsStore.shared.probeLAN()
            let wanted = Self.siteURL?.host
            if webView.url == nil || webView.title?.isEmpty != false || (wanted != nil && webView.url?.host != wanted) {
                reload()
            }
        }
    }

    @objc private func pull() {
        webView.reload()
    }

    /// Tells the page which lectures are on the phone, so its play buttons hand off to the native player.
    func pushDownloaded() {
        let ids = LectureStore.shared.items.filter { LectureStore.shared.isDownloaded($0) }.map(\.id)
        guard let json = try? JSONSerialization.data(withJSONObject: ids), let text = String(data: json, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.BoW = Object.assign(window.BoW || {}, { downloaded: \(text) });") { _, _ in }
    }
}

extension SiteController: WKScriptMessageHandler, WKNavigationDelegate {
    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        Task { @MainActor in
            switch type {
            case "play":
                guard let id = body["id"] as? String, let lecture = LectureStore.shared.items.first(where: { $0.id == id }) else { return }
                let pos = (body["position"] as? Double).map { Double($0) }
                PlayerEngine.shared.play(lecture, from: pos)
                AppState.shared.tab = .lectures
            default:
                break
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Links to YouTube, SoundCloud, articles… open in Safari; the site itself stays in the app.
        guard let url = navigationAction.request.url, let host = url.host else { return decisionHandler(.allow) }
        let siteHost = MainActor.assumeIsolated { SiteController.siteURL?.host } ?? ""
        let own = host == siteHost || host.hasSuffix("." + siteHost) || host == "api." + siteHost
            || host.hasSuffix("bodywithoutorgans.cc") || host.hasPrefix("192.168.")
        if navigationAction.navigationType == .linkActivated, !own, url.scheme?.hasPrefix("http") == true {
            Task { @MainActor in UIApplication.shared.open(url) }
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in self.loading = true }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.loading = false
            self.refresh.endRefreshing()
            self.lastError = nil
            self.pushDownloaded()
        }
    }

    /// iOS reclaims the web content process of a suspended app; without this the tab stays black forever.
    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor in
            ActivityLog.shared.log("Сайт: процесс страницы убит, перезагружаю")
            self.reload()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let text = error.localizedDescription
        let url = MainActor.assumeIsolated { Self.siteURL?.absoluteString } ?? ""
        Task { @MainActor in
            self.loading = false
            self.refresh.endRefreshing()
            self.lastError = text
            // Into the journal as well: a page that fails to load leaves nothing on the mini to look at, and the
            // tab is simply empty — the reason has to travel with the next request that does get through.
            ActivityLog.shared.log("Сайт не открылся", detail: "\(url): \(text)")
        }
    }
}

/// WebKit pauses everything a web view was playing the moment that view leaves the window — so tapping another
/// tab stopped the mix. The tab therefore holds a box, and the web view is only lent to it: while the tab is off
/// screen the box parks the web view in the window itself (behind everything, all but transparent, its own size
/// untouched so the page never relayouts) and takes it back when the tab comes round again.
final class SiteBox: UIView {
    private let web: WKWebView

    init(web: WKWebView) {
        self.web = web
        super.init(frame: .zero)
        backgroundColor = Theme.bgUI
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not from a storyboard") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            if web.superview !== self { addSubview(web) }
            setNeedsLayout()
        } else if web.superview === self {
            // Only when we are the one holding it: the same page pushed twice would otherwise steal it back.
            SiteParking.park(web)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if web.superview === self { web.frame = bounds }
    }
}

/// The window-sized nowhere where web views wait out the tabs they are not showing in.
@MainActor
enum SiteParking {
    private static var lot: UIView?

    static func park(_ web: WKWebView) {
        guard let window = lot?.window ?? UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
        if lot?.window !== window {
            let made = UIView(frame: window.bounds)
            made.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            made.clipsToBounds = true
            made.alpha = 0.01
            made.isUserInteractionEnabled = false
            window.insertSubview(made, at: 0)
            lot = made
        }
        lot?.addSubview(web)
    }
}

struct SiteWebView: UIViewRepresentable {
    let controller: SiteController
    func makeUIView(context: Context) -> SiteBox { SiteBox(web: controller.webView) }
    func updateUIView(_ box: SiteBox, context: Context) {}
}

/// A page of the site as a tab (or a row of «Ещё»): its controller — and with it the web view — appears on the
/// first visit. Resolving it inside a plain `body` would build one for every tab the moment the TabView is laid
/// out, which is the whole site loaded at launch.
struct SitePage: View {
    let page: SiteController.Page
    @State private var site: SiteController?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if let site { SiteView(site: site) }
        }
        .onAppear { if site == nil { site = SiteController.controller(for: page) } }
    }
}

struct SiteView: View {
    @ObservedObject var site: SiteController

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            // Без таб-бара страница шла до самого низа экрана; с ним низ листа с кнопками («Готово» во
            // французском) оказывался под баром и не нажимался. Вебвью кончается там, где начинается бар.
            SiteWebView(controller: site)
            if site.loading {
                VStack {
                    ProgressView().tint(Theme.text2).padding(.top, 8)
                    Spacer()
                }
            }
            if let e = site.lastError {
                VStack(spacing: 10) {
                    Image(systemName: "wifi.slash").font(.largeTitle).foregroundStyle(Theme.text2)
                    Text("Сайт не открылся").font(Theme.display(20, weight: .semibold))
                    Text(e).font(.footnote).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
                    Button("Ещё раз") { site.reload() }.buttonStyle(.borderedProminent)
                }
                .padding(24)
                .card()
                .padding(24)
            }
        }
        .onAppear { site.loadIfNeeded() }
    }
}
