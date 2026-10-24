#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
icon_work="${ICON_BUILD_DIR:-"$project_root/work/app-icon"}"
icon_output="${ICON_OUTPUT:-"$project_root/Packaging/AppIcon.icns"}"
export CLANG_MODULE_CACHE_PATH="$icon_work/ModuleCache"
mkdir -p "$icon_work/AppIcon.iconset" "$(dirname "$icon_output")"
swiftc "$project_root/Packaging/Icon.swift" -o "$icon_work/render-icon"
for size in 16 32 128 256 512; do
    "$icon_work/render-icon" "$icon_work/AppIcon.iconset/icon_${size}x${size}.png" "$size" "$project_root/Packaging/Artwork/PluginLibrary.png"
    "$icon_work/render-icon" "$icon_work/AppIcon.iconset/icon_${size}x${size}@2x.png" "$((size * 2))" "$project_root/Packaging/Artwork/PluginLibrary.png"
done
iconutil -c icns "$icon_work/AppIcon.iconset" -o "$icon_output"
echo "Built $icon_output"
