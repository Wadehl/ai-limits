#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Release}"
APP="/Applications/Linook.app"
# 改名前安装的旧包，bundle id 相同，留着会让系统登记两份同名小组件
OLD_APP="/Applications/AiLimits.app"

# 换成自己的团队编号（包括免费的 Personal Team）：DEVELOPMENT_TEAM=XXXXXXXXXX ./scripts/build-app.sh
TEAM_ARGS=()
[ -n "${DEVELOPMENT_TEAM:-}" ] && TEAM_ARGS+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")

cd "$ROOT"
xcodegen generate

DERIVED="$(xcodebuild -project AiLimits.xcodeproj -scheme AiLimits -configuration "$CONFIGURATION" -destination 'platform=macOS' ${TEAM_ARGS[@]+"${TEAM_ARGS[@]}"} -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
[ -n "$DERIVED" ] || { echo "取不到构建产物目录" >&2; exit 1; }

xcodebuild -project AiLimits.xcodeproj -scheme AiLimits -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' -allowProvisioningUpdates ${TEAM_ARGS[@]+"${TEAM_ARGS[@]}"} build

rm -rf "$APP"
ditto "$DERIVED/Linook.app" "$APP"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister
if [ -d "$OLD_APP" ]; then
    pluginkit -r "$OLD_APP/Contents/PlugIns/AiLimitsWidgetExtension.appex" 2>/dev/null || true
    "$LSREGISTER" -u "$OLD_APP" 2>/dev/null || true
    rm -rf "$OLD_APP"
    echo "已移除改名前的 $OLD_APP"
fi
"$LSREGISTER" -f -R -trusted "$APP"

echo "已安装 $APP"
pluginkit -m -v -p com.apple.widgetkit-extension | grep -i ailimits || echo "小组件扩展还没有注册" >&2
