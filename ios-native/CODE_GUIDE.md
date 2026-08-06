# 「2分割ビューア」コード解説 — 初心者向け

このアプリ（`ios-native/`）が **どういう仕組みで動いているのか** を、
プログラミングやアプリ開発がはじめての人にも分かるように、ゼロから説明します。

> このアプリは何？ … iPhone の画面を **上下2つ** に分けて、
> 「テキスト×2」「PDF×2」「分割ブラウザ」の3モードを切り替えて使えるビューアです。

読み方の目安：
- **1〜3章**：予備知識（Swift / SwiftUI とは、画面の考え方）。まずここを読むと後がラクです。
- **4〜9章**：実際のコードを1ファイルずつ、やさしく解説。
- **10章**：用語集（分からない言葉が出たら逆引き）。

---

## もくじ

1. このアプリでできること
2. 予備知識① Swift と SwiftUI
3. 予備知識② 「状態が変わると画面が変わる」
4. 全体の地図（ファイル構成）
5. アプリの入り口 — `SplitViewApp.swift`
6. 共通部品 — 上下2分割 `VSplit`
7. モード① テキスト×2 — `TextSplit.swift`
8. モード② PDF×2 — `DocsSplit.swift`
9. モード③ 分割ブラウザ — `WebSplit.swift`
10. 広告ブロック — `AdBlock.swift`
11. 用語集（逆引き）

（各章は下に順番に並んでいます。番号で探してください。）

---

## 1. このアプリでできること

3つの「モード」があり、画面上部のタブ（セグメント）で切り替えます。
どのモードも **上下2分割** で、真ん中の灰色のバーをドラッグすると比率を変えられます。

```
┌──────────────────────────────┐
│  [テキスト×2] [ PDF×2 ] [分割ブラウザ] │ ← モード切替タブ
├──────────────────────────────┤
│                              │
│         上のペイン            │ ← ペイン = 分割された一つの領域
│                              │
│━━━━━━━━ ⬤ ━━━━━━━━━━│ ← ドラッグで上下比率を変える仕切り
│                              │
│         下のペイン            │
│                              │
└──────────────────────────────┘
```

| モード | 何を表示する？ | 主な機能 |
|---|---|---|
| **テキスト×2** | Files アプリの `.md` / `.txt` を2つ | 文字サイズ ±、スクロール位置同期(🔗) |
| **PDF×2** | Files アプリの PDF を2つ | 本文幅に合わせて拡大、連続スクロール |
| **分割ブラウザ** | 任意の2つのWebサイトをSafari同等で | アドレスバー、戻る/進む、文字サイズ、広告ブロック |

すべてに共通する「こだわり」：
- **設定を保存する**：分割比率・文字サイズ・最後に開いたファイルやURL・スクロール位置を覚えていて、次回起動時に続きから使えます。
- **実機・個人利用向け**：App Store には出さず、自分の iPhone に入れて使う前提です。

---

## 2. 予備知識① Swift と SwiftUI

### Swift（スウィフト）とは
Apple が作った **プログラミング言語** です。iPhone / Mac アプリはこの言語で書きます。
文章を書くのに日本語や英語があるように、iPhone アプリを書くための言葉が Swift だ、と思ってください。

### SwiftUI（スウィフトユーアイ）とは
Swift で **画面（UI = ユーザーインターフェース）** を作るための道具（フレームワーク）です。
SwiftUI の最大の特徴は **宣言的（せんげんてき）** であること。これはとても大事な考え方です。

- **昔ながらのやり方（命令的）**：「ボタンを作れ」「ここに置け」「色を変えろ」と、手順を一つずつ命令する。
- **SwiftUI のやり方（宣言的）**：「画面は “こういう見た目” であるべき」と **結果だけを書く**。
  どう描くかは SwiftUI が勝手にやってくれる。

