#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/DerivedData/Gate4"
ARTIFACT_DIR="$ROOT_DIR/Artifacts/gate4-device-importer"
LOG="$ARTIFACT_DIR/xcodebuild.log"
PROJECT="$ROOT_DIR/WrathiOSGate4.xcodeproj"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug-iphoneos/WrathiOSGate4.app"
BINARY="$APP_BUNDLE/WrathiOSGate4"
PACKAGE_ROOT="$ROOT_DIR/Derived/gate4-package"
IPA="$ARTIFACT_DIR/WrathiOSGate4-unsigned.ipa"

mkdir -p "$ARTIFACT_DIR"
rm -rf "$DERIVED_DATA" "$PROJECT" "$PACKAGE_ROOT"

command -v xcodegen >/dev/null 2>&1 || {
  echo "error: xcodegen is required" >&2
  exit 2
}

cd "$ROOT_DIR"
xcodegen generate --spec project-gate4.yml

set -o pipefail
xcodebuild \
  -project WrathiOSGate4.xcodeproj \
  -scheme WrathiOSGate4 \
  -configuration Debug \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tee "$LOG"

[[ -d "$APP_BUNDLE" && -f "$BINARY" ]] || {
  echo "error: Gate 4 application bundle was not produced" >&2
  exit 1
}

file "$BINARY" | tee "$ARTIFACT_DIR/file.txt"
lipo -info "$BINARY" | tee "$ARTIFACT_DIR/architecture.txt"
otool -L "$BINARY" | tee "$ARTIFACT_DIR/dynamic-dependencies.txt"
nm -gU "$BINARY" > "$ARTIFACT_DIR/global-symbols.txt"
plutil -p "$APP_BUNDLE/Info.plist" > "$ARTIFACT_DIR/Info.plist.txt"
strings -a "$BINARY" > "$ARTIFACT_DIR/strings.txt"
find "$APP_BUNDLE" -print | sed "s#^$APP_BUNDLE#.#" | sort > "$ARTIFACT_DIR/bundle-inventory.txt"

architecture="$(cat "$ARTIFACT_DIR/architecture.txt")"
[[ "$architecture" == *"arm64"* ]] || {
  echo "error: Gate 4 application is not arm64" >&2
  exit 1
}

grep -q '_OBJC_CLASS_$_WrathImportViewController' "$ARTIFACT_DIR/global-symbols.txt" || {
  echo "error: Gate 4 importer view-controller class is missing" >&2
  exit 1
}
grep -q '_OBJC_CLASS_$_WrathDataImporter' "$ARTIFACT_DIR/global-symbols.txt" || {
  echo "error: Gate 4 importer service class is missing" >&2
  exit 1
}
grep -q 'Choose WRATH Folder' "$ARTIFACT_DIR/strings.txt" || {
  echo "error: Gate 4 folder-picker marker is missing" >&2
  exit 1
}
for sentinel in progs.dat csprogs.dat menu.dat; do
  grep -q "$sentinel" "$ARTIFACT_DIR/strings.txt" || {
    echo "error: Gate 4 binary is missing sentinel marker: $sentinel" >&2
    exit 1
  }
done

if grep -Eq '_Host_Main$|_SDL_Init$' "$ARTIFACT_DIR/global-symbols.txt"; then
  echo "error: Gate 4 must not link or start the WRATH runtime" >&2
  exit 1
fi

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Info.plist")"
short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Info.plist")"
build_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_BUNDLE/Info.plist")"
launch_storyboard="$(/usr/libexec/PlistBuddy -c 'Print :UILaunchStoryboardName' "$APP_BUNDLE/Info.plist")"
[[ "$bundle_id" == "com.arjukstudios.wrathios.gate3" ]] || {
  echo "error: unexpected Gate 4 bundle identifier: $bundle_id" >&2
  exit 1
}
[[ "$short_version" == "0.0.3" ]] || {
  echo "error: unexpected Gate 4 short version: $short_version" >&2
  exit 1
}
[[ "$build_version" == "3" ]] || {
  echo "error: unexpected Gate 4 build version: $build_version" >&2
  exit 1
}
[[ "$launch_storyboard" == "LaunchScreen" ]] || {
  echo "error: unexpected Gate 4 launch storyboard declaration: $launch_storyboard" >&2
  exit 1
}
launch_storyboard_path="$(find "$APP_BUNDLE" -type d -name 'LaunchScreen.storyboardc' -print -quit)"
[[ -n "$launch_storyboard_path" ]] || {
  echo "error: compiled LaunchScreen.storyboardc is missing from the Gate 4 bundle" >&2
  cat "$ARTIFACT_DIR/bundle-inventory.txt" >&2
  exit 1
}
printf '%s\n' "${launch_storyboard_path#"$APP_BUNDLE"/}" > "$ARTIFACT_DIR/launch-storyboard-location.txt"

