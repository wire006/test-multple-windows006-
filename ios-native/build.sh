#!/usr/bin/env bash
#
# ダウンロード後、これ1本でシミュレータ向けにビルド＆起動できます（署名不要）。
#   使い方: cd ios-native && ./build.sh
#
# 実機ビルドは README の「実機へインストール」を参照（署名が必要）。
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "✗ xcodegen が見つかりません。'brew install xcodegen' を実行してください。" >&2
  exit 1
fi

echo "▶ Xcode プロジェクトを生成 (xcodegen)..."
xcodegen generate

# 利用可能な iPhone シミュレータを1台自動選択
DEVICE=$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ {gsub(/^ +| +$/,"",$1); print $1; exit}')
DEVICE=${DEVICE:-iPhone 15}
echo "▶ シミュレータ: $DEVICE"
open -a Simulator || true
xcrun simctl boot "$DEVICE" 2>/dev/null || true

echo "▶ ビルド..."
xcodebuild -project SplitView.xcodeproj -scheme SplitView \
  -configuration Debug -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath build build

APP="build/Build/Products/Debug-iphonesimulator/SplitView.app"
echo "▶ インストール＆起動..."
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl launch "$DEVICE" com.wire006.splitview
echo "✅ 完了（シミュレータで起動しました）"
