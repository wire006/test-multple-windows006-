import Foundation

// MARK: - 依存ライブラリなしの簡易 Markdown → HTML 変換
//
// 見出し / 箇条書き / 番号付きリスト / コードブロック(```) / 引用は非対応部分あり
// ですが、太字・斜体・インラインコード・リンク・見出し・リスト・水平線・段落・
// コードフェンスといった「よく使う範囲」をカバーします。
// 完全な CommonMark が必要なら apple/swift-markdown か marked.js に差し替えてください。
enum MarkdownRenderer {

    /// 生 Markdown を、そのまま WKWebView に渡せる完全な HTML ページ文字列にする
    static func page(from markdown: String) -> String {
        let body = convert(markdown)
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body { font: 16px/1.6 -apple-system, system-ui, sans-serif; margin: 0; padding: 14px 16px;
                 color: #111; background: #fff; -webkit-text-size-adjust: 100%; word-wrap: break-word; }
          h1, h2, h3, h4 { line-height: 1.3; margin: 1em 0 .4em; }
          h1 { font-size: 1.6em; } h2 { font-size: 1.35em; } h3 { font-size: 1.15em; }
          p { margin: .5em 0; }
          ul, ol { margin: .5em 0; padding-left: 1.4em; }
          a { color: #0a84ff; }
          code { background: #f0f0f0; padding: 2px 5px; border-radius: 4px; font-size: .9em; }
          pre { background: #f0f0f0; padding: 10px 12px; border-radius: 8px; overflow: auto; }
          pre code { background: none; padding: 0; }
          hr { border: none; border-top: 1px solid #ddd; margin: 1em 0; }
          img { max-width: 100%; }
          blockquote { margin: .5em 0; padding-left: 12px; border-left: 3px solid #ccc; color: #555; }
          @media (prefers-color-scheme: dark) {
            body { color: #eee; background: #1c1c1e; }
            code, pre { background: #2c2c2e; }
            hr { border-top-color: #444; }
            blockquote { border-left-color: #555; color: #aaa; }
          }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    // MARK: ブロック要素の変換
    static func convert(_ md: String) -> String {
        var out = ""
        var inCode = false
        var codeBuf = ""
        var listType: String? = nil   // "ul" または "ol"
        var para: [String] = []

        func flushPara() {
            if !para.isEmpty {
                out += "<p>" + para.map(inline).joined(separator: " ") + "</p>\n"
                para = []
            }
        }
        func closeList() {
            if let lt = listType { out += "</\(lt)>\n"; listType = nil }
        }

        let lines = md.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // コードフェンス（```）の開始/終了
            if trimmed.hasPrefix("```") {
                if inCode {
                    out += "<pre><code>" + esc(codeBuf) + "</code></pre>\n"
                    codeBuf = ""; inCode = false
                } else {
                    flushPara(); closeList(); inCode = true
                }
                continue
            }
            if inCode { codeBuf += line + "\n"; continue }

            if trimmed.isEmpty { flushPara(); closeList(); continue }

            // 引用
            if trimmed.hasPrefix("> ") {
                flushPara(); closeList()
                out += "<blockquote>" + inline(String(trimmed.dropFirst(2))) + "</blockquote>\n"
                continue
            }
            // 見出し
            if let h = heading(trimmed) {
                flushPara(); closeList()
                out += "<h\(h.level)>" + inline(h.text) + "</h\(h.level)>\n"
                continue
            }
            // 水平線
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushPara(); closeList(); out += "<hr>\n"; continue
            }
            // 箇条書き
            if let item = bullet(trimmed) {
                flushPara()
                if listType != "ul" { closeList(); out += "<ul>\n"; listType = "ul" }
                out += "<li>" + inline(item) + "</li>\n"
                continue
            }
            // 番号付きリスト
            if let item = ordered(trimmed) {
                flushPara()
                if listType != "ol" { closeList(); out += "<ol>\n"; listType = "ol" }
                out += "<li>" + inline(item) + "</li>\n"
                continue
            }
            // 段落
            closeList()
            para.append(trimmed)
        }
        if inCode { out += "<pre><code>" + esc(codeBuf) + "</code></pre>\n" }
        flushPara(); closeList()
        return out
    }

    // MARK: インライン要素の変換
    static func inline(_ raw: String) -> String {
        var t = esc(raw)
        t = t.replacingOccurrences(of: "`([^`]+)`", with: "<code>$1</code>", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\[([^\\]]+)\\]\\(([^)]+)\\)", with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\*([^*]+)\\*", with: "<em>$1</em>", options: .regularExpression)
        return t
    }

    // MARK: ヘルパ
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func heading(_ s: String) -> (level: Int, text: String)? {
        var level = 0
        for c in s { if c == "#" { level += 1 } else { break } }
        guard (1...6).contains(level) else { return nil }
        let rest = s.dropFirst(level)
        guard rest.first == " " else { return nil }
        return (level, String(rest.drop(while: { $0 == " " })))
    }

    static func bullet(_ s: String) -> String? {
        for p in ["- ", "* ", "+ "] where s.hasPrefix(p) { return String(s.dropFirst(2)) }
        return nil
    }

    static func ordered(_ s: String) -> String? {
        var digits = ""
        for c in s { if c.isNumber { digits.append(c) } else { break } }
        guard !digits.isEmpty else { return nil }
        let after = s.dropFirst(digits.count)
        guard after.hasPrefix(". ") else { return nil }
        return String(after.dropFirst(2))
    }
}
