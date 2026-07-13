import SwiftUI
import WebKit
import UniformTypeIdentifiers
import UIKit

// MARK: - 用途3: Files の md / txt を2つ、上下2分割で表示（文字サイズ調整可）
//
// テキストはアプリ側で組版するので、ペイン幅に合わせて自動改行（リフロー）し、
// どんな文字サイズでも見切れない。文字サイズは各ペインの −/＋ で変更でき、
// @AppStorage に保存される（スクロール位置を保つため JS でライブ更新）。
// MARK: - 2ペインのスクロール進捗(%)を同期する
final class ScrollSync: ObservableObject {
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "text.sync.enabled") } }
    private weak var topWV: WKWebView?
    private weak var bottomWV: WKWebView?

    init() { enabled = UserDefaults.standard.bool(forKey: "text.sync.enabled") }

    func register(_ wv: WKWebView, top: Bool) { if top { topWV = wv } else { bottomWV = wv } }

    /// source がユーザー操作でスクロールしたら、もう片方を同じ割合(%)に合わせる
    func scrolled(_ source: WKWebView) {
        guard enabled else { return }
        let sv = source.scrollView
        // ユーザーが実際に触っている側だけを基準に（プログラム的スクロールのエコーを防止）
        guard sv.isDragging || sv.isDecelerating else { return }
        let other = (source === topWV) ? bottomWV : (source === bottomWV ? topWV : nil)
        guard let other else { return }
        let denom = max(1, sv.contentSize.height - sv.bounds.height)
        let f = min(1, max(0, sv.contentOffset.y / denom))
        let o = other.scrollView
        let odenom = max(1, o.contentSize.height - o.bounds.height)
        o.setContentOffset(CGPoint(x: 0, y: f * odenom), animated: false)
    }
}

struct TextSplit: View {
    @StateObject private var topSlot = BookmarkSlot(key: "slot.text.top")
    @StateObject private var bottomSlot = BookmarkSlot(key: "slot.text.bottom")
    @StateObject private var sync = ScrollSync()

    var body: some View {
        VSplit("text") {
            TextPane(title: "テキスト（上）", slot: topSlot, fontKey: "text.font.top",
                     scrollKey: "scroll.text.top", sync: sync, isTop: true)
        } bottom: {
            TextPane(title: "テキスト（下）", slot: bottomSlot, fontKey: "text.font.bottom",
                     scrollKey: "scroll.text.bottom", sync: sync, isTop: false)
        }
    }
}

struct TextPane: View {
    let title: String
    @ObservedObject var slot: BookmarkSlot
    let scrollKey: String
    @ObservedObject var sync: ScrollSync
    let isTop: Bool
    @AppStorage private var fontSize: Double
    @State private var importing = false
    @State private var html = ""

    private static let types: [UTType] = [
        .plainText, .text,
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "markdown") ?? .plainText,
        UTType(filenameExtension: "txt") ?? .plainText,
    ]

    init(title: String, slot: BookmarkSlot, fontKey: String, scrollKey: String,
         sync: ScrollSync, isTop: Bool) {
        self.title = title
        self._slot = ObservedObject(wrappedValue: slot)
        self.scrollKey = scrollKey
        self._sync = ObservedObject(wrappedValue: sync)
        self.isTop = isTop
        self._fontSize = AppStorage(wrappedValue: 17.0, fontKey)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isTop { toolbar }        // 上ペインはバーを上に
            TextHTMLView(html: html, fontSize: fontSize, scrollKey: scrollKey, sync: sync, isTop: isTop)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !isTop { toolbar }       // 下ペインはバーを最下部に（本文どうしを中央で隣接）
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: Self.types,
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let u = urls.first {
                UserDefaults.standard.set(0.0, forKey: scrollKey)   // 別ファイルは先頭から
                slot.set(u)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: slot.url) { _ in reload() }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text(title).font(.headline)
            if let name = slot.url?.lastPathComponent {
                Text(name).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button { sync.enabled.toggle() } label: {   // スクロール同期のオン/オフ
                Image(systemName: sync.enabled ? "link.circle.fill" : "link.circle")
            }
            Button { setFont(fontSize - 1) } label: { Image(systemName: "textformat.size.smaller") }
                .disabled(fontSize <= 10)
            Button { setFont(fontSize + 1) } label: { Image(systemName: "textformat.size.larger") }
                .disabled(fontSize >= 40)
            Button("選択") { importing = true }.buttonStyle(.bordered)
        }
        .font(.system(size: 17))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)          // 名前バーの上下幅を薄く
        .background(.thinMaterial)
    }

    private func setFont(_ v: Double) {
        // @AppStorage が保存。html は再生成せず、TextHTMLView が JS でライブ更新する。
        fontSize = min(40, max(10, v))
    }

    private func reload() {
        guard let u = slot.url else {
            html = TextRenderer.page(text: "「選択」で md / txt ファイルを開いてください。",
                                     markdown: false, fontSize: fontSize)
            return
        }
        let ok = u.startAccessingSecurityScopedResource()
        defer { if ok { u.stopAccessingSecurityScopedResource() } }
        let ext = u.pathExtension.lowercased()
        if let text = try? String(contentsOf: u, encoding: .utf8) {
            html = TextRenderer.page(text: text,
                                     markdown: (ext == "md" || ext == "markdown"),
                                     fontSize: fontSize)
        } else {
            html = TextRenderer.page(text: "読み込みに失敗しました。", markdown: false, fontSize: fontSize)
        }
    }
}

