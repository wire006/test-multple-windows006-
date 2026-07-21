import Foundation
import WebKit

// MARK: - 分割ブラウザ用の広告ブロック（WKContentRuleList）
//
// 起動時に複数の定番フィルタ（AdGuard 日本語 / AdGuard ベース / EasyList）を取得し、
// 2種類の規則にコンパイルして各 WebView に適用する：
//   1. ネットワークブロック … 広告ドメインへの通信を遮断（||domain^ 規則）
//   2. 要素非表示(cosmetic) … 残った広告枠を CSS で非表示（##selector 規則）
// 日本のサイト（まとめ／掲示板など）の広告は AdGuard 日本語が要素非表示で消してくれる。
//
// コンパイル済みは WKContentRuleListStore が識別子ごとに端末キャッシュするので、
// 次回起動時は即適用（更新は1日1回だけ取得）。
//
// 要素非表示規則は複数チャンクに分けてコンパイルする。1つのセレクタが
// コンパイル不能でも、そのチャンクだけが無効になり他は生き残るようにするため。
//
// Safari のコンテンツブロッカー（AdGuard 等の Safari 拡張）はサードパーティアプリの
// WKWebView には効かないため、このようにアプリ側でルールを読み込ませる必要がある。
final class AdBlock {
    static let shared = AdBlock()

    // 取得元フィルタ（アドブロック構文テキスト）。日本のサイト向けに日本語フィルタも併用。
    // 先頭ほど優先（上限に達したら後ろが切り捨てられるので、日本語を最優先）。
    private let sources: [URL] = [
        URL(string: "https://filters.adtidy.org/extension/safari/filters/7.txt")!, // AdGuard 日本語
        URL(string: "https://filters.adtidy.org/extension/safari/filters/2.txt")!, // AdGuard ベース
        URL(string: "https://easylist.to/easylist/easylist.txt")!,                 // EasyList（国際）
    ]
    private let netID = "ads-net-v2"                 // ネットワークブロック規則
    private func cosID(_ i: Int) -> String { "ads-cos-v2-\(i)" }   // 要素非表示規則（チャンク）
    private let oldID = "ads-rules-v1"               // 旧バージョン（掃除用）
    private static let maxCosChunks = 4              // 要素非表示チャンク数
    private let lastFetchKey = "adblock.lastFetch.v2"
    private let refreshInterval: TimeInterval = 24 * 60 * 60   // 1日

    private var lists: [WKContentRuleList] = []
    private var registered: [WeakWeb] = []
    private var started = false

    private final class WeakWeb {
        weak var wv: WKWebView?
        var applied = false      // このWebViewに規則適用済みか（初回だけ再読み込みする）
        init(_ w: WKWebView) { wv = w }
    }

