import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import UIKit

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
        VSplit("files") {
            PDFPane(title: "PDF（上）", slot: topSlot, scrollKey: "scroll.pdf.top")
        } bottom: {
            PDFPane(title: "PDF（下）", slot: bottomSlot, scrollKey: "scroll.pdf.bottom")
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
    let scrollKey: String
    @State private var importing = false

    var body: some View {
        VStack(spacing: 0) {
            PaneBar(title: title, filename: slot.url?.lastPathComponent) { importing = true }
            PDFKitView(url: slot.url, scrollKey: scrollKey)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.pdf],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let u = urls.first {
                UserDefaults.standard.removeObject(forKey: scrollKey + ".p")  // 別ファイルは先頭から
                UserDefaults.standard.removeObject(forKey: scrollKey + ".y")
                slot.set(u)
            }
        }
    }
}

// MARK: - PDFKit を SwiftUI から使う
struct PDFKitView: UIViewRepresentable {
    let url: URL?
    let scrollKey: String

    func makeUIView(context: Context) -> WidthFitPDFView {
        let view = WidthFitPDFView()
        view.setup(scrollKey: scrollKey)
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
        view.prepare()   // 本文幅にクロップして幅フィット
    }
}

// MARK: - 本文だけを切り出してペイン幅に合わせる PDFView
//
// ページ余白が広い PDF は、ページ幅に合わせても本文が細く・見切れやすい。
// そこで各ページを「本文（テキスト）の左右端」でクロップし、そのクロップ幅を
// ペイン幅に一致させる。これで本文が中央そろえで幅いっぱいになり、見切れない。
final class WidthFitPDFView: PDFView {
    private var lastFitWidth: CGFloat = -1
    private var cropWidth: CGFloat?     // クロップ後の共通ページ幅
    private var scrollKey: String?
    private var pendingRestore = false
    private var token: NSObjectProtocol?

    /// スクロール保存用のキーを設定し、バックグラウンド移行時に位置を保存する
    func setup(scrollKey: String) {
        self.scrollKey = scrollKey
        if token == nil {
            token = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.saveScroll() }
        }
    }
    deinit { if let t = token { NotificationCenter.default.removeObserver(t) } }

    /// 新しい文書を読み込んだら呼ぶ。本文幅にクロップして再フィット＆位置復元。
    func prepare() {
        cropToContent()
        lastFitWidth = -1
        pendingRestore = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 1 else { return }
        // 幅が変わったときだけ再フィット（ユーザーのピンチズームを毎回打ち消さない）
        if abs(bounds.width - lastFitWidth) >= 0.5 {
            lastFitWidth = bounds.width
            let w = cropWidth ?? document?.page(at: 0)?.bounds(for: .cropBox).width ?? 0
            if w > 0 {
                let fit = bounds.width / w     // クロップ幅（＝本文幅）をペイン幅に一致
                minScaleFactor = fit * 0.2
                maxScaleFactor = fit * 8
                scaleFactor = fit
            }
        }
        if pendingRestore, document != nil {
            pendingRestore = false
            DispatchQueue.main.async { [weak self] in self?.restoreScroll() }
        }
    }

    private func saveScroll() {
        guard let key = scrollKey, let dest = currentDestination,
              let doc = document, let page = dest.page else { return }
        UserDefaults.standard.set(doc.index(for: page), forKey: key + ".p")
        UserDefaults.standard.set(Double(dest.point.y), forKey: key + ".y")
    }

    private func restoreScroll() {
        guard let key = scrollKey, let doc = document,
              UserDefaults.standard.object(forKey: key + ".p") != nil else { return }
        let idx = UserDefaults.standard.integer(forKey: key + ".p")
        guard idx >= 0, idx < doc.pageCount, let page = doc.page(at: idx) else { return }
        let y = (UserDefaults.standard.object(forKey: key + ".y") as? Double).map { CGFloat($0) }
                ?? page.bounds(for: .cropBox).maxY
        go(to: PDFDestination(page: page, at: CGPoint(x: 0, y: y)))
    }

    /// 先頭数ページの本文の左右端を求め、全ページをその範囲にクロップする
    private func cropToContent() {
        cropWidth = nil
        guard let doc = document else { return }

        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        for i in 0..<min(8, doc.pageCount) {
            guard let page = doc.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox)
            guard let sel = doc.selection(from: page, at: CGPoint(x: box.minX, y: box.maxY),
                                          to: page, at: CGPoint(x: box.maxX, y: box.minY)),
                  let s = sel.string, !s.isEmpty else { continue }
            let b = sel.bounds(for: page)
            minX = min(minX, b.minX)
            maxX = max(maxX, b.maxX)
        }
        guard minX < maxX else { return }   // 選択できるテキストが無い（画像PDF等）→ クロップしない

        let pad: CGFloat = 6
        var width: CGFloat = 0
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let media = page.bounds(for: .mediaBox)
            let x0 = max(media.minX, minX - pad)
            let x1 = min(media.maxX, maxX + pad)
            guard x1 > x0 else { continue }
            page.setBounds(CGRect(x: x0, y: media.minY, width: x1 - x0, height: media.height),
                           for: .cropBox)
            width = x1 - x0
        }
        cropWidth = width > 1 ? width : nil
        layoutDocumentView()
    }
}
