# 案A: ネイティブ2分割アプリ（実機用・2用途対応）

1つのアプリで、上部のセグメントを切り替えて2つの用途に対応します。

| モード | 上ペイン | 下ペイン | ログイン問題 |
|--------|----------|----------|--------------|
| **Web (Claude/Docs)** | Claude (claude.ai) | Google ドキュメント | あり（下記） |
| **ファイル (MD/PDF)** | Markdown ファイル | PDF ファイル | **なし（最も確実）** |

## ファイル構成

| ファイル | 役割 |
|----------|------|
| `SplitViewApp.swift` | アプリ本体（`@main`）・モード切替・上下分割の共通部品 |
| `WebSplit.swift` | 用途1: Claude + Google ドキュメント（WKWebView） |
| `DocsSplit.swift` | 用途2: MD + PDF（Files から選択、PDFKit 表示） |
| `MarkdownRenderer.swift` | 依存なしの簡易 Markdown → HTML 変換 |

## セットアップ手順（Xcode / 実機のみ）

1. Xcode で **File → New → Project → iOS → App**（Interface: **SwiftUI**）。
2. 生成された `〇〇App.swift`（`@main` 付き）を**削除**し、
   この `ios-native/` 内の **4つの .swift ファイルすべて**をプロジェクトに追加。
   （`@main` は `SplitViewApp.swift` の 1 箇所だけになるようにする）
3. iPhone 13 を接続 → Signing で自分の Apple ID チームを選択 → **Run**。
   - 無料 Apple ID: 実機で動くが **7日で失効**（再ビルドで再署名）。
   - Apple Developer Program（年 $99）: 失効なし。
4. 追加の Info.plist 設定は不要（ユーザーが選んだファイルへのアクセスは
   ファイル選択画面が権限を付与するため）。

---

## 用途1（Claude + Google ドキュメント）のログインについて — 要注意

**Google は「埋め込みブラウザ(WKWebView)からの Google ログイン」を既定でブロック**します
（`disallowed_useragent` / 「このブラウザまたはアプリは安全でない可能性があります」）。

- **Claude 側**: Google を使わず **メールアドレス＋確認コード**でログインすれば WKWebView でも通ります。→ 実質問題なし。
- **Google ドキュメント側**: Google ログインが必須。本サンプルでは `WebView.safariUA` で
  **UA を Safari に偽装**してブロックを回避しています。実務上はこれで通ることが多いですが:
  - Google の規約上はグレー（**実機・個人利用のみ**という前提での割り切り）。
  - iOS 更新で UA 文字列の数字更新が必要になる場合あり（`WebSplit.swift` の `safariUA`）。
  - 一度ログインすれば Cookie は永続化され、次回起動時も維持されます。
- どうしても Google の制限を避けたい場合、Google ドキュメントの内容を
  **PDF/MD として書き出して「ファイル」モードで開く**のが最も確実です。

> 補足: `SFSafariViewController` は本物の Safari で Google ログインも通りますが、
> **全画面モーダル専用で分割表示に使えない**ため、分割には WKWebView が必須です。

---

## 用途2（MD + PDF）について — 最も確実

- 「選択」ボタンで **Files アプリ**から MD / PDF を選ぶ（`.fileImporter`）。
- **PDF は PDFKit**（`PDFView`）でネイティブ表示、**MD は整形して表示**。
- 選んだファイルは**セキュリティスコープ付きブックマーク**で保存し、
  次回起動時に自動復元。
- ローカルファイルのみなので Web ログインの問題は一切なし。

### Markdown レンダリングの範囲

`MarkdownRenderer.swift` は依存ライブラリなしの簡易実装で、
**見出し / 箇条書き / 番号付きリスト / 太字・斜体・インラインコード / リンク /
コードフェンス(```) / 引用 / 水平線 / 段落**をカバーします
（HTML はエスケープ済みで安全）。表・脚注・ネスト等の完全な CommonMark が必要なら、
`apple/swift-markdown`（SwiftPM）や `marked.js` に差し替えてください。

---

## 発展（必要に応じて）

- 分割比の記憶（`@AppStorage`）、左右分割/入れ替え、ペイン全画面トグル。
- Web ペインに 戻る/進む/再読込 ボタン。
- ファイルモードで、MD の代わりに任意テキストや複数タブ対応。
