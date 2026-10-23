#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_input="${APP_INPUT:-"$project_root/outputs/PluginShelf.app"}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_input/Contents/Info.plist")"
dmg_output="${DMG_OUTPUT:-"$project_root/outputs/PluginShelf-$version-macOS-Universal.dmg"}"
design_work="$project_root/work/dmg-design"
tool_modules="${DMGBUILD_MODULES:-"$design_work/tools"}"
export PYTHONPATH="$tool_modules${PYTHONPATH:+:$PYTHONPATH}"
export CLANG_MODULE_CACHE_PATH="$design_work/ModuleCache"
mkdir -p "$design_work"
if ! python3 -c 'import dmgbuild' 2>/dev/null; then
    echo "Install the packaging tool: python3 -m pip install --target '$tool_modules' dmgbuild==1.6.5" >&2
    exit 1
fi
codesign --verify --strict "$app_input"
swiftc "$project_root/Packaging/DmgBackground.swift" -o "$design_work/render-background"
swiftc "$project_root/Packaging/DmgBookmark.swift" -o "$design_work/encode-bookmark"
"$design_work/render-background" "$design_work/background.tiff"
mkdir -p "$(dirname "$dmg_output")"
python3 -m dmgbuild -s "$project_root/Packaging/dmg-settings.py" \
    -D "app=$app_input" -D "background=$design_work/background.tiff" -D "bookmark_encoder=$design_work/encode-bookmark" \
    "安装 PluginShelf" "$dmg_output"
hdiutil verify "$dmg_output"
(
    cd "$(dirname "$dmg_output")"
    shasum -a 256 "$(basename "$dmg_output")" > "$(basename "$dmg_output").sha256"
)
echo "Built $dmg_output"
