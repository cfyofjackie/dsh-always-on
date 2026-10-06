#!/bin/bash
set -euo pipefail
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
task_icons_requested=false
if [[ "${1:-}" == "--icons" ]]; then
    task_icons_requested=true
elif [[ $# -gt 0 ]]; then
    printf 'Usage: bash scripts/refresh-art.sh [--icons]\n' >&2
    exit 1
fi
node "$task_root/scripts/sync-pet-art.mjs"
node "$task_root/scripts/sync-life-art.mjs"
# Export with the existing Swift renderer without starting the UI or DSH integration.
mkdir -p "$task_root/dist"
task_art=$(mktemp -d "$task_root/dist/art-export.XXXXXX")
cd "$task_root/macos"
swift build -c release --product DSHAlwaysOn
task_binary=$(swift build -c release --show-bin-path)/DSHAlwaysOn
"$task_binary" --export-art "$task_art"
for task_state in idle working waiting success error; do
    test -s "$task_art/$task_state.png"
    cp "$task_art/$task_state.png" "$task_root/macos/Resources/characters/"
done
if [[ "$task_icons_requested" == true ]]; then
test -s "$task_art/app-icon.png"
for task_size in 16 32 128 256 512; do
    task_icons="$task_root/macos/Resources/Assets.xcassets/AppIcon.appiconset"
    sips -z "$task_size" "$task_size" "$task_art/app-icon.png" --out "$task_icons/icon_${task_size}x${task_size}.png" >/dev/null
    task_double=$((task_size * 2))
    sips -z "$task_double" "$task_double" "$task_art/app-icon.png" --out "$task_icons/icon_${task_size}x${task_size}@2x.png" >/dev/null
done
fi
printf 'Synced playground character under macos/Resources. Build the Xcode App again to use it.\n'
