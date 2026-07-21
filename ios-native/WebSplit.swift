import SwiftUI
import WebKit

// MARK: - 用途1: 汎用の「分割ブラウザ」（任意の2サイトを分割表示）
//
// 各ペインは WKWebView（Safari と同じ WebKit）。アドレスバー・戻る/進む/更新・
// 文字サイズ・入れ替え（上ペインのバーに統合）を備えた2ペインブラウザです。
// 既定は Claude（上）と Google ドキュメント（下）。
//
// 【ログイン注意】Google は埋め込みブラウザからのログインを既定でブロックするため、
// 下記 safariUA で UA を Safari に偽装して回避しています（実機・個人利用向けの割り切り）。
// Claude 側は Google を使わず「メール＋確認コード」でログインすれば確実です。

struct WebSplit: View {
    @StateObject private var top = BrowserPane(storageKey: "web.url.top",
                                               initial: "https://claude.ai")
    @StateObject private var bottom = BrowserPane(storageKey: "web.url.bottom",
                                                  initial: "https://docs.google.com/document/u/0/")

    var body: some View {
        // 独立した操作バーは持たず、入れ替えボタンは上ペインのアドレスバーに統合（1段）
        VSplit("web") {
            BrowserPaneView(pane: top, isTop: true, zoomKey: "web.zoom.top", onSwap: swapPanes)
        } bottom: {
            BrowserPaneView(pane: bottom, isTop: false, zoomKey: "web.zoom.bottom")
        }
    }

    // 上下ペインの URL を入れ替える
    private func swapPanes() {
        let a = top.current
        let b = bottom.current
        top.load(b)
        bottom.load(a)
    }
}

// MARK: - 1ペインの UI（ツールバー + WebView + プログレス）
struct BrowserPaneView: View {
    @ObservedObject var pane: BrowserPane
    let isTop: Bool
    let onSwap: (() -> Void)?               // 指定時はツールバーに入れ替えボタンを表示
    @AppStorage private var zoom: Double   // ページ拡大率（保存）
    @FocusState private var focused: Bool

    init(pane: BrowserPane, isTop: Bool, zoomKey: String, onSwap: (() -> Void)? = nil) {
        self._pane = ObservedObject(wrappedValue: pane)
        self.isTop = isTop
        self.onSwap = onSwap
        self._zoom = AppStorage(wrappedValue: 1.0, zoomKey)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isTop { toolbar }        // 上ペインはバーを上に
            ZStack(alignment: .top) {
                WebView(pane: pane, zoom: zoom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if pane.isLoading {
                    ProgressView(value: pane.progress)
                        .progressViewStyle(.linear)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !isTop { toolbar }       // 下ペインはバーを最下部に
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbar: some View {
        // すべて1行の HStack。URL欄は上限つき＆足りなければ縮むので必ず1行に収まる。
        HStack(spacing: 6) {
            if let onSwap { iconButton("arrow.up.arrow.down", action: onSwap) }
            iconButton("chevron.backward", action: pane.back).disabled(!pane.canGoBack)
            iconButton("chevron.forward", action: pane.forward).disabled(!pane.canGoForward)

            TextField("検索 または URL", text: $pane.address)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.webSearch)
                .submitLabel(.go)
                .focused($focused)
                .onSubmit { pane.go(); focused = false }
                .frame(maxWidth: 220)          // 狭め。残りが足りなければさらに縮む

            iconButton(pane.isLoading ? "xmark" : "arrow.clockwise", action: pane.reloadOrStop)
            iconButton("textformat.size.smaller", action: { zoom = max(0.5, zoom - 0.1) })
                .disabled(zoom <= 0.5)
            iconButton("textformat.size.larger", action: { zoom = min(3.0, zoom + 0.1) })
                .disabled(zoom >= 3.0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial)
    }

    // 押しやすいよう大きめのタップ領域を持つアイコンボタン
    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17))
                .frame(minWidth: 34, minHeight: 36)
                .contentShape(Rectangle())
        }
    }
}

// MARK: - ペインの状態モデル（WebView と双方向にやり取り）
final class BrowserPane: ObservableObject {
    @Published var address: String       // アドレスバーの文字列
    @Published var displayURL: String = "" // 実際に開いているURL
    @Published var title: String = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var progress: Double = 0

    weak var webView: WKWebView?
    private let storageKey: String

    init(storageKey: String, initial: String) {
        self.storageKey = storageKey
        self.address = UserDefaults.standard.string(forKey: storageKey) ?? initial
    }

    /// 現在開いているURL（未取得ならアドレス欄の値）
    var current: String { displayURL.isEmpty ? address : displayURL }

