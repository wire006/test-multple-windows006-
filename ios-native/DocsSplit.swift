import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - 用途2: Files に保存した PDF を2つ、上下2分割で表示
//
// ・上下それぞれ独立に PDF を選択（「選択」ボタン → Files アプリ）
// ・PDFKit(PDFView) でネイティブ表示。ペインごとに独立してスクロール/ズームできる
// ・選んだファイルは「セキュリティスコープ付きブックマーク」で保存し、次回起動時に復元
// ・ローカルファイルのみなので Web ログインの問題は一切なし（実機で最も確実な用途）

struct DocsSplit: View {
    @StateObject private var topSlot = BookmarkSlot(key: "slot.pdf.top")
    @StateObject private var bottomSlot = BookmarkSlot(key: "slot.pdf.bottom")
    @State private var fraction = 0.5

    var body: some View {
        TwoPaneSplit(axis: .vertical, fullscreen: .none, fraction: $fraction) {
            PDFPane(title: "PDF（上）", slot: topSlot)
        } second: {
            PDFPane(title: "PDF（下）", slot: bottomSlot)
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

// MARK: - PDF ペイン（選択バー + PDFView）
struct PDFPane: View {
    let title: String
    @ObservedObject var slot: BookmarkSlot
    @State private var importing = false

    var body: some View {
        VStack(spacing: 0) {
            PaneBar(title: title, filename: slot.url?.lastPathComponent) { importing = true }
            PDFKitView(url: slot.url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.pdf],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let u = urls.first {
                slot.set(u)
            }
        }
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