// MARK: - HTML を表示（文字サイズは JS でライブ更新してスクロール位置を保つ）
struct TextHTMLView: UIViewRepresentable {
    let html: String
    let fontSize: Double
    let scrollKey: String
    let sync: ScrollSync
    let isTop: Bool

    func makeCoordinator() -> Coordinator { Coordinator(scrollKey: scrollKey, sync: sync, isTop: isTop) }

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView()
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.navigationDelegate = context.coordinator
        context.coordinator.webView = wv
        sync.register(wv, top: isTop)
        context.coordinator.observeScroll(wv)
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        let c = context.coordinator
        if c.lastHTML != html {
            c.lastHTML = html
            c.lastFont = fontSize
            wv.loadHTMLString(html, baseURL: nil)
        } else if c.lastFont != fontSize {
            c.lastFont = fontSize
            wv.evaluateJavaScript(
                "document.documentElement.style.setProperty('--fs','\(Int(fontSize))px')",
                completionHandler: nil)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let scrollKey: String
        let sync: ScrollSync
        let isTop: Bool
        var lastHTML: String?
        var lastFont: Double = -1
        weak var webView: WKWebView?
        private var token: NSObjectProtocol?
        private var scrollObs: NSKeyValueObservation?

        init(scrollKey: String, sync: ScrollSync, isTop: Bool) {
            self.scrollKey = scrollKey
            self.sync = sync
            self.isTop = isTop
            super.init()
            // バックグラウンドに移る瞬間にスクロール位置（割合）を保存
            token = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.save() }
        }
        deinit {
            if let t = token { NotificationCenter.default.removeObserver(t) }
            scrollObs?.invalidate()
        }

        // スクロールを監視し、同期がオンならもう片方を同じ割合に合わせる
        func observeScroll(_ wv: WKWebView) {
            scrollObs = wv.scrollView.observe(\.contentOffset, options: [.new]) { [weak self, weak wv] _, _ in
                guard let self, let wv else { return }
                self.sync.scrolled(wv)
            }
        }

        func save() {
            guard let sv = webView?.scrollView else { return }
            let denom = max(1, sv.contentSize.height - sv.bounds.height)
            let f = min(1, max(0, Double(sv.contentOffset.y / denom)))
            UserDefaults.standard.set(f, forKey: scrollKey)
        }

        // 読み込み完了後、保存した割合位置まで復元
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let f = UserDefaults.standard.double(forKey: scrollKey)
            guard f > 0 else { return }
            webView.evaluateJavaScript(
                "window.scrollTo(0,(document.documentElement.scrollHeight-window.innerHeight)*\(f))",
                completionHandler: nil)
        }
    }
}