たとえるなら、命令的は「材料を切って、炒めて、盛り付けて…」と料理の手順を書くこと。
宣言的は「完成形はカレーライスです」と写真を見せること。SwiftUI では **完成形の写真** を書きます。

```swift
// 「縦に並べて、上に見出し、下に本文」という "完成形" を書くだけ
VStack {
    Text("タイトル").font(.headline)   // 見出し
    Text("本文です")                    // 本文
}
```

`VStack`（Vertical Stack＝縦積み）の中に `Text` を2つ書くと、上下に並びます。
「どうやって並べるか」は書きません。**結果を書けば SwiftUI が描いてくれる** ── これが宣言的UIです。

このアプリに出てくる SwiftUI の部品（**View** と呼びます）：
- `VStack` / `HStack` / `ZStack`：縦積み / 横並び / 重ね（奥行き方向）
- `Text`：文字　`Button`：ボタン　`Picker`：選択タブ　`TextField`：入力欄
- `GeometryReader`：画面の大きさを測る特別な部品

> **View（ビュー）** ＝ 画面を作るブロック。レゴブロックのように、小さな View を組み合わせて画面を作ります。

---

## 3. 予備知識② 「状態が変わると画面が変わる」

SwiftUI を理解する鍵は、この一文です：

> **データ（状態）が変わると、SwiftUI が自動で画面を描き直す。**

「状態（state / ステート）」とは、アプリが覚えている値のこと。
たとえば「今どのモードを開いているか」「文字サイズはいくつか」などです。

表計算ソフト（Excel）を思い出してください。あるセルの数字を変えると、
それを使った合計セルが **自動で計算し直される** ── SwiftUI も同じで、
状態を変えると、その状態を使っている画面部分が **自動で更新** されます。

```
 あなたが操作         状態が変わる          画面が自動で更新
────────────      ─────────────      ──────────────
「＋」を押す   ─→   fontSize 17→18   ─→   文字が大きく再表示
タブを押す     ─→   mode .text→.web  ─→   ブラウザ画面に切替
```

この「状態」を SwiftUI に教えるための **目印（マーク）** が、`@` で始まる記号です。
これを **プロパティラッパー** と呼びます（難しい名前ですが「特別な目印」くらいの理解でOK）。

このアプリで使う主な目印：

| 目印 | 意味 | たとえ |
|---|---|---|
| `@State` | この View だけが持つ小さな状態 | メモ用の付箋 |
| `@StateObject` | 複数の値をまとめて持つ「箱」を **新しく作って** 所有する | 自分専用の道具箱 |
| `@ObservedObject` | その「箱」を **借りて見る**（作りはしない） | 誰かの道具箱を覗く |
| `@AppStorage` | アプリを閉じても **消えない** 状態（自動で保存） | ノートに書いておく |
| `@Published` | 「箱」の中の値。変わると持ち主に通知 | 箱の中の変化を知らせるベル |

> ポイント：`@State` や `@AppStorage` の値を書き換えるだけで、画面は自動で追従します。
> 「画面を描き直せ」と命令するコードは、基本的に書きません。

これらを踏まえて、いよいよ実際のコードを読んでいきます。

---

## 4. 全体の地図（ファイル構成）

`ios-native/` にある Swift ファイルは5つ。役割はこう分かれています。

| ファイル | 役割 | ひとことで |
|---|---|---|
| `SplitViewApp.swift` | **入り口**。アプリ起動・モード切替・共通の分割部品 | 司令塔 |
| `TextSplit.swift` | テキスト×2モードの中身 | テキスト係 |
| `DocsSplit.swift` | PDF×2モードの中身 | PDF係 |
| `WebSplit.swift` | 分割ブラウザモードの中身 | ブラウザ係 |
| `AdBlock.swift` | 広告ブロックの仕組み | 用心棒 |

関係を図にすると：

