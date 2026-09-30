#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT="${1:-$ROOT/logs/widget-preview}"

cd "$ROOT"
swift build -c "$CONFIGURATION" --product AiLimitsWidgetPreview
BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"

# AnimalFont 从 Bundle.main 找字体，命令行工具的主目录就是可执行文件所在目录
cp "$ROOT/Resources/Nunito.ttf" "$BIN_PATH/Nunito.ttf"

"$BIN_PATH/AiLimitsWidgetPreview" "$OUTPUT"
