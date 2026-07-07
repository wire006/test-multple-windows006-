# 案A: WKWebView 2分割のネイティブアプリ（雛形）

自作アプリの中に `WKWebView` を上下 2 つ積み、別々の Web サービスを同時表示します。
`web-pwa`（iframe 版）と違い **本物のブラウザエンジン**なので、
X-Frame-Options で埋め込み拒否されるサイト（X / Gmail / Google 検索等）も直接開けます。

## セットアップ手順（Xcode）

1. Xcode で **File → New → Project → iOS → App** を選択。
   - Interface: **SwiftUI** / Language: **Swift**
2. 自動生成された `〇〇App.swift`（`@main` が付いたファイル）を削除するか中身を空にし、
   本ディレクトリの [`SplitWebView.swift`](SplitWebView.swift) をプロジェクトに追加。
   （このファイルが `@main struct SplitWebApp` を持っています）
3. iPhone 13 を USB 接続し、Signing で自分の Apple ID チームを選択して **Run**。

## 費用・署名について

- **無料の Apple ID**: 実機で動くが 7 日で失効 → 再ビルド（再署名）が必要。
- **Apple Developer Program（年 $99）**: 失効なし。TestFlight 配布や App Store 申請も可能。

## 実装のポイント

| 項目 | 対応 |
|------|------|
| リダイレクトによる再読み込みループ | `Coordinator.lastLoaded` で直近 URL を記録し、変化時のみ `load` |
| 枠内での動画再生 | `allowsInlineMediaPlayback = true` |
| 端スワイプで戻る/進む | `allowsBackForwardNavigationGestures = true` |
| 分割比の変更 | 仕切りへの `DragGesture` で上ペイン高さを更新（min/max でクランプ） |
| キーボードでレイアウトが崩れる | `.ignoresSafeArea(.keyboard)` |
| URL 入力の自動大文字化/補正 | `.textInputAutocapitalization(.never)` + `.autocorrectionDisabled()` |

## ここから実用化する際の発展

- 各ペインの URL・分割比を `@AppStorage` で永続化。
- ペイン毎に「戻る/進む/再読込」ボタンや、レイアウト（上下比）のプリセット保存。
- 左右分割・入れ替えボタン、ペインの全画面トグル。
- ログインを跨ぎたいサイト向けに `WKWebsiteDataStore`（Cookie 保持）を明示管理。
- ネイティブ機能が欲しい部分は WebView をやめ、自作 SwiftUI ビューに置換（案C）。

## 制約（再掲）

- **Web 版が存在するサービス限定**。ネイティブ専用アプリは取り込めない。
- Netflix 等の DRM 動画や、`WKWebView` を弾く一部サイトは再生/表示不可の場合あり。
- あくまで 1 アプリ内の 2 ペイン。CPU / メモリは 1 アプリ分を共有。