```
              SplitViewApp（アプリ本体）
                     │
                RootView（タブで切替）
        ┌────────────┼────────────┐
    TextSplit     DocsSplit      WebSplit
   （テキスト）    （PDF）        （ブラウザ）
        │            │             │
        └──── みんな VSplit を使う ────┘   ← 上下2分割の共通部品
                                     │
                                  AdBlock（ブラウザに広告ブロックを適用）
```

`VSplit`（上下2分割の枠）は3モード共通の部品で、`SplitViewApp.swift` の中にあります。
「同じ仕組みは1回だけ書いて使い回す」というプログラミングの基本（**再利用**）の good な例です。

---

## 5. アプリの入り口 — SplitViewApp.swift

### 5-1. `@main` — ここから始まる

```swift
@main
struct SplitViewApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}
```

- `@main`：この目印が付いた場所が **アプリの開始地点**。iPhone はここから起動します（1アプリに1つだけ）。
- `App`：アプリ全体を表す型。`WindowGroup`（アプリの画面の入れ物）の中に、最初に見せる画面 `RootView()` を置いています。

つまり「起動したら `RootView` を表示してね」と宣言しているだけ。

### 5-2. `RootView` — モードの切り替え

```swift
struct RootView: View {
    enum Mode: Int, CaseIterable, Identifiable {
        case text, files, web    // 先頭 = 既定。テキストを最初に開く
        ...
    }
    @State private var mode: Mode = .text   // 今どのモードか（初期値は text）
```

- `enum Mode`：モードの種類を **決まった選択肢** として定義（`text` / `files` / `web` の3つ）。
  「enum（イーナム＝列挙型）」は “信号は 赤・青・黄 のどれか” のように、選択肢が限られる値を表すのに使います。
- `@State private var mode`：今のモードを覚える状態。ここを書き換えると画面が切り替わります。

画面の本体（`body`）：

```swift
var body: some View {
    VStack(spacing: 0) {
        Picker("表示", selection: $mode) {           // ① 上部の切替タブ
            ForEach(Mode.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)

        ZStack {                                     // ② 3モードを "重ねて" 置く
            TextSplit().opacity(mode == .text ? 1 : 0)
            DocsSplit().opacity(mode == .files ? 1 : 0)
            WebSplit().opacity(mode == .web ? 1 : 0)
        }
    }
    .onAppear { AdBlock.shared.start() }             // ③ 起動時に広告ブロック準備
}
```

読み解きポイント：

- **① `Picker` + `$mode`**：`$` は「この状態と双方向につなぐ」という意味（**バインディング**）。
  タブを押すと `mode` が変わり、`mode` が変わると選択も変わる、と双方向に連動します。
- **② `ZStack` で全部を重ねる**：普通なら「今のモードだけ表示」で良さそうですが、あえて
  **3モードすべてを常に存在させ**、`opacity`（不透明度：1で見える / 0で透明）で見せ隠しします。
  なぜ？ → タブを切り替えても **ブラウザのログイン状態やスクロール位置を消さないため**。
  もし切替のたびに作り直すと、毎回リセットされてしまいます。これは実用上とても大事な工夫です。
- **③ `.onAppear`**：この画面が現れた瞬間に1回だけ実行。ここで広告ブロックの読み込みを開始します。

### 5-3. `PaneBar` — ペイン上部の名前バー

各ペインの「テキスト（上）」のような見出し＋ファイル名＋「選択」ボタンを表示する小さな部品です。
PDF モードで使われます（テキスト/ブラウザは各モード内に自前のバーを持っています）。

---

## 6. 共通部品 — 上下2分割 VSplit

`VSplit` は3モードが共通で使う **「上下に分割して、仕切りをドラッグで動かせる枠」** です。
`SplitViewApp.swift` の中にあります。ここは少し難しいので、ゆっくり見ます。

### 6-1. 使う側から見ると

```swift
VSplit("web") {
    // 上に置きたいもの
} bottom: {
    // 下に置きたいもの
}
```

`"web"` は **保存用の名前（キー）**。モードごとに違う名前を渡すことで、分割比率をモード別に覚えます。

