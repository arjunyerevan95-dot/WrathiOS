#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: XcodeGen is required. Install it with 'brew install xcodegen'." >&2
    exit 1
fi

cd "$ROOT_DIR"
xcodegen generate --spec project.yml
xcodebuild -project WrathiOS.xcodeproj -scheme WrathiOS -showBuildSettings >/dev/null

echo "Generated $ROOT_DIR/WrathiOS.xcodeproj"
