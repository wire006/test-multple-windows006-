# 案A: ネイティブ2分割アプリ（実機用・3モード）

1つのアプリで、上部のセグメントを切り替えて3つのモードを使えます。

| モード | 内容 | ログイン問題 |
|--------|------|--------------|
| **テキスト×2**（起動時の既定） | Files の md / txt を2つ分割表示。ペイン幅にリフロー、文字サイズ −/＋（保存） | なし |
| **PDF×2** | Files に保存した PDF を2つ分割表示（本文幅に自動フィット・縦連続スクロール） | なし |
| **分割ブラウザ** | 任意の2サイトを分割表示（既定: Claude / Google ドキュメント） | あり（下記） |

すべて共通の上下分割 `VSplit`（上ペインを一番上に固定・仕切りドラッグで高さ可変）を使用。

> 📖 **コードの仕組みを初心者向けに一から解説した文書**があります → [`CODE_GUIDE.md`](CODE_GUIDE.md)
> （Swift / SwiftUI とは何かから、各ファイルの読み解き方まで。勉強用にどうぞ）

## ファイル構成

| ファイル | 役割 |
|----------|------|
| `SplitViewApp.swift` | アプリ本体（`@main`）・モード切替・共通2分割コンテナ `VSplit` |
| `TextSplit.swift` | テキスト×2（md/txt を HTML リフロー表示・文字サイズ調整・簡易Markdown・スクロール同期） |
| `DocsSplit.swift` | PDF × 2（本文幅にクロップして幅フィット・縦連続スクロール） |
| `WebSplit.swift` | 分割ブラウザ（アドレスバー・戻る/進む・入れ替え・文字サイズ） |
| `AdBlock.swift` | 分割ブラウザの広告ブロック（WKContentRuleList・AdGuard日本語/ベース＋組み込み規則） |
| `CODE_GUIDE.md` | 初心者向けコード解説（このアプリの仕組みを一から説明） |
| `project.yml` | XcodeGen 用。`.xcodeproj` を生成するための定義（ターミナルビルド用） |
| `build.sh` / `rebuild.command` | シミュレータへビルド＆起動 / 実機へ再ビルド（自動 pull・署名検出） |

## セットアップ手順A: ターミナルだけで（ダウンロード〜ビルド）

ソースは loose な .swift だけなので、`xcodebuild` の前に **XcodeGen**（`project.yml`）で
`.xcodeproj` を生成します。

**前提（Mac mini + Xcode）**
- Xcode を一度起動してライセンス同意（または `sudo xcodebuild -license accept`）。
- `sudo xcode-select -s /Applications/Xcode.app`
- Homebrew（未導入なら https://brew.sh の1行）と XcodeGen: `brew install xcodegen`

**1. ダウンロード（このブランチを取得）**
```sh
git clone -b claude/iphone-split-screen-approaches-df90pl \
  https://github.com/wire006/test-multple-windows006-.git
cd test-multple-windows006-/ios-native
```

**2. シミュレータでビルド＆起動（署名不要・最短）**
```sh
./build.sh
```
内部で `xcodegen generate` → `xcodebuild`(iphonesimulator) → `simctl install/launch` を実行します。
手動で行う場合:
```sh
xcodegen generate
xcodebuild -project SplitView.xcodeproj -scheme SplitView \
  -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath build build
```

**3. 実機（iPhone 13）へインストール（署名が必要）**
- 初回のみ署名の準備: 生成された `SplitView.xcodeproj` を一度 Xcode で開き、
  Signing & Capabilities で自分の Apple ID チームと「Automatically manage signing」を選択
  （＝無料 Apple ID の provisioning を作成。以後はターミナルだけで可）。
  10桁のチームIDが分かっていれば GUI を使わず次でも可:
```sh
xcodebuild -project SplitView.xcodeproj -scheme SplitView \
  -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=あなたの10桁ID \
  -derivedDataPath build build
```
- iPhone を接続し、UDID を確認してインストール・起動（Xcode 15+ の devicectl）:
```sh
xcrun devicectl list devices
xcrun devicectl device install app --device <UDID> \
  build/Build/Products/Debug-iphoneos/SplitView.app
xcrun devicectl device process launch --device <UDID> com.wire006.splitview
```
- 無料 Apple ID は **7日で失効**（再ビルド／再インストールで更新）。初回起動時は
  iPhone の「設定 → 一般 → VPN とデバイス管理」で自分の開発者証明書を信頼。

> iOS 17 以前の実機では `devicectl` の代わりに `ios-deploy`（`brew install ios-deploy`）:
> `ios-deploy --bundle build/Build/Products/Debug-iphoneos/SplitView.app`

**再ビルドのショートカット**: `rebuild.command` は、接続中の iPhone を自動検出して
「生成→ビルド→インストール→起動」を一発で行います（無料 Apple ID の7日失効時の入れ直しに便利）。
デスクトップに置いてダブルクリックで実行できます:
```sh
cp rebuild.command ~/Desktop/ && chmod +x ~/Desktop/rebuild.command
```

## セットアップ手順B: Xcode GUI の場合

1. `xcodegen generate` で `SplitView.xcodeproj` を作って開く
   （または空の SwiftUI App を新規作成し `*.swift` 3ファイルを追加。`@main` は1つに）。
2. iPhone 13 を接続 → Signing でチーム選択 → **Run**。

---

## 「分割ブラウザ」モードでできること

