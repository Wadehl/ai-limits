#!/bin/bash
# 不需要付费开发者账号的发布构建：临时签名（ad-hoc），小组件走 local 共享位置，产物放到 dist/
# 用法：VERSION=0.2.0 ./scripts/build-release.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
DERIVED="$DIST/DerivedData"
APP_NAME="Linook"
VOLUME_NAME="Linook"

cd "$ROOT"
xcodegen generate

# 临时签名没有团队编号，应用组权限在 macOS 15 上反而会让小组件扩展被拒绝访问，这里直接去掉
for f in Build/AiLimits.entitlements Build/AiLimitsWidget.entitlements; do
    /usr/libexec/PlistBuddy -c "Delete :com.apple.security.application-groups" "$f" 2>/dev/null || true
done

VERSION="${VERSION:-}"
VERSION="${VERSION#v}"
EXTRA=()
[ -n "$VERSION" ] && EXTRA+=("MARKETING_VERSION=$VERSION")
[ -n "${BUILD_NUMBER:-}" ] && EXTRA+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")

rm -rf "$DIST"
xcodebuild -project AiLimits.xcodeproj -scheme AiLimits -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    AILIMITS_SHARED_STORAGE=local \
    ${EXTRA[@]+"${EXTRA[@]}"} build

APP="$DIST/$APP_NAME.app"
BUILT="$DERIVED/Build/Products/Release/$APP_NAME.app"
ditto "$BUILT" "$APP"
# xcodebuild 会把构建目录里的副本登记到 LaunchServices，留着会在本机多出一份同名小组件
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister
pluginkit -r "$BUILT/Contents/PlugIns/AiLimitsWidgetExtension.appex" 2>/dev/null || true
"$LSREGISTER" -u "$BUILT" 2>/dev/null || true
APPEX="$APP/Contents/PlugIns/AiLimitsWidgetExtension.appex"
[ -d "$APPEX" ] || { echo "产物里没有小组件扩展：$APPEX" >&2; exit 1; }

codesign --verify --deep --strict --verbose=2 "$APP"
echo "--- 签名与权限 ---"
codesign -dv "$APP" 2>&1 | grep -E 'Identifier|Signature|TeamIdentifier|flags' || true
codesign -d --entitlements - "$APPEX" 2>/dev/null || true
for plist in "$APP/Contents/Info.plist" "$APPEX/Contents/Info.plist"; do
    mode="$(/usr/libexec/PlistBuddy -c 'Print :AiLimitsSharedStorage' "$plist")"
    [ "$mode" = "local" ] || { echo "$plist 的 AiLimitsSharedStorage 是 $mode，应为 local" >&2; exit 1; }
done
lipo -info "$APP/Contents/MacOS/$APP_NAME"

SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BASE="$APP_NAME-$SHORT_VERSION-macOS"

ditto -c -k --norsrc --keepParent "$APP" "$DIST/$BASE.zip"

STAGING="$DIST/dmg"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DIST/$BASE.dmg"
rm -rf "$STAGING"

(cd "$DIST" && shasum -a 256 "$BASE.zip" "$BASE.dmg" > SHA256SUMS.txt && cat SHA256SUMS.txt)
echo "已生成 $DIST/$BASE.zip 与 $DIST/$BASE.dmg"