### 6-2. 中身の要点

```swift
struct VSplit<Top: View, Bottom: View>: View {
    @AppStorage private var topFraction: Double   // 上ペインの割合（0〜1）を保存
    private let dividerH: CGFloat = 16             // 仕切りの高さ

    var body: some View {
        GeometryReader { geo in                    // ① 画面の実寸を測る
            let usable = geo.size.height - dividerH
            let topH = usable * topFraction         // 上ペインの高さを割合から計算

            VStack(spacing: 0) {
                top.frame(height: topH)             // 上ペイン（計算した高さ）
                // ── 仕切りバー ──
                ZStack { Color(.systemGray5); Capsule()... }
                    .highPriorityGesture(           // ② ドラッグを検知
                        DragGesture(coordinateSpace: .named(space))
                            .onChanged { v in
                                topFraction = v.location.y / usable   // 指の位置→割合
                            }
                    )
                bottom.frame(maxHeight: .infinity)  // 下ペイン（残り全部）
            }
        }
    }
}
```

- **① `GeometryReader`**：画面（この枠）の **実際の大きさ** を教えてくれる特別な View。
  「画面の高さ」が分からないと「上を60%」の高さを計算できないので、まず実寸を測ります。
- **`topFraction`（例：0.5）× 画面の高さ** ＝ 上ペインの高さ。これで割合ベースの分割ができます。
- **② `DragGesture`（ドラッグ操作）**：仕切りを指で動かすと `onChanged` が何度も呼ばれ、
  **指の位置 ÷ 全体の高さ** を新しい割合として `topFraction` に入れます。
  `topFraction` は `@AppStorage` なので、動かすたびに保存され、次回も同じ比率で開きます。

> **豆知識（過去のバグ）**：以前この仕切りが「上下に暴れる（発振する）」不具合がありました。
> 原因は、動いている仕切り自身を基準に位置を測っていたため（自分が動く→測り直す→また動く…の無限ループ）。
> `.named(space)` で **固定された座標系** を基準に「指の絶対位置」で測るようにして解決しました。
> ── コードは “何を基準に測るか” で結果が変わる、という良い教訓です。

`<Top: View, Bottom: View>` の部分は **ジェネリクス**（総称型）といって、
「上と下には “どんな View でも” 入れられる」という意味。だから3モードで使い回せます。

---

## 7. モード① テキスト×2 — TextSplit.swift

Files アプリに保存した `.md` / `.txt` を2つ並べて読むモードです。
テキストは **アプリ側で HTML に組版** して `WKWebView`（＝Safari と同じ表示エンジン）で表示します。
こうすると、文字サイズを変えても **幅に合わせて自動改行（リフロー）** され、見切れません。

### 7-1. 登場人物

| 名前 | 役割 |
|---|---|
| `TextSplit` | このモードの土台。`VSplit` で上下に `TextPane` を2つ置く |
| `TextPane` | 1ペイン分のUI（ツールバー＋本文表示） |
| `TextHTMLView` | HTML を実際に表示する部分（`WKWebView` を SwiftUI で使う橋渡し） |
| `TextRenderer` / `MarkdownMini` | テキストや Markdown を HTML 文字列に変換する |
| `ScrollSync` | 2ペインのスクロール位置(%)を同期する係 |

### 7-2. テキスト → HTML の変換（TextRenderer / MarkdownMini）