    /// アプリ起動時に一度呼ぶ。キャッシュを即適用し、古ければ最新版を取得。
    func start() {
        guard !started else { return }
        started = true
        guard let store = WKContentRuleListStore.default() else { return }
        store.removeContentRuleList(forIdentifier: oldID) { _ in }   // 旧版キャッシュの掃除

        // キャッシュ済みのリスト（ネット + 要素非表示チャンク）を引き当てて即適用
        let ids = [netID] + (0..<Self.maxCosChunks).map { cosID($0) }
        let group = DispatchGroup()
        let lock = NSLock()
        var cached: [WKContentRuleList] = []
        var foundNet = false
        for id in ids {
            group.enter()
            store.lookUpContentRuleList(forIdentifier: id) { list, _ in
                if let list {
                    lock.lock()
                    cached.append(list)
                    if id == self.netID { foundNet = true }
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if !cached.isEmpty { self.applyAll(cached) }
            let last = UserDefaults.standard.double(forKey: self.lastFetchKey)
            let stale = Date().timeIntervalSince1970 - last > self.refreshInterval
            if !foundNet || stale { self.fetchAndCompile() }
        }
    }

    /// WebView 生成時に登録。ルールが用意済みなら、読み込み前に適用する。
    func register(_ webView: WKWebView) {
        let entry = WeakWeb(webView)
        if !lists.isEmpty {
            for l in lists { webView.configuration.userContentController.add(l) }
            entry.applied = true
        }
        registered.append(entry)
    }

    /// 用意できた規則リストを全 WebView に適用。
    /// まだ素通しで読み込んだ WebView は一度だけ再読み込みして反映する。
    private func applyAll(_ newLists: [WKContentRuleList]) {
        guard !newLists.isEmpty else { return }
        lists = newLists
        registered.removeAll { $0.wv == nil }
        for e in registered {
            guard let wv = e.wv else { continue }
            wv.configuration.userContentController.removeAllContentRuleLists()
            for l in newLists { wv.configuration.userContentController.add(l) }
            if !e.applied {
                e.applied = true
                wv.reload()
            }
        }
    }

    private func fetchAndCompile() {
        let group = DispatchGroup()
        let lock = NSLock()
        var chunks: [(Int, String)] = []     // (優先順位, テキスト)
        for (i, url) in sources.enumerated() {
            group.enter()
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data, let s = String(data: data, encoding: .utf8) {
                    lock.lock(); chunks.append((i, s)); lock.unlock()
                }
                group.leave()
            }.resume()
        }
        group.notify(queue: .global(qos: .utility)) { [weak self] in
            guard let self, !chunks.isEmpty else { return }
            // 取得順に関わらず sources の並び（＝優先順）で連結
            let text = chunks.sorted { $0.0 < $1.0 }.map { $0.1 }.joined(separator: "\n")
            let (netJSON, cosJSONs) = Self.convert(text)
            var jobs: [(String, String)] = [(self.netID, netJSON)]
            for (i, json) in cosJSONs.enumerated() { jobs.append((self.cosID(i), json)) }
            DispatchQueue.main.async {
                guard let store = WKContentRuleListStore.default() else { return }
                self.compileMany(store, jobs) { compiled in
                    guard !compiled.isEmpty else { return }
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: self.lastFetchKey)
                    self.applyAll(compiled)
                }
            }
        }
    }

