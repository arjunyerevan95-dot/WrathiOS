#!/usr/bin/env python3
"""Validate the pinned WRATH iOS source inventory and Gate 2 compile manifest."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "config/engine/source_dispositions.json"
SOURCE_LIST_PATH = ROOT / "config/engine/ios_upstream_sources.txt"
UPSTREAM_PATH = ROOT / "Vendor/wrath-darkplaces"

VALID_DISPOSITIONS = {
    "include_portable",
    "include_builtin_stub",
    "include_deferred_static_binding",
    "include_ios_adaptation",
    "replace_ios",
    "exclude_architecture",
    "exclude_desktop_backend",
    "exclude_optional_feature",
}


class ValidationError(RuntimeError):
    pass


def fail(message: str) -> None:
    raise ValidationError(message)


def load_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"missing manifest: {path.relative_to(ROOT)}")
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {path.relative_to(ROOT)}: {exc}")
    raise AssertionError("unreachable")


def read_source_list(path: Path) -> list[str]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        fail(f"missing compile source list: {path.relative_to(ROOT)}")
    return [line.strip() for line in lines if line.strip() and not line.lstrip().startswith("#")]


def discover_upstream_translation_units() -> set[str]:
    source_text = "\n".join(
        (UPSTREAM_PATH / name).read_text(encoding="utf-8", errors="replace")
        for name in ("makefile", "makefile.inc")
    )
    stems = set(re.findall(r"(?<![A-Za-z0-9_])([A-Za-z0-9_]+)\.o\b", source_text))
    discovered = {
        f"{stem}.c"
        for stem in stems
        if (UPSTREAM_PATH / f"{stem}.c").is_file()
    }
    if (UPSTREAM_PATH / "builddate.c").is_file():
        discovered.add("builddate.c")
    return discovered


def validate_checkout_revision(expected_commit: str) -> None:
    try:
        actual = subprocess.check_output(
            ["git", "-C", str(UPSTREAM_PATH), "rev-parse", "HEAD"],
            text=True,
            stderr=subprocess.STDOUT,
        ).strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        fail(f"unable to read upstream revision: {exc}")
    if actual != expected_commit:
        fail(f"upstream revision mismatch: expected {expected_commit}, got {actual}")


def validate(require_upstream: bool) -> None:
    manifest = load_json(MANIFEST_PATH)

    if manifest.get("schema_version") != 1:
        fail("unsupported source manifest schema_version")

    upstream = manifest.get("upstream")
    if not isinstance(upstream, dict):
        fail("manifest.upstream must be an object")
    expected_commit = upstream.get("commit")
    if not isinstance(expected_commit, str) or not re.fullmatch(r"[0-9a-f]{40}", expected_commit):
        fail("manifest upstream commit must be a full lowercase SHA-1")

    sources = manifest.get("sources")
    if not isinstance(sources, list) or not sources:
        fail("manifest.sources must be a non-empty array")

    by_path: dict[str, dict[str, Any]] = {}
    for index, source in enumerate(sources):
        if not isinstance(source, dict):
            fail(f"sources[{index}] must be an object")
        path = source.get("path")
        disposition = source.get("disposition")
        selected = source.get("selected_for_gate2")
        reason = source.get("reason")

        if not isinstance(path, str) or not re.fullmatch(r"[A-Za-z0-9_]+\.c", path):
            fail(f"sources[{index}].path is invalid: {path!r}")
        if path in by_path:
            fail(f"duplicate source disposition: {path}")
        if disposition not in VALID_DISPOSITIONS:
            fail(f"invalid disposition for {path}: {disposition!r}")
        if not isinstance(selected, bool):
            fail(f"selected_for_gate2 must be boolean for {path}")
        if not isinstance(reason, str) or not reason.strip():
            fail(f"missing reason for {path}")

        if disposition.startswith("exclude_") and selected:
            fail(f"excluded source cannot be selected: {path}")
        if disposition == "replace_ios":
            if selected:
                fail(f"replaced upstream source cannot be selected directly: {path}")
            replacement = source.get("replacement")
            if not isinstance(replacement, str) or not replacement:
                fail(f"replacement path is required for {path}")

        by_path[path] = source

    selected_paths = [source["path"] for source in sources if source["selected_for_gate2"]]
    expected_list = [f"Vendor/wrath-darkplaces/{path}" for path in selected_paths]
    actual_list = read_source_list(SOURCE_LIST_PATH)

    if len(actual_list) != len(set(actual_list)):
        fail("compile source list contains duplicates")
    if actual_list != expected_list:
        expected_set = set(expected_list)
        actual_set = set(actual_list)
        missing = sorted(expected_set - actual_set)
        extra = sorted(actual_set - expected_set)
        fail(
            "compile source list does not match selected manifest entries"
            f"; missing={missing}; extra={extra}; order_mismatch={not missing and not extra}"
        )

    counts = manifest.get("counts")
    if not isinstance(counts, dict):
        fail("manifest.counts must be an object")
    expected_counts = {
        "upstream_translation_units": len(sources),
        "selected_upstream_translation_units": len(selected_paths),
        "ios_replacements_planned": sum(
            1 for source in sources if source["disposition"] == "replace_ios"
        ),
    }
    for key, value in expected_counts.items():
        if counts.get(key) != value:
            fail(f"manifest count mismatch for {key}: expected {value}, got {counts.get(key)}")

    dependencies = manifest.get("dependencies")
    if not isinstance(dependencies, list) or not dependencies:
        fail("manifest.dependencies must be a non-empty array")
    approved_sdl = [
        dependency
        for dependency in dependencies
        if isinstance(dependency, dict)
        and dependency.get("name") == "SDL2"
        and dependency.get("gate2_status") == "approved"
    ]
    if len(approved_sdl) != 1:
        fail("exactly one approved SDL2 dependency is required")
    sdl_commit = approved_sdl[0].get("commit")
    if not isinstance(sdl_commit, str) or not re.fullmatch(r"[0-9a-f]{40}", sdl_commit):
        fail("SDL2 dependency must be pinned to a full commit SHA")

    if UPSTREAM_PATH.is_dir():
        if not (UPSTREAM_PATH / ".git").is_dir():
            fail("Vendor/wrath-darkplaces exists but is not a Git checkout")
        validate_checkout_revision(expected_commit)
        discovered = discover_upstream_translation_units()
        recorded = set(by_path)
        missing = sorted(discovered - recorded)
        stale = sorted(recorded - discovered)
        if missing or stale:
            fail(f"source universe mismatch; missing={missing}; stale={stale}")
        absent_selected = sorted(
            path for path in selected_paths if not (UPSTREAM_PATH / path).is_file()
        )
        if absent_selected:
            fail(f"selected upstream sources are absent: {absent_selected}")
        upstream_state = "verified against pinned checkout"
    elif require_upstream:
        fail("pinned upstream checkout is required; run scripts/fetch_upstream.sh")
    else:
        upstream_state = "checkout absent; structural validation only"

    print(
        "validated WRATH iOS source manifest: "
        f"{len(sources)} recorded, {len(selected_paths)} selected, "
        f"{expected_counts['ios_replacements_planned']} replacement; {upstream_state}"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--require-upstream",
        action="store_true",
        help="fail unless Vendor/wrath-darkplaces is present at the pinned revision",
    )
    args = parser.parse_args()

    try:
        validate(args.require_upstream)
    except ValidationError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
