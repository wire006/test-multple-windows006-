import SwiftUI

// MARK: - 実機のみ想定の「上下2分割ビューア」アプリ本体
//
// 1つのアプリで2つの用途を切り替えられます（上部のセグメントで選択）:
//   1. Web分割   … Claude と Google ドキュメントを上下に（WebSplit.swift）
//   2. ファイル分割 … Files に保存した MD と PDF を上下に（DocsSplit.swift）
//
// セットアップ手順は ios-native/README.md を参照。

@main
struct SplitViewApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    enum Mode: Int, CaseIterable, Identifiable {
        case web, files
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .web:   return "Web (Claude/Docs)"
            case .files: return "ファイル (PDF×2)"
            }
        }
    }

    @State private var mode: Mode = .web

    var body: some View {
        VStack(spacing: 0) {
            Picker("表示", selection: $mode) {
                ForEach(Mode.allCases) { m in Text(m.label).tag(m) }
            }
            .pickerStyle(.segmented)
            .padding(6)

            // 両方を常にマウントしたまま表示だけ切り替える。
            // こうすると Web 側のログインセッションが、モード切替で失われない。
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

// MARK: - 汎用: 上下2分割 + ドラッグ可能な仕切り
struct VerticalSplit<Top: View, Bottom: View>: View {
    @ViewBuilder var top: Top
    @ViewBuilder var bottom: Bottom

    @State private var topHeight: CGFloat = 320
    @State private var dragStart: CGFloat? = nil
    private let dividerH: CGFloat = 26
    private let minPane: CGFloat = 120

    var body: some View {
        GeometryReader { geo in
            let maxTop = max(minPane, geo.size.height - dividerH - minPane)
            let clamped = min(max(minPane, topHeight), maxTop)

            VStack(spacing: 0) {
                top.frame(height: clamped)
                divider
                bottom.frame(maxHeight: .infinity)
            }
        }
    }

    private var divider: some View {
        ZStack {
            Color(.systemGray5)
            Capsule().fill(Color(.systemGray)).frame(width: 44, height: 5)
        }
        .frame(height: dividerH)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStart == nil { dragStart = topHeight }
                    topHeight = (dragStart ?? topHeight) + value.translation.height
                }
                .onEnded { _ in dragStart = nil }
        )
    }
}

// MARK: - 汎用: 各ペイン上部のツールバー
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
