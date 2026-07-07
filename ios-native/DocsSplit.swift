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

    var body: some View {
        VSplit {
            PDFPane(title: "PDF（上）", slot: topSlot)
        } bottom: {
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

    func makeUIView(context: Context) -> WidthFitPDFView {
        let view = WidthFitPDFView()
        view.autoScales = false          // 幅フィットは自前で行う（全体縮小を避ける）
        // モバイルWebのように、縦スクロールだけで全ページを連続して読める設定
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .systemBackground
        return view
    }

    func updateUIView(_ view: WidthFitPDFView, context: Context) {
        guard let url else { return }
        guard view.document?.documentURL != url else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        view.document = PDFDocument(url: url)
        view.refitWidth()   // 新しい文書に合わせて幅フィットし直す
    }
}

// MARK: - ページ幅を常にペイン幅に合わせる PDFView
//
// 縦長ページを短いペインに入れても文字が小さくならないよう、ページ幅を
// ペイン幅いっぱいに拡大する（高さははみ出して縦スクロールで読む）。
final class WidthFitPDFView: PDFView {
    private var lastFitWidth: CGFloat = -1
    private var cachedContentWidth: CGFloat?
    private let sideMargin: CGFloat = 8            // 左右にこれだけ余白（小さいほど本文が幅いっぱい）

    /// 新しい文書に切り替えたら呼ぶ（次のレイアウトで再フィット）
    func refitWidth() {
        lastFitWidth = -1
        cachedContentWidth = nil
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 1, let page = document?.page(at: 0) else { return }
        // 幅が変わったときだけ再フィット（毎回やるとユーザーのピンチズームを打ち消すため）
        if abs(bounds.width - lastFitWidth) < 0.5 { return }
        lastFitWidth = bounds.width

        let pageW = page.bounds(for: .cropBox).width
        guard pageW > 0 else { return }

        // ページ幅ではなく「本文（テキスト）の幅」に合わせる。
        // これで余白の広い PDF でも本文がペイン幅いっぱいになる（文書ごとに自動調整）。
        if cachedContentWidth == nil {
            var c = textContentWidth(of: page) ?? pageW
            if c < pageW * 0.2 { c = pageW }        // 念のための下限
            cachedContentWidth = c
        }
        let contentW = cachedContentWidth ?? pageW

        let fit = max(0.05, (bounds.width - sideMargin * 2) / contentW)
        minScaleFactor = fit * 0.2
        maxScaleFactor = fit * 8
        scaleFactor = fit
    }

    /// ページ内の全テキストを選択し、その境界の幅（＝本文の横幅）を返す
    private func textContentWidth(of page: PDFPage) -> CGFloat? {
        guard let doc = page.document else { return nil }
        let box = page.bounds(for: .cropBox)
        guard let sel = doc.selection(from: page, at: CGPoint(x: box.minX, y: box.maxY),
                                      to: page, at: CGPoint(x: box.maxX, y: box.minY)) else { return nil }
        if let s = sel.string, s.isEmpty { return nil }
        let w = sel.bounds(for: page).width
        return w > 1 ? w : nil
    }
}