python3 - "$ARTIFACT_DIR/dynamic-dependencies.txt" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()[1:]
paths = [line.strip().split()[0] for line in lines if line.strip()]
allowed = ("/System/Library/Frameworks/", "/usr/lib/")
invalid = [path for path in paths if not path.startswith(allowed)]
if invalid:
    print("error: non-system dynamic dependencies detected:", file=sys.stderr)
    for path in invalid:
        print(f"  {path}", file=sys.stderr)
    raise SystemExit(1)
print(f"validated {len(paths)} system dynamic dependencies")
PY

if find "$APP_BUNDLE" -type f \( -iname '*.pak' -o -iname '*.pk3' -o -iname '*.pk4' -o -iname '*.wad' \) -print -quit | grep -q .; then
  echo "error: Gate 4 bundle unexpectedly contains commercial-style archives" >&2
  exit 1
fi

if codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null 2>&1; then
  echo "error: CI importer unexpectedly contains a valid signature" >&2
  exit 1
else
  echo "unsigned CI bundle confirmed" > "$ARTIFACT_DIR/signing-status.txt"
fi

mkdir -p "$PACKAGE_ROOT/Payload"
ditto "$APP_BUNDLE" "$PACKAGE_ROOT/Payload/WrathiOSGate4.app"
rm -rf "$PACKAGE_ROOT/Payload/WrathiOSGate4.app/_CodeSignature"
rm -f "$PACKAGE_ROOT/Payload/WrathiOSGate4.app/embedded.mobileprovision"
(
  cd "$PACKAGE_ROOT"
  /usr/bin/zip -qry "$IPA" Payload
)

[[ -s "$IPA" ]] || {
  echo "error: unsigned Gate 4 IPA was not produced" >&2
  exit 1
}
/usr/bin/unzip -tq "$IPA" > "$ARTIFACT_DIR/ipa-validation.txt"
shasum -a 256 "$BINARY" "$IPA" > "$ARTIFACT_DIR/SHA256SUMS.txt"
cp "$BINARY" "$ARTIFACT_DIR/WrathiOSGate4-arm64"

cat > "$ARTIFACT_DIR/device-test-checklist.md" <<'EOF'
# Gate 4 physical-device checklist

1. Install `WrathiOSGate4-unsigned.ipa` through the existing Gate 3 App ID.
2. Confirm the screen identifies Gate 4 and says the engine/runtime remain disabled.
3. Tap **Choose WRATH Folder** and select either the licensed installation root or its `kp1` folder.
4. Confirm an incomplete or unrelated folder fails with missing sentinel details.
5. Import the licensed folder and wait for both source and sandboxed-copy validation.
6. Confirm the final card reports compatible data, file count, package count, and total size.
7. Force-quit and relaunch. Confirm the installed-data validation still passes without selecting the source again.
8. Confirm **Remove Imported Data** removes only the sandboxed copy.

Do not attach imported files, package listings containing private paths, or the app container to issues or CI artifacts.
EOF

cat > "$ARTIFACT_DIR/summary.md" <<EOF
# Gate 4 device importer build

- Target: arm64-apple-ios16.3
- Bundle ID: \`$bundle_id\` (reuses the existing diagnostic App ID)
- Version: \`$short_version ($build_version)\`
- Runtime engine startup: absent
- Validation profile: \`wrath-1.1.2-qc-layout-v1\`
- Required sentinels: \`progs.dat\`, \`csprogs.dat\`, \`menu.dat\`
- Supported package indexes: PK3 and Quake PAK
- Launch storyboard: \`${launch_storyboard_path#"$APP_BUNDLE"/}\`
- Non-system dynamic dependencies: none
- Commercial data in IPA: absent
- Packaging: unsigned IPA for external signing
EOF

echo "Gate 4 device importer build and packaging validation passed"
