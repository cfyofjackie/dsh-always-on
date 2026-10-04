#!/bin/bash
set -euo pipefail
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$task_root/plugin"
npm ci --silent
# Xcode builds and embeds the plugin through the shared App scheme.
xcodebuild -project "$task_root/macos/DSHAlwaysOn.xcodeproj" \
    -scheme 'DSH Always On' -configuration Release \
    -destination 'platform=macOS,arch=arm64' ARCHS=arm64 \
    -derivedDataPath "$task_root/dist/XcodeReleaseDerivedData" build

task_built="$task_root/dist/XcodeReleaseDerivedData/Build/Products/Release/DSH Always On.app"
task_app="$task_root/dist/DSH Always On.app"
task_stage=$(mktemp -d "$task_root/dist/app-stage.XXXXXX")
ditto "$task_built" "$task_stage/DSH Always On.app"
codesign --verify --deep --strict "$task_stage/DSH Always On.app"
# Preserve any existing local build; do not merge two signed bundles.
if [[ -e "$task_app" ]]; then
    task_previous="$task_root/dist/DSH Always On-previous-$(date +%Y%m%d-%H%M%S)-${task_stage##*.}.app"
    mv "$task_app" "$task_previous"
fi
mv "$task_stage/DSH Always On.app" "$task_app"
printf 'Built: %s\n' "$task_app"
