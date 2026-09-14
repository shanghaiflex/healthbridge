import SwiftUI
import WebKit

/// The whole site (bodywithoutorgans.cc) inside the app: one WKWebView that lives for the app's lifetime,
/// logged in through `/app/login` with the bearer token. The site knows it runs here (`window.BoW`) and hands
/// downloaded lectures to the native player instead of playing them itself.
@MainActor
final class SiteController: NSObject, ObservableObject {
    static let shared = SiteController()
    static let handlerName = "bow"

    let webView: WKWebView
    @Published private(set) var loaded = false
    @Published private(set) var loading = false
    @Published private(set) var lastError: String?
    private let refresh = UIRefreshControl()

    private override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.applicationNameForUserAgent = "BoW/2"
        let bridge = WKUserScript(source: "window.BoW = { app: 2, downloaded: [] };", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(bridge)
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        super.init()
        config.userContentController.add(self, name: Self.handlerName)
        webView.navigationDelegate = self
        refresh.tintColor = .white
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

    func loadIfNeeded() {
        guard !loaded, let site = Self.siteURL else {
            ActivityLog.shared.log("Сайт: не гружу", detail: loaded ? "уже загружен" : "адрес сайта не собрался")
            return
        }
        loaded = true
        ActivityLog.shared.log("Сайт: гружу", detail: site.absoluteString)
        var comps = URLComponents(url: site.appendingPathComponent("app/login"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "t", value: SettingsStore.shared.apiToken), URLQueryItem(name: "next", value: "/")]
        webView.load(URLRequest(url: comps.url!))
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

struct SiteWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { SiteController.shared.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct SiteView: View {
    @ObservedObject private var site = SiteController.shared

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            SiteWebView()
                .ignoresSafeArea(edges: .bottom)
            if site.loading {
                VStack {
                    ProgressView().tint(.white).padding(.top, 8)
                    Spacer()
                }
            }
            if let e = site.lastError {
                VStack(spacing: 10) {
                    Image(systemName: "wifi.slash").font(.largeTitle).foregroundStyle(Theme.text2)
                    Text("Сайт не открылся").font(.headline)
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
