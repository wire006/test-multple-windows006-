import SwiftUI

// MARK: - 実機用「上下/左右 2分割ビューア」アプリ本体
//
// 1つのアプリで2つの用途を、上部セグメントで切り替え:
//   1. 分割ブラウザ … 任意の2サイトを分割表示（既定: Claude と Google ドキュメント）… WebSplit.swift
//   2. PDF×2       … Files に保存した PDF を2つ分割表示 … DocsSplit.swift
//
// セットアップ手順は ios-native/README.md を参照。

@main
struct SplitViewApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    enum Mode: Int, CaseIterable, Identifiable {
        case web, files
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .web:   return "分割ブラウザ"
            case .files: return "PDF×2"
            }
        }
    }

    @State private var mode: Mode = .web

    var body: some View {
        VStack(spacing: 0) {
            Picker("表示", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(6)

            // 両方を常にマウントしたまま表示だけ切り替える
            // （ブラウザのログインセッションや PDF の選択状態を維持するため）
            ZStack {
                WebSplit()
                    .opacity(mode == .web ? 1 : 0)
                    .allowsHitTesting(mode == .web)
                DocsSplit()
                    .opacity(mode == .files ? 1 : 0)
                    .allowsHitTesting(mode == .files)
            }
        }
    }
}

// MARK: - 分割の向き / 全画面状態
enum SplitAxis: String { case vertical, horizontal }   // vertical = 上下 / horizontal = 左右
enum FullscreenPane { case none, first, second }

// MARK: - 汎用: 2ペイン分割（上下・左右対応、片側全画面対応、ドラッグ仕切り）
//
// first / second はビューツリー内で「1回だけ」参照し、向き・全画面の切替では
// frame と offset の数値だけを変える。こうすると WKWebView が再生成されず、
// 開いているページ（ログイン状態やスクロール位置）が維持される。
struct TwoPaneSplit<First: View, Second: View>: View {
    let axis: SplitAxis
    let fullscreen: FullscreenPane
    @Binding var fraction: Double            // 1つ目のペインが占める割合（0.15〜0.85）
    @ViewBuilder var first: First
    @ViewBuilder var second: Second

    private let dividerT: CGFloat = 14
    @State private var dragStart: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            let isV = axis == .vertical
            let showDivider = fullscreen == .none
            let axisTotal = isV ? H : W
            let usable = max(0, axisTotal - (showDivider ? dividerT : 0))
            let clamped = min(max(0.15, fraction), 0.85)
            let firstAxis: CGFloat = fullscreen == .first ? axisTotal
                                   : (fullscreen == .second ? 0 : usable * CGFloat(clamped))
            let dividerAxis: CGFloat = showDivider ? dividerT : 0
            let secondAxis = max(0, axisTotal - firstAxis - dividerAxis)

            ZStack(alignment: .topLeading) {
                first
                    .frame(width: isV ? W : firstAxis, height: isV ? firstAxis : H)
                    .offset(x: 0, y: 0)

                if showDivider {
                    dividerView(total: axisTotal)
                        .frame(width: isV ? W : dividerAxis, height: isV ? dividerAxis : H)
                        .offset(x: isV ? 0 : firstAxis, y: isV ? firstAxis : 0)
                }

                second
                    .frame(width: isV ? W : secondAxis, height: isV ? secondAxis : H)
                    .offset(x: isV ? 0 : firstAxis + dividerAxis,
                            y: isV ? firstAxis + dividerAxis : 0)
            }
            .frame(width: W, height: H)
        }
    }

    private func dividerView(total: CGFloat) -> some View {
        ZStack {
            Color(.systemGray5)
            Capsule().fill(Color(.systemGray))
                .frame(width: axis == .vertical ? 44 : 5,
                       height: axis == .vertical ? 5 : 44)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStart == nil { dragStart = fraction }
                    let moved = axis == .vertical ? value.translation.height : value.translation.width
                    let delta = Double(moved) / Double(max(1, total))
                    fraction = min(0.85, max(0.15, (dragStart ?? fraction) + delta))
                }
                .onEnded { _ in dragStart = nil }
        )
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
        .padding(.vertical, 6)
        .background(.thinMaterial)
    }
}
