import Foundation
import WebKit

// MARK: - 分割ブラウザ用の広告ブロック（WKContentRuleList）
//
// 起動時に EasyList を取得し、広告ドメインのブロック規則に変換して WKContentRuleList
// にコンパイルし、各 WebView に適用する。コンパイル済みは WKContentRuleListStore が
// 識別子ごとに端末キャッシュするので、次回起動時は即適用（更新は1日1回だけ取得）。
//
// Safari のコンテンツブロッカー（AdGuard 等の Safari 拡張）はサードパーティアプリの
// WKWebView には効かないため、このようにアプリ側でルールを読み込ませる必要がある。
final class AdBlock {
    static let shared = AdBlock()

    private let identifier = "ads-rules-v1"
    private let listURL = URL(string: "https://easylist.to/easylist/easylist.txt")!
    private let lastFetchKey = "adblock.lastFetch"
    private let refreshInterval: TimeInterval = 24 * 60 * 60   // 1日

    private var ruleList: WKContentRuleList?
    private var registered: [WeakWeb] = []
    private var started = false

    private final class WeakWeb { weak var wv: WKWebView?; init(_ w: WKWebView) { wv = w } }

    /// アプリ起動時に一度呼ぶ。キャッシュを即適用し、古ければ最新版を取得。
    func start() {
        guard !started else { return }
        started = true
        guard let store = WKContentRuleListStore.default() else { return }
        store.lookUpContentRuleList(forIdentifier: identifier) { [weak self] list, _ in
            guard let self else { return }
            if let list { self.apply(list, reload: false) }
            let last = UserDefaults.standard.double(forKey: self.lastFetchKey)
            let stale = Date().timeIntervalSince1970 - last > self.refreshInterval
            if list == nil || stale { self.fetchAndCompile() }
        }
    }

    /// WebView 生成時に登録。ルールが用意済みなら即適用。
    func register(_ webView: WKWebView) {
        if let ruleList { webView.configuration.userContentController.add(ruleList) }
        registered.append(WeakWeb(webView))
    }

    private func apply(_ list: WKContentRuleList, reload: Bool) {
        ruleList = list
        for w in registered {
            guard let wv = w.wv else { continue }
            wv.configuration.userContentController.add(list)
            if reload { wv.reload() }
        }
    }

    private func fetchAndCompile() {
        URLSession.shared.dataTask(with: listURL) { [weak self] data, _, _ in
            guard let self, let data, let text = String(data: data, encoding: .utf8) else { return }
            let json = Self.convert(text)          // 重い変換はバックグラウンドで
            guard json != "[]" else { return }
            // WKContentRuleListStore はメインスレッドから扱う
            DispatchQueue.main.async {
                guard let store = WKContentRuleListStore.default() else { return }
                store.compileContentRuleList(forIdentifier: self.identifier, encodedContentRuleList: json) { list, _ in
                    guard let list else { return }
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: self.lastFetchKey)
                    self.apply(list, reload: true)
                }
            }
        }.resume()
    }

    /// EasyList テキストから、広告ドメインの block 規則の JSON を生成。
    /// 確実に有効な規則（url-filter は「エスケープ済みドメイン」の部分一致）だけを作る。
    static func convert(_ text: String, limit: Int = 50000) -> String {
        var rules: [[String: Any]] = []
        for raw in text.split(separator: "\n") {
            if rules.count >= limit { break }
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("||") else { continue }          // ドメインブロック規則だけ対象
            let body = line.dropFirst(2)
            guard let caret = body.firstIndex(of: "^") else { continue }
            let domain = String(body[..<caret])                   // ^ の前＝ドメイン（オプションは無視）
            guard domain.count >= 3, domain.contains("."),
                  domain.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") })
            else { continue }
            let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
            rules.append(["trigger": ["url-filter": escaped], "action": ["type": "block"]])
        }
        let data = (try? JSONSerialization.data(withJSONObject: rules)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
