#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=upstream.env
source "$ROOT_DIR/scripts/upstream.env"
VENDOR_DIR="$ROOT_DIR/Vendor"

fetch_exact_revision() {
    local name="$1"
    local url="$2"
    local commit="$3"
    local destination="$VENDOR_DIR/$name"

    if [[ -e "$destination" && ! -d "$destination/.git" ]]; then
        echo "error: $destination exists but is not a Git checkout" >&2
        exit 1
    fi

    if [[ ! -d "$destination/.git" ]]; then
        mkdir -p "$destination"
        git -C "$destination" init --quiet
        git -C "$destination" remote add origin "$url"
    fi

    local actual_origin
    actual_origin="$(git -C "$destination" remote get-url origin)"
    if [[ "$actual_origin" != "$url" ]]; then
        echo "error: unexpected origin for $name: $actual_origin" >&2
        exit 1
    fi

    git -C "$destination" fetch --quiet --depth 1 origin "$commit"
    git -C "$destination" -c advice.detachedHead=false checkout --quiet --detach FETCH_HEAD

    local actual_commit
    actual_commit="$(git -C "$destination" rev-parse HEAD)"
    if [[ "$actual_commit" != "$commit" ]]; then
        echo "error: expected $commit for $name, got $actual_commit" >&2
        exit 1
    fi

    echo "$name: $actual_commit"
}

mkdir -p "$VENDOR_DIR"
fetch_exact_revision wrath-darkplaces "$WRATH_ENGINE_URL" "$WRATH_ENGINE_COMMIT"
fetch_exact_revision wrath-qc "$WRATH_QC_URL" "$WRATH_QC_COMMIT"
fetch_exact_revision SDL2 "$SDL2_URL" "$SDL2_COMMIT"

"$ROOT_DIR/scripts/verify_upstream.sh"
python3 "$ROOT_DIR/scripts/validate_engine_manifest.py" --require-upstream
