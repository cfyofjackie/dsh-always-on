#!/bin/bash
set -euo pipefail
# GUI-launched Xcode does not inherit a terminal's Homebrew PATH.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
task_root=$(CDPATH= cd -- "$PROJECT_DIR/.." && pwd -P)
if ! command -v node >/dev/null 2>&1; then
    echo 'error: Building the bundled DSH plugin requires Node.js 24+. Install the development dependency before building.' >&2
    exit 1
fi
if [[ ! -f "$task_root/plugin/node_modules/esbuild/package.json" ]]; then
    echo 'error: Plugin dependencies are missing. Run npm ci in the project plugin directory once, then build again.' >&2
    exit 1
fi
cd "$task_root/plugin"
node build.mjs
task_resources="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/plugin"
mkdir -p "$task_resources/lib"
cp package.json "$task_resources/package.json"
cp lib/index.js lib/client.js "$task_resources/lib/"