// MARK: - md / txt を HTML 化（文字サイズは CSS 変数 --fs）
enum TextRenderer {
    static func page(text: String, markdown: Bool, fontSize: Double) -> String {
        let body = markdown ? MarkdownMini.convert(text)
                            : "<pre class=\"txt\">" + esc(text) + "</pre>"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { --fs: \(Int(fontSize))px; }
          body { font: var(--fs)/1.75 -apple-system, system-ui, sans-serif; margin: 0; padding: 12px 14px;
                 color: #111; background: #fff; -webkit-text-size-adjust: 100%;
                 word-wrap: break-word; overflow-wrap: break-word; }
          pre.txt { white-space: pre-wrap; word-wrap: break-word; overflow-wrap: break-word;
                    font: var(--fs)/1.75 -apple-system, system-ui, sans-serif; margin: 0;
                    background: none; padding: 0; }
          h1 { font-size: 1.6em; } h2 { font-size: 1.35em; } h3 { font-size: 1.15em; }
          h1,h2,h3,h4 { line-height: 1.3; margin: .8em 0 .3em; }
          p { margin: .5em 0; } ul,ol { padding-left: 1.4em; margin: .5em 0; }
          a { color: #0a84ff; }
          code { background: #f0f0f0; padding: 2px 5px; border-radius: 4px; font-size: .92em;
                 font-family: ui-monospace, Menlo, monospace; }
          pre:not(.txt) { background: #f0f0f0; padding: 10px 12px; border-radius: 8px; overflow-x: auto; }
          pre:not(.txt) code { background: none; padding: 0; }
          hr { border: none; border-top: 1px solid #ddd; margin: 1em 0; }
          blockquote { margin: .5em 0; padding-left: 12px; border-left: 3px solid #ccc; color: #555; }
          @media (prefers-color-scheme: dark) {
            body, pre.txt { color: #eee; background: #1c1c1e; }
            code, pre:not(.txt) { background: #2c2c2e; }
            blockquote { border-left-color: #555; color: #aaa; } hr { border-top-color: #444; }
          }
        </style></head><body>\(body)</body></html>
        """
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - 依存なしの簡易 Markdown → HTML（見出し/リスト/引用/コード/装飾/リンク）
enum MarkdownMini {
    static func convert(_ md: String) -> String {
        var out = ""
        var inCode = false
        var codeBuf = ""
        var listType: String?
        var para: [String] = []

        func flushPara() {
            if !para.isEmpty { out += "<p>" + para.map(inline).joined(separator: " ") + "</p>\n"; para = [] }
        }
        func closeList() { if let lt = listType { out += "</\(lt)>\n"; listType = nil } }

        let lines = md.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") {
                if inCode { out += "<pre><code>" + esc(codeBuf) + "</code></pre>\n"; codeBuf = ""; inCode = false }
                else { flushPara(); closeList(); inCode = true }
                continue
            }
            if inCode { codeBuf += line + "\n"; continue }
            if t.isEmpty { flushPara(); closeList(); continue }
            if t.hasPrefix("> ") {
                flushPara(); closeList()
                out += "<blockquote>" + inline(String(t.dropFirst(2))) + "</blockquote>\n"; continue
            }
            if let h = heading(t) { flushPara(); closeList(); out += "<h\(h.0)>" + inline(h.1) + "</h\(h.0)>\n"; continue }
            if t == "---" || t == "***" || t == "___" { flushPara(); closeList(); out += "<hr>\n"; continue }
            if let item = bullet(t) {
                flushPara()
                if listType != "ul" { closeList(); out += "<ul>\n"; listType = "ul" }
                out += "<li>" + inline(item) + "</li>\n"; continue
            }
            if let item = ordered(t) {
                flushPara()
                if listType != "ol" { closeList(); out += "<ol>\n"; listType = "ol" }
                out += "<li>" + inline(item) + "</li>\n"; continue
            }
            closeList(); para.append(t)
        }
        if inCode { out += "<pre><code>" + esc(codeBuf) + "</code></pre>\n" }
        flushPara(); closeList()
        return out
    }

    static func inline(_ raw: String) -> String {
        var s = esc(raw)
        s = s.replacingOccurrences(of: "`([^`]+)`", with: "<code>$1</code>", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\[([^\\]]+)\\]\\(([^)]+)\\)", with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\*([^*]+)\\*", with: "<em>$1</em>", options: .regularExpression)
        return s
    }

    static func esc(_ s: String) -> String { TextRenderer.esc(s) }

    static func heading(_ s: String) -> (Int, String)? {
        var n = 0
        for c in s { if c == "#" { n += 1 } else { break } }
        guard (1...6).contains(n) else { return nil }
        let rest = s.dropFirst(n)
        guard rest.first == " " else { return nil }
        return (n, String(rest.drop(while: { $0 == " " })))
    }

    static func bullet(_ s: String) -> String? {
        for p in ["- ", "* ", "+ "] where s.hasPrefix(p) { return String(s.dropFirst(2)) }
        return nil
    }

    static func ordered(_ s: String) -> String? {
        var d = ""
        for c in s { if c.isNumber { d.append(c) } else { break } }
        guard !d.isEmpty else { return nil }
        let after = s.dropFirst(d.count)
        guard after.hasPrefix(". ") else { return nil }
        return String(after.dropFirst(2))
    }
}
