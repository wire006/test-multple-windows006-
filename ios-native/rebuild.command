#!/bin/bash
#
# 「2分割」アプリを iPhone に再ビルド＆インストールするショートカット。
# デスクトップに置いてダブルクリックすれば、接続中の iPhone に入れ直せます。
# （無料 Apple ID は7日で失効するので、切れたらこれを実行すればOK）
#
set -e

# Homebrew(xcodegen) を PATH に追加（Intel Mac は /usr/local、Apple Silicon は /opt/homebrew）
export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"

# ── 設定 ───────────────────────────────
PROJECT_DIR="$HOME/test-multple-windows006-/ios-native"
BUNDLE_ID="com.wire006.splitview"   # 署名が通らない時はここを splitview2 等に変更
# ──────────────────────────────────────

cd "$PROJECT_DIR"

echo "▶ 最新のコードを取得 (git pull)..."
git -C "$PROJECT_DIR" pull --ff-only || echo "（git pull はスキップ／現在のコードでビルドします）"

echo "▶ プロジェクト生成 (xcodegen)..."
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
fi

# 署名チームID: ~/.splitview_team を最優先、無ければ Apple Development 証明書(OU)から自動抽出
TEAM=""
if [ -f "$HOME/.splitview_team" ]; then
  TEAM=$(tr -d '[:space:]' < "$HOME/.splitview_team")
else
  TEAM=$(security find-certificate -a -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | grep -oE 'OU *= *[A-Z0-9]{10}' | grep -oE '[A-Z0-9]{10}' | head -1)
fi

if [ -z "$TEAM" ]; then
  echo ""
  echo "⚠️ 署名チームが見つかりません。初回だけ Xcode で署名を作成してください:"
  echo "   1) Xcode → Settings → Accounts で Apple ID を追加"
  echo "   2) open \"$PROJECT_DIR/SplitView.xcodeproj\""
  echo "   3) SplitView ターゲット → Signing & Capabilities →"
  echo "      「Automatically manage signing」にチェック＆「Team」を選択（証明書が作られます）"
  echo "   その後このショートカットを再実行すれば、以降は自動で署名します。"
  echo "   （Team ID が分かっている場合: echo あなたの10桁ID > ~/.splitview_team ）"
  exit 1
fi
echo "▶ 署名チーム: $TEAM"

echo "▶ iPhone 向けにビルド（署名あり）..."
xcodebuild -project SplitView.xcodeproj -scheme SplitView -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" -derivedDataPath build build

APP="build/Build/Products/Debug-iphoneos/SplitView.app"

echo "▶ 接続中の iPhone を検出..."
UDID=$(xcrun devicectl list devices 2>/dev/null \
  | grep -iE 'iphone' | grep -iwE 'connected' \
  | grep -oiE '[0-9A-F-]{36}' | head -1)

if [ -z "$UDID" ]; then
  echo "⚠️ 接続中の iPhone が見つかりません（ケーブル接続と「信頼」を確認）。ビルドは完了しています。"
else
  echo "▶ インストール（$UDID）..."
  xcrun devicectl device install app --device "$UDID" "$APP"
  echo "▶ 起動..."
  xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" || true
  echo "✅ 完了。iPhone のホーム画面に「2分割」が入っています。"
fi

echo ""
echo "（このウィンドウは閉じて大丈夫です）"