    /// 複数の (識別子, JSON) を順にコンパイルし、成功したリストだけ集めて返す。
    private func compileMany(_ store: WKContentRuleListStore, _ jobs: [(String, String)],
                             _ acc: [WKContentRuleList] = [],
                             _ done: @escaping ([WKContentRuleList]) -> Void) {
        guard let (id, json) = jobs.first else { done(acc); return }
        let rest = Array(jobs.dropFirst())
        guard json != "[]" else { compileMany(store, rest, acc, done); return }
        store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: json) { [weak self] list, _ in
            guard let self else { return }
            var acc2 = acc
            if let list { acc2.append(list) }
            DispatchQueue.main.async { self.compileMany(store, rest, acc2, done) }
        }
    }

    // MARK: - 変換（アドブロック構文 → WKContentRuleList JSON）

    /// フィルタ群テキストから (ネットワークブロック用JSON, 要素非表示用JSONチャンク配列) を生成。
    /// 確実にコンパイル可能な規則だけを採用し、拡張構文（:has 等）は捨てる。
    static func convert(_ text: String, netLimit: Int = 50000, chunkSize: Int = 10000)
        -> (net: String, cos: [String]) {
        var netRules: [[String: Any]] = []
        var cosRules: [[String: Any]] = []
        var seenNet = Set<String>()
        var seenCos = Set<String>()
        let cosLimit = maxCosChunks * chunkSize

        for rawSub in text.split(separator: "\n") {
            let line = String(rawSub).trimmingCharacters(in: .whitespaces)
            guard let first = line.first, first != "!", first != "[" else { continue }  // 空行/コメント

            // ---- ネットワークブロック規則: ||domain^ ----
            if line.hasPrefix("||") {
                if netRules.count < netLimit, let domain = networkDomain(line) {
                    let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
                    if seenNet.insert(escaped).inserted {
                        netRules.append(["trigger": ["url-filter": escaped],
                                         "action": ["type": "block"]])
                    }
                }
                continue
            }

            // ---- 要素非表示規則: [domains]##selector ----
            // 例外(#@#)や拡張(#?# #$# 等)は "##" を含まないので自然に除外される。
            if cosRules.count < cosLimit, let r = line.range(of: "##") {
                let selector = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                guard isSafeSelector(selector) else { continue }
                let domainsPart = String(line[line.startIndex..<r.lowerBound])
                guard let (ifD, unlessD) = parseDomains(domainsPart) else { continue }
                var trigger: [String: Any] = ["url-filter": ".*"]
                if !ifD.isEmpty { trigger["if-domain"] = ifD }
                else if !unlessD.isEmpty { trigger["unless-domain"] = unlessD }
                let sig = ifD.joined(separator: ",") + "~" + unlessD.joined(separator: ",") + "##" + selector
                if seenCos.insert(sig).inserted {
                    cosRules.append(["trigger": trigger,
                                     "action": ["type": "css-display-none", "selector": selector]])
                }
            }
        }

        // 要素非表示規則を chunkSize ごとに分割してそれぞれ JSON 化
        var cosChunks: [String] = []
        var idx = 0
        while idx < cosRules.count {
            let end = min(idx + chunkSize, cosRules.count)
            cosChunks.append(jsonString(Array(cosRules[idx..<end])))
            idx = end
        }
        return (jsonString(netRules), cosChunks)
    }

    private static func jsonString(_ rules: [[String: Any]]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: rules)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    /// ||...^ 行からドメインを取り出す（$オプションやパスは除去）。
    static func networkDomain(_ line: String) -> String? {
        var s = String(line.dropFirst(2))
        if let i = s.firstIndex(of: "$") { s = String(s[..<i]) }   // $以降のオプション除去
        for sep in "^/*:?" {                                       // ドメイン区切りで切る
            if let i = s.firstIndex(of: sep) { s = String(s[..<i]) }
        }
        guard s.count >= 3, s.contains("."),
              s.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") })
        else { return nil }
        return s
    }

    /// ドメイン指定部を (適用ドメイン, 除外ドメイン) に分解。不正を含めば nil で規則ごと破棄。
    /// サブドメインにも効くよう先頭に "*" を付与（WKContentRuleList の記法）。
    static func parseDomains(_ part: String) -> (ifD: [String], unlessD: [String])? {
        if part.isEmpty { return ([], []) }
        var ifD: [String] = []
        var unlessD: [String] = []
        for token in part.split(separator: ",") {
            var d = String(token).trimmingCharacters(in: .whitespaces)
            var negate = false
            if d.hasPrefix("~") { negate = true; d.removeFirst() }
            guard isDomain(d) else { return nil }
            if negate { unlessD.append("*" + d) } else { ifD.append("*" + d) }
        }
        return (ifD, unlessD)
    }

    static func isDomain(_ d: String) -> Bool {
        d.count >= 2 && d.contains(".") &&
        d.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
    }

    // css-display-none で使える文字（素直なCSSセレクタ＋属性値中のURL文字）。拡張構文は弾く。
    private static let selectorAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: " .#*,>+~[]=\"'-_:()^$|/%&?")
        return set
    }()

    /// WKContentRuleList でコンパイル可能な「素直なCSSセレクタ」だけ許可。
    static func isSafeSelector(_ s: String) -> Bool {
        guard s.count >= 1, s.count <= 400 else { return false }
        if s.contains("::") { return false }                          // 疑似要素は不可
        if s.contains("/*") { return false }                          // CSSコメント混入を排除
        let bad = [":has(", ":has-text(", ":contains(", ":-abp-", ":matches-css",
                   ":matches-attr", ":matches-path", ":xpath(", ":nth-ancestor(",
                   ":upward(", ":remove(", ":style(", ":watch-attr", "[-ext-", ">>>"]
        for b in bad where s.contains(b) { return false }
        return s.unicodeScalars.allSatisfy { selectorAllowed.contains($0) }
    }
}
