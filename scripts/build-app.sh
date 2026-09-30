#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Release}"
APP="/Applications/AiLimits.app"

cd "$ROOT"
xcodegen generate

DERIVED="$(xcodebuild -project AiLimits.xcodeproj -scheme AiLimits -configuration "$CONFIGURATION" -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
[ -n "$DERIVED" ] || { echo "取不到构建产物目录" >&2; exit 1; }

xcodebuild -project AiLimits.xcodeproj -scheme AiLimits -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' -allowProvisioningUpdates build

rm -rf "$APP"
ditto "$DERIVED/AiLimits.app" "$APP"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister
"$LSREGISTER" -f -R -trusted "$APP"

echo "已安装 $APP"
pluginkit -m -v -p com.apple.widgetkit-extension | grep -i ailimits || echo "小组件扩展还没有注册" >&2