`.txt` はそのまま、`.md`（Markdown）は簡易変換して HTML にします。
`MarkdownMini` は **外部ライブラリを使わず自前** で、見出し `#`、リスト `-`、
太字 `**`、リンク `[..](..)`、コード \`..\` などを HTML に置き換えます。

```swift
// 例：見出しの判定（先頭の # の数を数えて <h1>〜<h6> にする）
static func heading(_ s: String) -> (Int, String)? {
    var n = 0
    for c in s { if c == "#" { n += 1 } else { break } }   // # を数える
    guard (1...6).contains(n) else { return nil }
    ...
}
```

作られる HTML には、文字サイズを **CSS変数 `--fs`** で持たせているのがミソです：

```swift
:root { --fs: 17px; }           // ← ここを書き換えるだけで全体の文字サイズが変わる
body { font: var(--fs)/1.75 ...; }
```

### 7-3. 文字サイズ変更が「スクロールを保ったまま」効く理由

「＋」を押したとき、HTML を作り直すと表示が先頭に戻ってしまいます。そこで工夫があります：

```swift
func updateUIView(_ wv: WKWebView, context: Context) {
    if c.lastHTML != html {                    // 本文が変わったときだけ全読み込み
        wv.loadHTMLString(html, baseURL: nil)
    } else if c.lastFont != fontSize {         // 文字サイズだけ変わったときは…
        wv.evaluateJavaScript(                 // JavaScript で CSS変数だけ書き換える
            "document.documentElement.style.setProperty('--fs','\(Int(fontSize))px')")
    }
}
```

- 本文が同じで **文字サイズだけ** 変わったときは、ページを読み込み直さず、
  **JavaScript で `--fs` の値だけ更新**。だから **スクロール位置がずれません**。
- これは「必要最小限のことだけやる」という、動作を軽く・自然にするための定石です。

### 7-4. スクロール位置の保存と復元

`Coordinator`（後述）が、アプリが裏に回る瞬間（`willResignActiveNotification`）に
スクロール位置を **割合（0〜1）** で保存し、次回読み込み完了時にその割合まで戻します。

```swift
func save() {   // 今の位置を「全体の何割か」で保存
    let f = sv.contentOffset.y / (sv.contentSize.height - sv.bounds.height)
    UserDefaults.standard.set(f, forKey: scrollKey)
}
func webView(_ webView: WKWebView, didFinish ...) {   // 読み込み完了→その割合へ
    let f = UserDefaults.standard.double(forKey: scrollKey)
    webView.evaluateJavaScript("window.scrollTo(0,(...scrollHeight-innerHeight)*\(f))")
}
```

**なぜピクセルでなく割合？** → 文字サイズを変えると全体の高さが変わるため。
割合で覚えておけば、高さが変わっても「だいたい同じ場所」に戻れます。

### 7-5. スクロール同期（🔗）— ScrollSync

`ScrollSync` は「片方をスクロールしたら、もう片方も同じ **進捗率(%)** に合わせる」係です。

```swift
func scrolled(_ source: WKWebView) {
    guard enabled else { return }                         // 🔗 がオフなら何もしない
    guard sv.isDragging || sv.isDecelerating else { return } // ★ユーザーが触っている側だけ
    ...
    let f = sv.contentOffset.y / (contentSize - bounds)   // 動いた側の進捗率
    other.setContentOffset(y: f * 相手の最大),  animated: false  // 相手を同じ率へ
}
```

★の行がとても重要です。**「今ユーザーが指で触っている側」だけを基準** にします。
これがないと、A→B に合わせる → B が動いたことで B→A に合わせる → …と
**お互いに押し合う無限ループ** になってしまいます。「どちらが主導か」を見極めるための条件です。

---

## 8. モード② PDF×2 — DocsSplit.swift

Files アプリの PDF を2つ並べて読むモード。表示には Apple 純正の **PDFKit** を使います。
ローカルのファイルを開くだけなので、Webのようなログイン問題がなく **最も確実** なモードです。

### 8-1. ファイルの参照を保存する — BookmarkSlot と「セキュリティスコープ付きブックマーク」

iPhone のアプリは、勝手に他の場所のファイルを読めません（安全のため）。
ユーザーが「選択」で選んだファイルには一時的な許可が出ますが、それは **次回起動時には切れます**。

そこで **「セキュリティスコープ付きブックマーク」** という仕組みを使います。
これは「このファイルを後でまた開いていいですよ」という **許可証つきのしおり** のようなもの。

```swift
func set(_ picked: URL) {
    let accessing = picked.startAccessingSecurityScopedResource()  // 許可を開始
    defer { if accessing { picked.stopAccessingSecurityScopedResource() } } // 終わったら閉じる
    let data = try picked.bookmarkData()                 // "しおり" を作る
    UserDefaults.standard.set(data, forKey: key)         // 保存
}
```

次回はこの `data`（しおり）から `URL(resolvingBookmarkData:)` でファイルを復元します。
だから **次回起動時も同じPDFが自動で開きます**。

### 8-2. 本文幅にピッタリ合わせる — WidthFitPDFView

PDF は余白が広いものが多く、ページ幅に合わせると本文が細く読みづらくなります。
そこで `WidthFitPDFView` は各ページの **本文（テキスト）の左右端を検出してその範囲に切り出し（クロップ）**、
その幅を画面幅に合わせます。結果、本文が画面いっぱいに大きく表示されます。

```swift
// ページ全体からテキストを選択して、その左右端(minX/maxX)を調べる
let sel = doc.selection(from: page, at: 左上, to: page, at: 右下)
let b = sel.bounds(for: page)     // テキストが占める矩形
minX = min(minX, b.minX); maxX = max(maxX, b.maxX)
...
page.setBounds(切り出した範囲, for: .cropBox)   // 表示範囲を本文だけに絞る
```

- `displayMode = .singlePageContinuous`（連続縦スクロール）で、全ページを縦にスルスル読めます。
- スクロール位置は `PDFDestination`（ページ番号＋位置）で保存・復元します。

---

## 9. モード③ 分割ブラウザ — WebSplit.swift

任意の2つのWebサイトを上下に開ける、簡易ブラウザです。各ペインは `WKWebView`（Safari と同じ WebKit）。
既定は Claude（上）と Google ドキュメント（下）。

### 9-1. 登場人物

| 名前 | 役割 |
|---|---|
| `WebSplit` | 土台。`VSplit` で `BrowserPaneView` を上下に置く |
| `BrowserPaneView` | 1ペインのUI（ツールバー＋WebView＋読み込みバー） |
| `BrowserPane` | そのペインの **状態**（URL・戻れるか等）を持つ箱 |
| `WebView` | `WKWebView` を SwiftUI で使う橋渡し |

### 9-2. 状態の箱 — BrowserPane（ObservableObject）

```swift
final class BrowserPane: ObservableObject {
    @Published var address: String        // アドレスバーの文字
    @Published var canGoBack = false      // 戻れるか（ボタンの有効/無効に使う）
    @Published var isLoading = false      // 読み込み中か
    ...
}
```

`@Published` の付いた値が変わると、この箱を見ている画面（`@ObservedObject var pane`）が
**自動で更新** されます。たとえば `isLoading` が変われば、更新ボタンの絵が「✕（停止）」に切り替わります。

URL欄の賢い判定（`normalize`）：

```swift
if 文字が http:// か https:// で始まる  →  そのままURL
else if "." を含み空白がない（例 apple.com）  →  https:// を足してURL
else（例：ただの単語）  →  Google 検索にする
```

だから **URL欄に単語を入れると Google 検索** になります。

### 9-3. UIKit の部品を SwiftUI で使う — UIViewRepresentable と Coordinator

ここがこのアプリ全体で **いちばん大切な橋渡しの概念** です。

`WKWebView`（ブラウザ）や `PDFView`（PDF）は、SwiftUI より前からある **UIKit** という
古い世代の道具の部品です。SwiftUI で直接は置けないので、**変換アダプター** を作ります。
それが `UIViewRepresentable` です。

```swift
struct WebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {   // ① 部品を1回だけ作る
        let webView = WKWebView(...)
        webView.navigationDelegate = context.coordinator
        AdBlock.shared.register(webView)               // 広告ブロックを適用
        return webView
    }
    func updateUIView(_ webView: WKWebView, ...) {     // ② 状態が変わるたび呼ばれる
        // 文字サイズが変わっていれば反映する、など
    }
    func makeCoordinator() -> Coordinator { ... }      // ③ 連絡係を作る
}
```

- **`makeUIView`**：UIKit部品を **最初に1回だけ** 作る。
- **`updateUIView`**：状態（文字サイズなど）が変わるたびに呼ばれ、部品に反映する。
- **`Coordinator`（コーディネーター＝連絡係）**：
  UIKit部品からの「ページ読み込みが終わった」「URLが変わった」などの **通知を受け取る係**。
  SwiftUI（宣言的）と UIKit（命令的・通知が来る）を **つなぐ通訳** の役割です。

`Coordinator` は2つの方法で WebView を監視します：
- **KVO（`observe`）**：`estimatedProgress`（進捗）や `url`、`canGoBack` の変化を見張り、`BrowserPane` に書き戻す。
- **デリゲート（`didFinish`）**：ページ読み込み完了などの節目に呼ばれるメソッド。

### 9-4. Google ログインのための小細工（UA偽装）

Google は「埋め込みブラウザ（WKWebView）からのログイン」を既定で拒否します。
そこで **User-Agent（自分が何のブラウザかを名乗る文字列）を Safari のものに偽装** して回避しています。

```swift
webView.customUserAgent = "Mozilla/5.0 (iPhone; ...) ... Safari/604.1"
```

> これは規約上グレーな “実機・個人利用向けの割り切り” です（README にも注意書きあり）。

---

## 10. 広告ブロック — AdBlock.swift

分割ブラウザで広告を消すための仕組み。少し高度ですが、考え方はシンプルです。

### 10-1. なぜアプリ内で作る必要がある？

Safari の広告ブロック拡張（AdGuard など）は、**Safari 本体にしか効かず**、
このアプリのような **他アプリの WKWebView には効きません**。
そこで **アプリ自身がブロックのルールを読み込ませる** 必要があります。それが `WKContentRuleList` です。

### 10-2. 2段構えのブロック

```
① ネットワークブロック … 広告ドメインへの "通信そのもの" を遮断
     例：doubleclick.net への読み込みを止める
