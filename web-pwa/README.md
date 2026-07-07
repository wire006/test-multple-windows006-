# 案B: HTML 2ペイン（iframe）を全画面 PWA として使う

Xcode も Apple Developer 登録も不要。**数分で試せる**最速の方法です。

## 使い方

1. `index.html` を iPhone の Safari で開く。
   - 手軽な確認方法: このリポジトリを GitHub Pages で公開する、
     iCloud Drive / メール等で `index.html` を送って Safari で開く、
     または任意の静的ホスティング（Netlify 等）に置く。
2. 上部の URL 欄に、上パネルに表示したいアドレスを入れて「開く」。
   下パネルも同様。入力した URL は端末に保存され、次回も復元されます。
3. 仕切り（中央のグレーのバー）を上下にドラッグすると分割比を変えられます。
4. 共有ボタン → **「ホーム画面に追加」** すると、ブラウザ UI のない
   全画面アプリのように起動できます（`apple-mobile-web-app-capable` 指定済み）。

## 重要な制約：埋め込みできないサイトがある

多くの主要サイトは `X-Frame-Options: DENY` や CSP `frame-ancestors` により
**iframe への埋め込みを禁止**しています。

| サイト例 | この方式で表示 |
|----------|----------------|
| YouTube（`youtube.com/embed/動画ID`） | ✅ 可 |
| OpenStreetMap の埋め込み | ✅ 可 |
| 自分でホストする Web アプリ / 社内ツール | ✅ 可（設定次第） |
| X (Twitter) / Gmail / Google 検索 / Instagram 等 | ❌ 不可（埋め込み拒否） |

→ 埋め込み拒否サイトを 2 分割で常用したい場合は、
本物のブラウザエンジンで開ける **案A（`ios-native`）** を使ってください。

## 仕組みのポイント

- `100dvh` + `env(safe-area-inset-*)` で iPhone 13 のノッチ／ホームインジケータを回避。
- 入力欄のフォントは 16px（未満だと iOS が自動ズームしてしまうため）。
- 仕切りは Pointer Events + `setPointerCapture` でドラッグ、
  ドラッグ中は iframe の `pointer-events` を切ってイベント取りこぼしを防止。
