import SwiftUI
import WebKit

// MARK: - 用途1: 汎用の「分割ブラウザ」（任意の2サイトを分割表示）
//
// 各ペインは WKWebView（Safari と同じ WebKit）。アドレスバー・戻る/進む/更新・全画面、
// 上下⇔左右切替、入れ替え、ブックマークを備えた実用的な2ペインブラウザです。
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
    @StateObject private var bookmarks = BookmarkStore()
    @State private var showManage = false

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            VSplit {
                BrowserPaneView(pane: top)
            } bottom: {
                BrowserPaneView(pane: bottom)
            }
        }
        .sheet(isPresented: $showManage) { manageSheet }
    }

    // MARK: 上部の操作バー
    private var controlBar: some View {
        HStack(spacing: 18) {
            Button { swapPanes() } label: {
                Image(systemName: "arrow.up.arrow.down")
            }

            Spacer()

            Menu {
                Section("開く") {
                    ForEach(bookmarks.pairs) { pair in
                        Button(pair.name) { apply(pair) }
                    }
                }
                Section {
                    Button { saveCurrent() } label: { Label("現在のペアを保存", systemImage: "plus") }
                    Button { showManage = true } label: { Label("管理…", systemImage: "slider.horizontal.3") }
                }
            } label: {
                Image(systemName: "bookmark")
            }
        }
        .font(.system(size: 18))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial)
    }

    // MARK: ブックマーク管理シート
    private var manageSheet: some View {
        NavigationView {
            List {
                if bookmarks.pairs.isEmpty {
                    Text("保存されたブックマークはありません").foregroundStyle(.secondary)
                }
                ForEach($bookmarks.pairs) { $pair in
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("名前", text: $pair.name)
                        Text("↑ \(pair.top)").font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Text("↓ \(pair.bottom)").font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                .onDelete { bookmarks.remove(at: $0) }
            }
            .navigationTitle("ブックマーク")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { showManage = false }
                }
            }
        }
    }

    // MARK: 操作
    private func swapPanes() {
        let a = top.current
        let b = bottom.current
        top.load(b)
        bottom.load(a)
    }
    private func apply(_ pair: BookmarkPair) {
        top.load(pair.top)
        bottom.load(pair.bottom)
    }
    private func saveCurrent() {
        let name = "\(hostName(top.current)) / \(hostName(bottom.current))"
        bookmarks.add(BookmarkPair(name: name, top: top.current, bottom: bottom.current))
    }
    private func hostName(_ s: String) -> String {
        (URL(string: s)?.host ?? s).replacingOccurrences(of: "www.", with: "")
    }
}

// MARK: - 1ペインの UI（ツールバー + WebView + プログレス）
struct BrowserPaneView: View {
    @ObservedObject var pane: BrowserPane
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button(action: pane.back) { Image(systemName: "chevron.backward") }
                    .disabled(!pane.canGoBack)
                Button(action: pane.forward) { Image(systemName: "chevron.forward") }
                    .disabled(!pane.canGoForward)

                TextField("検索 または URL", text: $pane.address)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.webSearch)
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit { pane.go(); focused = false }

                Button(action: pane.reloadOrStop) {
                    Image(systemName: pane.isLoading ? "xmark" : "arrow.clockwise")
                }
            }
            .font(.system(size: 16))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.thinMaterial)

            ZStack(alignment: .top) {
                WebView(pane: pane)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if pane.isLoading {
                    ProgressView(value: pane.progress)
                        .progressViewStyle(.linear)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        pane.webView = webView

        if let url = BrowserPane.normalize(pane.address) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) { }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let pane: BrowserPane
        private var obs: [NSKeyValueObservation] = []
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

// MARK: - ブックマーク（2サイトの組）
struct BookmarkPair: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var top: String
    var bottom: String
}

final class BookmarkStore: ObservableObject {
    @Published var pairs: [BookmarkPair] { didSet { save() } }
    private let key = "web.bookmarks.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([BookmarkPair].self, from: data) {
            pairs = decoded
        } else {
            pairs = BookmarkStore.defaults
        }
    }

    func add(_ p: BookmarkPair) { pairs.append(p) }
    func remove(at offsets: IndexSet) { pairs.remove(atOffsets: offsets) }

    private func save() {
        if let data = try? JSONEncoder().encode(pairs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static let defaults = [
        BookmarkPair(name: "Claude + Google ドキュメント",
                     top: "https://claude.ai", bottom: "https://docs.google.com/document/u/0/"),
        BookmarkPair(name: "Claude + Gmail",
                     top: "https://claude.ai", bottom: "https://mail.google.com"),
        BookmarkPair(name: "YouTube + Wikipedia",
                     top: "https://m.youtube.com", bottom: "https://ja.m.wikipedia.org"),
    ]
}
