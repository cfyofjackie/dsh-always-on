#!/bin/bash
set -euo pipefail
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
task_app="$task_root/dist/DSH Always On.app"
if [[ ! -d "$task_app" ]]; then bash "$task_root/scripts/build-app.sh"; fi
task_stage=$(mktemp -d "$task_root/dist/dmg-stage.XXXXXX")
cp -R "$task_app" "$task_stage/DSH Always On.app"
ln -s /Applications "$task_stage/Applications"
cp "$task_root/docs/使用说明.md" "$task_stage/使用说明.md"
# Keep each generated installer; never replace a pre-existing distribution artifact.
task_image="$task_root/dist/DSH-Always-On-0.1.0-arm64-$(date +%Y%m%d-%H%M%S).dmg"
hdiutil create -quiet -volname 'DSH Always On' -srcfolder "$task_stage" -format UDZO "$task_image"
hdiutil verify "$task_image"
printf 'Built: %s\n' "$task_image"