② 要素非表示(cosmetic) … 残った広告の "枠" を CSS で隠す
     例：animanch の .abox という広告枠を display:none にする
```

ルールは **アドブロック構文のフィルタ**（AdGuard 日本語 / ベース）を起動時にダウンロードし、
`convert()` が `WKContentRuleList` 用の **JSON** に変換します。
さらに、確実に効かせたい規則（animanch の広告枠など実測で確認したもの）は
**アプリに内蔵**（`builtinRules`）してあり、ダウンロードに失敗しても最低限は効きます。

### 10-3. 「ドメインだけ・パスは弾く」— 実際にあったバグの教訓

ブロックの照合は **URL の部分一致** です。ここに落とし穴がありました。

フィルタには `||google.com/pagead...`（Google の広告 *パス* だけを狙う規則）があります。
これを **単純に「google.com をブロック」と丸めてしまう** と、
`www.google.com/search`（検索）まで巻き込んで **検索できなくなる** 不具合が起きました。

対策として `networkDomain()` は次の規則だけ「ドメイン全体ブロック」に採用します：

```swift
// パス(/)やワイルドカード(*,?)を含む規則は採用しない（正規サイト全体を塞ぐため）
if pattern.contains(where: { $0 == "/" || $0 == "*" || $0 == "?" }) { return nil }
// domain= / replace= 等 "値付き修飾子" の規則も採用しない（スコープや意味が変わるため）
if options.contains(where: { $0 == "=" }) { return nil }
```

これで Google 検索・YouTube・Google ドキュメントなどの **正規サイトを塞がず**、
`doubleclick.net` のような **純粋な広告ドメインだけ** をブロックできます。

> 教訓：ブロック系の機能は “効かせる” より **“効かせ過ぎない”** ほうが難しい。
> だからこのアプリでは、実データで「正規サイトが巻き込まれていないか」を必ず確認しています。

### 10-4. コンパイルの工夫（堅牢性）

- 要素非表示ルールは **複数チャンクに分割** してコンパイル。1つの不正なセレクタで全体が
  無効化されないようにしています（1かたまりだけ捨てて他は生かす）。
- コンパイル結果は端末に **キャッシュ** され、次回は即適用。更新は約1週間に1回だけ再取得します。

---

## 11. 用語集（逆引き）

分からない言葉が出てきたら、ここで確認してください。

| 用語 | やさしい意味 |
|---|---|
| **Swift** | iPhone / Mac アプリを書くための言語 |
| **SwiftUI** | 画面を「完成形の宣言」で作る道具（宣言的UI） |
| **View（ビュー）** | 画面を作るブロック。組み合わせて画面にする |
| **宣言的UI** | 手順でなく “こう見えるべき” という結果を書くやり方 |
| **状態（State）** | アプリが覚えている値。変わると画面が自動更新 |
| **プロパティラッパー** | `@State` など `@` で始まる「状態の目印」 |
| **`@State`** | その View だけの小さな状態 |
| **`@StateObject` / `@ObservedObject`** | 値をまとめた「箱」を 所有する / 借りて見る |
| **`@Published`** | 「箱」の中の値。変わると見ている画面へ通知 |
| **`@AppStorage`** | 閉じても消えない状態（自動でファイルに保存） |
| **ObservableObject** | `@Published` を持てる「状態の箱」の型 |
| **バインディング（`$`）** | 状態と入力欄などを 双方向につなぐ |
| **enum（列挙型）** | 選択肢が決まった値（例：モードは text/files/web） |
| **クロージャ `{ ... }`** | 「あとで実行してね」と渡す処理のかたまり |
| **ジェネリクス `<T>`** | 「どんな型でも入れられる」という汎用の書き方 |
| **UIKit** | SwiftUI より前からある画面の道具（WKWebView 等） |
| **UIViewRepresentable** | UIKit部品を SwiftUI で使うための変換アダプター |
| **Coordinator** | UIKit部品からの通知を受け取る連絡係（通訳） |
| **デリゲート** | 「〜が起きたら教えてね」を託す相手（`navigationDelegate` 等） |
| **KVO / `observe`** | ある値の変化を見張って知らせてもらう仕組み |
| **WKWebView** | Safari と同じ、Webページを表示する部品 |
| **PDFKit / PDFView** | Apple 純正の PDF 表示部品 |
| **UserDefaults** | 小さな設定値を保存する場所（比率や文字サイズ等） |
| **セキュリティスコープ付きブックマーク** | 選んだファイルを次回も開ける “許可証つきしおり” |
| **WKContentRuleList** | WKWebView に適用する広告ブロックのルール |
| **リフロー** | 幅に合わせて文字を自動改行して流し込むこと |
| **User-Agent** | ブラウザが「自分は何者か」を名乗る文字列 |

---

## おわりに — もっと理解を深めるには

おすすめの読み進め方：
1. まず **動かして** みる（`ios-native/README.md` のビルド手順、または「2分割アプリ再ビルド」ショートカット）。
2. `SplitViewApp.swift` → `VSplit` → 好きなモード1つ、の順にコードを開いて、この解説と見比べる。
3. 小さく **いじって** みる：`RootView` の初期モードを変える、文字サイズの上限（`40`）を変える、
   `VSplit` の仕切りの高さ（`dividerH = 16`）を変える、など。1箇所変えて再ビルドすると理解が早いです。

分からない用語は11章の逆引きへ。コードのコメント（`//` の日本語説明）も一緒に読むと、
「なぜそう書いたか」が分かるようになっています。
