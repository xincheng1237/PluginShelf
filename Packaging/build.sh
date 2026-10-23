#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="${BUILD_DIR:-"$project_root/.build-release"}"
app_path="${APP_OUTPUT:-"$project_root/outputs/PluginShelf.app"}"
export CLANG_MODULE_CACHE_PATH="$build_root/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_root/ModuleCache"
mkdir -p "$build_root"
for cpu in arm64 x86_64; do
  swift build --disable-sandbox --package-path "$project_root" --scratch-path "$build_root/$cpu" --triple "$cpu-apple-macosx14.0" -c release
  bin_path="$(swift build --disable-sandbox --package-path "$project_root" --scratch-path "$build_root/$cpu" --triple "$cpu-apple-macosx14.0" -c release --show-bin-path)"
  cp "$bin_path/PluginShelf" "$build_root/PluginShelf-$cpu"
done
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
lipo -create "$build_root/PluginShelf-arm64" "$build_root/PluginShelf-x86_64" -output "$app_path/Contents/MacOS/PluginShelf"
cp "$project_root/Packaging/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_root/Packaging/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app_path"
codesign --verify --strict "$app_path"
file "$app_path/Contents/MacOS/PluginShelf"
echo "Built $app_path"