各ペインは `WKWebView`（Safari と同じ WebKit エンジン）です。既定は Claude（上）と
Google ドキュメント（下）。すべての操作は1段のツールバーに収めています。

- **アドレスバー**（各ペイン独立） … URL を入力、または URL でない文字列は **Google 検索**。
- **戻る / 進む / 更新（読み込み中は停止）** ボタン＋**読み込みプログレスバー**。
- **ペインの入れ替え**（上ペインのツールバー左のアイコン）… 上下の URL をスワップ。
- **文字サイズ − / ＋**（各ペイン独立・保存） … **文字だけ**拡大／縮小し、**横幅は維持**
  （折り返して縦に伸びるので横スクロールが出ない）。
- **広告ブロック**（後述）… 主要な広告の通信を遮断し、残った広告枠も CSS で非表示。
- **分割比率の変更** … 中央のグレーの仕切りバーを上下にドラッグ（比率は保存）。
- **状態の永続化** … 各ペインの最後に開いた URL と分割比率を保存し、次回起動時に復元。
- **ログイン Cookie の保持**、端スワイプの戻る/進む、動画のインライン再生、
  `target="_blank"` リンクの同一ペイン内オープンにも対応。

> 実装メモ: モード切替（テキスト×2 / PDF×2 / 分割ブラウザ）でも `WKWebView` を
> 作り直さないよう、3モードは常時マウントしたまま表示だけ切り替えています
> （＝ページのログイン状態やスクロール位置がタブ切替で消えない）。

### 広告ブロックについて

Safari のコンテンツブロッカー（AdGuard などの Safari 拡張）は**サードパーティアプリの
WKWebView には効きません**。そこでアプリ内で `WKContentRuleList` を組み立てて適用します。

- **フィルタ**: 起動時に **AdGuard 日本語**・**AdGuard ベース**を取得（AdGuard 公式の
  GitHub 配布リポジトリから）。日本のサイト（まとめ／掲示板など）の広告に効くよう
  **AdGuard 日本語を最優先**で読み込み。
- **組み込み規則**: 取得に失敗しても効くよう、実測で確認した広告枠（`animanch` の
  `.abox` / `.AMvertical` / 780×485 の広告 `div` など）＋一般的な広告コンテナ
  （`.adsbygoogle` など）を**アプリに内蔵**。これらは常に最優先で適用されます。
- **2段構え**:
  1. *ネットワークブロック* … `||domain^` 規則から広告ドメインへの通信を遮断。
  2. *要素非表示 (cosmetic)* … `##selector` 規則で残った広告枠を CSS で非表示
     （ドメイン限定・属性セレクタ `div[style="…"]` にも対応）。
- **キャッシュ**: コンパイル結果は端末にキャッシュ。**次回以降は即適用**、更新は**約1週間に1回**だけ再取得。
- **初回起動**は取得・コンパイルに数秒かかり（リストが大きいため）、完了後に自動で一度だけ
  再読み込みして反映します。組み込み規則ぶんはそれ以前から効きます。
- オン/オフのトグルはありません（常時オン）。実装は `AdBlock.swift`。

> 割り切り: `:has()` `:upward()` などの拡張セレクタや `@@` 例外、スクリプトレットは未対応
> （WKContentRuleList でコンパイル可能な素直な規則のみ）。要素非表示規則は複数チャンクに
> 分けてコンパイルし、1つの不正セレクタで全体が無効化されないようにしています。
> それでもごく稀に広告の空き枠が残る／逆に一部要素が消えることがあります。

### ログインについて — 要注意（Google）

**Google は「埋め込みブラウザ(WKWebView)からの Google ログイン」を既定でブロック**します
（`disallowed_useragent`）。

- **Claude 側**: Google を使わず **メールアドレス＋確認コード**でログインすれば通ります。
- **Google ドキュメント側**: `WebView.safariUA` で **UA を Safari に偽装**して回避しています。
  実務上はこれで通ることが多いですが、Google 規約上はグレー（**実機・個人利用向けの割り切り**）、
  iOS 更新で UA 文字列の数字更新が必要になる場合あり。
- どうしても避けたい場合は、Google ドキュメントを **PDF に書き出して「PDF×2」モードで開く**のが確実。

> `SFSafariViewController` は Google ログインも通りますが、全画面モーダル専用で
> 分割表示に使えないため、分割には WKWebView が必須です。

---

## 「PDF×2」モードについて — 最も確実

- 上下それぞれの「選択」ボタンで **Files アプリ**から PDF を選ぶ（`.fileImporter`）。
- **PDFKit**（`PDFView`）でネイティブ表示。ペインごとに独立してスクロール/ズーム。
- 選んだファイルは**セキュリティスコープ付きブックマーク**で保存し、次回起動時に自動復元。
- ローカルファイルのみなので Web ログインの問題は一切なし。

> iCloud Drive 上の PDF は未ダウンロードだと開けない場合があります
> （Files で一度ダウンロード済みにしておくと確実）。

---

## 発展（必要に応じて）

- タブ（各ペインに複数ページ）、履歴一覧、ページ内検索。
- PDF×2 モードにも上下/左右切替・全画面を適用（`TwoPaneSplit` はそのまま流用可能）。
- 2つの PDF のスクロール同期。
- Web モード不要なら `RootView` から Picker と `WebSplit()` を外し `DocsSplit()` を直接表示すれば PDF 専用アプリになります（`WebSplit.swift` も削除可）。
