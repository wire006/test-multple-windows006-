import SwiftUI
import WebKit

// MARK: - 用途1: Claude と Google ドキュメントを上下2分割
//
// 【重要 / ログインについて】
// ・Google は「埋め込みブラウザ(WKWebView)からの Google ログイン」を既定でブロックします
//   （エラー: "このブラウザまたはアプリは安全でない可能性…" / disallowed_useragent）。
// ・Claude 側は Google を使わず「メールアドレス＋確認コード」でログインすれば WKWebView でも通ります。
// ・Google ドキュメント側は Google ログインが必須のため、下の customUserAgent（Safari を詐称）で
//   ブロックを回避します。実務上はこれで通ることが多いですが、Google の規約上はグレーで、
//   将来 UA 文字列の更新が必要になる場合があります（実機・個人利用のみを前提とした割り切り）。
// ・一度ログインすれば Cookie は既定の永続データストアに保存され、次回起動時も維持されます。

struct WebSplit: View {
    @State private var topText = "https://claude.ai"
    @State private var bottomText = "https://docs.google.com/document/u/0/"
    @State private var topURL: URL? = URL(string: "https://claude.ai")
    @State private var bottomURL: URL? = URL(string: "https://docs.google.com/document/u/0/")

    var body: some View {
        VerticalSplit {
            WebPane(title: "上のURL（例: Claude）", text: $topText, url: $topURL)
        } bottom: {
            WebPane(title: "下のURL（例: Googleドキュメント）", text: $bottomText, url: $bottomURL)
        }
    }
}

// MARK: - 1ペイン（URLバー + WebView）
struct WebPane: View {
    let title: String
    @Binding var text: String
    @Binding var url: URL?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TextField(title, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit { url = normalized(text) }
                Button("開く") { url = normalized(text) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(6)
            .background(.thinMaterial)

            WebView(url: url)
        }
    }

    private func normalized(_ s: String) -> URL? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if !t.lowercased().hasPrefix("http") { t = "https://" + t }
        return URL(string: t)
    }
}

// MARK: - WKWebView ラッパ
struct WebView: UIViewRepresentable {
    let url: URL?

    // Google の「埋め込みブラウザ」判定を避けるための Safari UA。
    // iOS のバージョンが上がったら数字を更新してください。
    static let safariUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var lastLoaded: URL? }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        // 既定の永続データストア = ログイン Cookie が起動を跨いで保持される
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Self.safariUA
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let url, context.coordinator.lastLoaded != url else { return }
        context.coordinator.lastLoaded = url
        webView.load(URLRequest(url: url))
    }
}
