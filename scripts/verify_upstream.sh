#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=upstream.env
source "$ROOT_DIR/scripts/upstream.env"

verify_checkout() {
    local name="$1"
    local expected_url="$2"
    local expected_commit="$3"
    local checkout="$ROOT_DIR/Vendor/$name"

    if [[ ! -d "$checkout/.git" ]]; then
        echo "error: missing checkout: $checkout" >&2
        exit 1
    fi

    local actual_url actual_commit dirty
    actual_url="$(git -C "$checkout" remote get-url origin)"
    actual_commit="$(git -C "$checkout" rev-parse HEAD)"
    dirty="$(git -C "$checkout" status --porcelain)"

    [[ "$actual_url" == "$expected_url" ]] || {
        echo "error: $name origin mismatch: $actual_url" >&2
        exit 1
    }
    [[ "$actual_commit" == "$expected_commit" ]] || {
        echo "error: $name revision mismatch: $actual_commit" >&2
        exit 1
    }
    [[ -z "$dirty" ]] || {
        echo "error: $name checkout contains uncommitted modifications" >&2
        exit 1
    }

    echo "verified $name at $actual_commit"
}

verify_checkout wrath-darkplaces "$WRATH_ENGINE_URL" "$WRATH_ENGINE_COMMIT"
verify_checkout wrath-qc "$WRATH_QC_URL" "$WRATH_QC_COMMIT"
verify_checkout SDL2 "$SDL2_URL" "$SDL2_COMMIT"
verify_checkout ogg "$OGG_URL" "$OGG_COMMIT"
verify_checkout vorbis "$VORBIS_URL" "$VORBIS_COMMIT"
verify_checkout freetype "$FREETYPE_URL" "$FREETYPE_COMMIT"
