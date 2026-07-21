import SwiftUI

// MARK: - 実機用「上下2分割ビューア」アプリ本体
//
// 1つのアプリで2つの用途を、上部セグメントで切り替え:
//   1. 分割ブラウザ … 任意の2サイトを上下に（WebSplit.swift）
//   2. PDF×2       … Files に保存した PDF を2つ上下に（DocsSplit.swift）
//
// どちらも共通の VSplit（上ペインを一番上に固定・仕切りドラッグで高さ可変）を使用。
// セットアップ手順は ios-native/README.md を参照。

@main
struct SplitViewApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    enum Mode: Int, CaseIterable, Identifiable {
        case text, files, web    // 先頭 = 既定。テキストを最初に開く
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .text:  return "テキスト×2"
            case .files: return "PDF×2"
            case .web:   return "分割ブラウザ"
            }
        }
    }

    @State private var mode: Mode = .text   // 既定はテキスト

    var body: some View {
        VStack(spacing: 0) {
            Picker("表示", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding([.top, .horizontal], 6)

            // 両方を常にマウントしたまま表示だけ切り替える
            // （ブラウザのログインセッションや PDF の選択状態を維持するため）
            ZStack {
                TextSplit()
                    .opacity(mode == .text ? 1 : 0)
                    .allowsHitTesting(mode == .text)
                DocsSplit()
                    .opacity(mode == .files ? 1 : 0)
                    .allowsHitTesting(mode == .files)
                WebSplit()
                    .opacity(mode == .web ? 1 : 0)
                    .allowsHitTesting(mode == .web)
            }
        }
    }
}

// MARK: - 汎用: 上下2分割（上ペインを一番上に固定・仕切りドラッグで高さ可変）
//
// シンプルな VStack。上ペインは指定高さぶんを一番上から占め、仕切りをドラッグすると
// その高さ（＝下ペインの大きさ）が変わる。中央寄せの余白は出ない。
// 仕切りは固定座標系での指の絶対位置で決めるため、発振（画面が上下に暴れる）しない。
struct VSplit<Top: View, Bottom: View>: View {
    private let top: Top
    private let bottom: Bottom
    private let space: String
    @AppStorage private var topFraction: Double   // 分割比率を保存（次回起動時に復元）
    private let dividerH: CGFloat = 28             // つかみやすいよう仕切りを大きめに

    init(_ storageKey: String, @ViewBuilder top: () -> Top, @ViewBuilder bottom: () -> Bottom) {
        self.top = top()
        self.bottom = bottom()
        self.space = "VSplit." + storageKey
        self._topFraction = AppStorage(wrappedValue: 0.5, "split." + storageKey)
    }

    var body: some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.height - dividerH)
            let topH = min(max(120, usable * topFraction), max(120, usable - 120))

            VStack(spacing: 0) {
                top
                    .frame(height: topH)
                    .clipped()

                ZStack {
                    Color(.systemGray4)
                    Capsule().fill(Color(.systemGray)).frame(width: 60, height: 6)
                }
                .frame(maxWidth: .infinity)
                .frame(height: dividerH)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                        .onChanged { v in
                            topFraction = min(0.85, max(0.15, Double(v.location.y) / Double(usable)))
                        }
                )

                bottom
                    .frame(maxHeight: .infinity)
                    .clipped()
            }
            .coordinateSpace(name: space)
        }
    }
}

// MARK: - 汎用: ファイルペイン上部のツールバー（PDFペインで使用）
struct PaneBar: View {
    let title: String
    let filename: String?
    let onPick: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.headline)
            if let filename {
                Text(filename)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("選択", action: onPick).buttonStyle(.bordered)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)          // 名前バーの上下幅を薄く（6→4）
        .background(.thinMaterial)
    }
}
