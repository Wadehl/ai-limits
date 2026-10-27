#!/bin/bash
# CI 里检查：安装到 /Applications 之后，系统能否认出小组件扩展。
# 只能说明扩展能被 PlugInKit 注册，不能说明桌面上一定显示得出来。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP=/Applications/Linook.app
APPEX="$APP/Contents/PlugIns/AiLimitsWidgetExtension.appex"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister

sudo rm -rf "$APP"
sudo ditto "$ROOT/dist/Linook.app" "$APP"
"$LSREGISTER" -f -R -trusted "$APP"
pluginkit -a "$APPEX" || true
WIDGET_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APPEX/Contents/Info.plist")"
echo "小组件扩展：$WIDGET_ID"
spctl --assess --type execute -vv "$APP" 2>&1 || true

for _ in 1 2 3 4 5; do
    if pluginkit -m -v -i "$WIDGET_ID" | grep -q "$WIDGET_ID"; then
        pluginkit -m -v -i "$WIDGET_ID"
        echo "PlugInKit 已注册小组件扩展"
        exit 0
    fi
    sleep 2
done
pluginkit -m -v -p com.apple.widgetkit-extension || true
echo "::warning::PlugInKit 没有列出 $WIDGET_ID"
