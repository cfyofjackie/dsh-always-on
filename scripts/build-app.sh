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
# Preserve builds as recoverable archives, so app search does not index every backup.
if [[ -e "$task_app" ]]; then
    [[ -d "$task_app" && ! -L "$task_app" ]] || { printf 'Unexpected existing App path\n' >&2; exit 1; }
    mkdir -p "$task_root/dist/app-archives"
    task_previous="$task_root/dist/app-archives/DSH-Always-On-previous-$(date +%Y%m%d-%H%M%S)-${task_stage##*.}.zip"
    ditto -c -k --sequesterRsrc --keepParent "$task_app" "$task_previous"
    unzip -tq "$task_previous"
    # The old bundle moves to our freshly created stage after its archive is verified.
    mv "$task_app" "$task_stage/previous.app"
fi
mv "$task_stage/DSH Always On.app" "$task_app"
# Only remove this invocation's rebuildable stage; earlier backups remain untouched.
[[ "$task_stage" == "$task_root/dist/app-stage."* && -d "$task_stage" && ! -L "$task_stage" ]] || exit 1
rm -rf -- "$task_stage"
printf 'Built: %s\n' "$task_app"
