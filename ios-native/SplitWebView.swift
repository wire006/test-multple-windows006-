import SwiftUI
import WebKit

// MARK: - 案A: 2つの WKWebView を上下分割するネイティブアプリの雛形
//
// 上下それぞれで別々の Web サービス（YouTube / X(Web) / Gmail / ChatGPT 等）を
// 同時に開ける、自作の「疑似2画面」アプリです。
// iOS の制約上「他のネイティブアプリ」は取り込めませんが、Web 版があるサービスなら
// 実質的に2つのアプリを上下に並べて使えます。
//
// 使い方:
//   1. Xcode で iOS App プロジェクトを新規作成（Interface: SwiftUI）
//   2. 自動生成された ***App.swift の中身をこのファイルで置き換える
//      （または本ファイルをプロジェクトに追加し、既存の @main を削除）
//   3. 実機を接続して Run（無料の Apple ID でも7日間は実機で動作可）

// MARK: - WKWebView を SwiftUI から使うためのラッパ
struct WebView: UIViewRepresentable {
    let url: URL?

    func makeCoordinator() -> Coordinator { Coordinator() }

    // 直近で読み込んだ URL を覚えておき、サイトのリダイレクトによる
    // 再読み込みループを防ぐ
    final class Coordinator {
        var lastLoaded: URL?
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true                       // 全画面化せず枠内で再生
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true            // 端スワイプで戻る/進む
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let url, context.coordinator.lastLoaded != url else { return }
        context.coordinator.lastLoaded = url
        webView.load(URLRequest(url: url))
    }
}

// MARK: - 1ペイン（URLバー + WebView）
struct Pane: View {
    let title: String
    @Binding var text: String     // 入力欄の文字列
    @Binding var url: URL?        // 実際に読み込む URL

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

// MARK: - 上下分割 + ドラッグ可能な仕切り
struct ContentView: View {
    private static let defaultTop = "https://www.youtube.com/embed/aqz-KE-bpKQ"
    // WKWebView は本物のブラウザなので、iframe 版では表示できない全サイトも直接開ける
    private static let defaultBottom = "https://ja.m.wikipedia.org/wiki/iPhone"

    @State private var topText = defaultTop
    @State private var bottomText = defaultBottom
    @State private var topURL: URL? = URL(string: defaultTop)
    @State private var bottomURL: URL? = URL(string: defaultBottom)

    @State private var topHeight: CGFloat = 320   // 上ペインの高さ(pt)
    @State private var dragStart: CGFloat? = nil  // ドラッグ開始時の高さ

    private let dividerH: CGFloat = 26
    private let minPane: CGFloat = 120

    var body: some View {
        GeometryReader { geo in
            let maxTop = max(minPane, geo.size.height - dividerH - minPane)
            let clampedTop = min(max(minPane, topHeight), maxTop)

            VStack(spacing: 0) {
                Pane(title: "上のURL", text: $topText, url: $topURL)
                    .frame(height: clampedTop)

                divider

                Pane(title: "下のURL", text: $bottomText, url: $bottomURL)
                    .frame(maxHeight: .infinity)
            }
        }
        .ignoresSafeArea(.keyboard)   // キーボードでレイアウトが押し上がるのを防ぐ
    }

    private var divider: some View {
        ZStack {
            Color(.systemGray5)
            Capsule()
                .fill(Color(.systemGray))
                .frame(width: 44, height: 5)
        }
        .frame(height: dividerH)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStart == nil { dragStart = topHeight }
                    topHeight = (dragStart ?? topHeight) + value.translation.height
                }
                .onEnded { _ in dragStart = nil }
        )
    }
}

// MARK: - アプリのエントリポイント
@main
struct SplitWebApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