    func go() {
        guard let url = Self.normalize(address) else { return }
        address = url.absoluteString
        webView?.load(URLRequest(url: url))
    }
    func load(_ string: String) { address = string; go() }
    func back() { webView?.goBack() }
    func forward() { webView?.goForward() }
    func reloadOrStop() {
        if isLoading { webView?.stopLoading() } else { webView?.reload() }
    }

    func persist(_ s: String) { UserDefaults.standard.set(s, forKey: storageKey) }

    /// URL文字列を正規化。スキームがなければ、ドメイン風なら https、そうでなければ Google 検索。
    static func normalize(_ s: String) -> URL? {
        let raw = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://") {
            return URL(string: raw)
        }
        let looksLikeDomain = raw.contains(".") && !raw.contains(" ")
        if looksLikeDomain {
            return URL(string: "https://\(raw)")
        }
        let q = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
        return URL(string: "https://www.google.com/search?q=\(q)")
    }
}

// MARK: - WKWebView ラッパ（KVO で状態を同期）
struct WebView: UIViewRepresentable {
    @ObservedObject var pane: BrowserPane
    let zoom: Double

    // Google の埋め込みブラウザ判定を避けるための Safari UA（iOS更新時に数字を更新）
    static let safariUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    func makeCoordinator() -> Coordinator { Coordinator(pane: pane) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = .default()   // ログインCookieを永続化

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Self.safariUA
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.attach(webView)
        context.coordinator.textScale = zoom      // 文字のみ拡大（横幅維持）
        pane.webView = webView

        if let url = BrowserPane.normalize(pane.address) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let c = context.coordinator
        c.textScale = zoom
        if c.appliedScale != zoom {
            c.appliedScale = zoom
            c.applyTextScale(webView)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let pane: BrowserPane
        private var obs: [NSKeyValueObservation] = []
        var textScale: Double = 1.0
        var appliedScale: Double = -1
        init(pane: BrowserPane) { self.pane = pane }

        func attach(_ webView: WKWebView) {
            let pane = self.pane   // 弱参照キャプチャ用のローカル束縛
            obs = [
                webView.observe(\.estimatedProgress, options: [.new]) { [weak pane] wv, _ in
                    pane?.progress = wv.estimatedProgress
                },
                webView.observe(\.isLoading, options: [.new]) { [weak pane] wv, _ in
                    pane?.isLoading = wv.isLoading
                },
                webView.observe(\.url, options: [.new]) { [weak pane] wv, _ in
                    guard let u = wv.url?.absoluteString else { return }
                    pane?.displayURL = u
                    pane?.address = u
                    pane?.persist(u)
                },
                webView.observe(\.title, options: [.new]) { [weak pane] wv, _ in
                    pane?.title = wv.title ?? ""
                },
                webView.observe(\.canGoBack, options: [.new]) { [weak pane] wv, _ in
                    pane?.canGoBack = wv.canGoBack
                },
                webView.observe(\.canGoForward, options: [.new]) { [weak pane] wv, _ in
                    pane?.canGoForward = wv.canGoForward
                },
            ]
        }

        // 文字だけを倍率変更（横幅は維持＝折り返しで縦に伸びる）。
        // 各要素の元フォントサイズを覚えて倍率をかけ、後から増える要素にも
        // MutationObserver で追従。1.0 のときは元に戻す。
        func applyTextScale(_ webView: WKWebView) {
            let js: String
            if abs(textScale - 1.0) < 0.001 {
                js = "(function(){if(window.__tsObs){window.__tsObs.disconnect();window.__tsObs=null;}var e=document.querySelectorAll('[data-ofs]');for(var i=0;i<e.length;i++){e[i].style.fontSize='';e[i].removeAttribute('data-ofs');}})();"
            } else {
                js = "(function(s){function a(){var e=document.querySelectorAll('*');for(var i=0;i<e.length;i++){var el=e[i];var o=el.getAttribute('data-ofs');if(o===null){o=getComputedStyle(el).fontSize;el.setAttribute('data-ofs',o);}var p=parseFloat(o);if(!isNaN(p)){el.style.fontSize=(p*window.__ts)+'px';}}}window.__ts=s;a();if(!window.__tsObs){var t;window.__tsObs=new MutationObserver(function(){clearTimeout(t);t=setTimeout(a,200);});window.__tsObs.observe(document.body||document.documentElement,{childList:true,subtree:true});}})(\(textScale));"
            }
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            appliedScale = textScale
            applyTextScale(webView)
        }

        // target="_blank" 等の新規ウィンドウ要求を、同じ WebView で開く
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}

// （ブックマーク機能は削除済み）
