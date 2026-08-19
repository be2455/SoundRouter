#!/bin/bash
# 把 SwiftPM 執行檔包成 SoundRouter.app 並簽章。
# Core Audio 的 process tap 一定要有 bundle 身分（Info.plist + 簽章）才拿得到
# TCC 授權；直接跑裸執行檔的話 tap 只會送回靜音。
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="build/SoundRouter.app"

swift build -c "$CONFIG" --product SoundRouterApp
swift build -c "$CONFIG" --product audiorouter

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/SoundRouterApp" "$APP/Contents/MacOS/SoundRouterApp"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# 沒有 Developer ID 就用 ad-hoc 簽章。可以正常運作，但簽章雜湊會隨每次重建改變，
# 所以 TCC 授權在重建後可能需要重新勾選一次。
IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --verbose=2 "$APP" 2>&1 | sed 's/^/  /'

# CLI 直接從 shell 執行時拿不到 process tap 的 TCC 授權（tap 會靜靜地回傳靜音），
# 所以另外包一份帶 bundle 身分的版本，用 `open` 啟動時可正常擷取音訊。
PROBE="build/AudioRouterProbe.app"
rm -rf "$PROBE"
mkdir -p "$PROBE/Contents/MacOS"
cp "$BIN_DIR/audiorouter" "$PROBE/Contents/MacOS/audiorouter"
cp Packaging/ProbeInfo.plist "$PROBE/Contents/Info.plist"
codesign --force --sign "$IDENTITY" "$PROBE"

# 裸執行檔也簽一下，至少在已獲授權的終端機裡跑得動。
codesign --force --sign "$IDENTITY" "$BIN_DIR/audiorouter"

echo
echo "已建立 $APP"
echo "診斷用 CLI bundle：$PROBE"
echo "裸 CLI：$BIN_DIR/audiorouter"
