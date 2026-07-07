import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - 用途2: Files に保存した MD と PDF を上下2分割
//
// ・上ペイン: Markdown ファイル（.md / .markdown / .txt）を選んで整形表示
// ・下ペイン: PDF ファイルを PDFKit で表示
// ・Web ログインの問題は一切なし（ローカルファイルのみ）。実機で最も確実に動く用途。
// ・選んだファイルは「セキュリティスコープ付きブックマーク」で保存し、次回起動時も復元します。

struct DocsSplit: View {
    @StateObject private var mdSlot = BookmarkSlot(key: "slot.markdown")
    @StateObject private var pdfSlot = BookmarkSlot(key: "slot.pdf")

    var body: some View {
        VerticalSplit {
            MarkdownPane(slot: mdSlot)
        } bottom: {
            PDFPane(slot: pdfSlot)
        }
    }
}

// MARK: - 選択したファイルの参照を永続化する入れ物
final class BookmarkSlot: ObservableObject {
    @Published var url: URL?
    private let key: String

    init(key: String) {
        self.key = key
        restore()
    }

    /// ファイル選択時に呼ぶ。ブックマークを保存し、url を更新する。
    func set(_ picked: URL) {
        let accessing = picked.startAccessingSecurityScopedResource()
        defer { if accessing { picked.stopAccessingSecurityScopedResource() } }
        do {
            let data = try picked.bookmarkData()
            UserDefaults.standard.set(data, forKey: key)
            url = picked
        } catch {
            print("bookmark save failed:", error)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        var stale = false
        if let resolved = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) {
            url = resolved
        }
    }
}

// MARK: - Markdown ペイン
struct MarkdownPane: View {
    @ObservedObject var slot: BookmarkSlot
    @State private var page = MarkdownRenderer.page(from: "MDファイルを「選択」してください。")
    @State private var importing = false

    private static let mdTypes: [UTType] = [
        .plainText, .text,
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "markdown") ?? .plainText,
    ]

    var body: some View {
        VStack(spacing: 0) {
            PaneBar(title: "Markdown", filename: slot.url?.lastPathComponent) { importing = true }
            HTMLView(html: page)
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: Self.mdTypes,
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let u = urls.first {
                slot.set(u)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: slot.url) { _ in reload() }
    }

    private func reload() {
        guard let u = slot.url else { return }
        let accessing = u.startAccessingSecurityScopedResource()
        defer { if accessing { u.stopAccessingSecurityScopedResource() } }
        if let text = try? String(contentsOf: u, encoding: .utf8) {
            page = MarkdownRenderer.page(from: text)
        } else {
            page = MarkdownRenderer.page(from: "読み込みに失敗しました。\niCloud 上のファイルは未ダウンロードだと読めない場合があります。")
        }
    }
}

// MARK: - PDF ペイン
struct PDFPane: View {
    @ObservedObject var slot: BookmarkSlot
    @State private var importing = false

    var body: some View {
        VStack(spacing: 0) {
            PaneBar(title: "PDF", filename: slot.url?.lastPathComponent) { importing = true }
            PDFKitView(url: slot.url)
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.pdf],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let u = urls.first {
                slot.set(u)
            }
        }
    }
}

// MARK: - HTML（整形済み Markdown）を表示する WKWebView
struct HTMLView: UIViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var last: String? }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.last != html else { return }
        context.coordinator.last = html
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - PDFKit を SwiftUI から使う
struct PDFKitView: UIViewRepresentable {
    let url: URL?

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard let url else { return }
        guard view.document?.documentURL != url else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        view.document = PDFDocument(url: url)
    }
}
