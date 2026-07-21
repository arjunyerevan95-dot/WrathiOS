#!/usr/bin/env python3
"""Materialize the pinned SDL2 source with the bounded iOS UIWindowScene patch."""

from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Vendor" / "SDL2"
DERIVED = ROOT / "Derived" / "SDL2-ios"
TARGET_RELATIVE = Path("src/video/uikit/SDL_uikitwindow.m")
EXPECTED_COMMIT = "5d249570393f7a37e037abf22cd6012a4cc56a71"


def fail(message: str) -> int:
    print(f"error: {message}", file=sys.stderr)
    return 1


def main() -> int:
    if not (SOURCE / ".git").is_dir():
        return fail("missing pinned SDL2 checkout")

    revision = subprocess.run(
        ["git", "-C", str(SOURCE), "rev-parse", "HEAD"],
        text=True,
        capture_output=True,
        check=False,
    )
    if revision.returncode != 0:
        return fail(revision.stderr.strip() or "could not read SDL2 revision")
    if revision.stdout.strip() != EXPECTED_COMMIT:
        return fail(
            f"expected SDL2 {EXPECTED_COMMIT}, got {revision.stdout.strip()}"
        )

    if DERIVED.exists():
        shutil.rmtree(DERIVED)
    shutil.copytree(
        SOURCE,
        DERIVED,
        ignore=shutil.ignore_patterns(".git"),
        symlinks=True,
    )

    target = DERIVED / TARGET_RELATIVE
    text = target.read_text(encoding="utf-8")

    old_frame = "    CGRect frame = UIKit_ComputeViewFrame(window, displaydata.uiscreen);"
    new_frame = (
        "    /* WrathiOS: a scene-backed UIWindow already has the authoritative "
        "landscape geometry. */\n"
        "    CGRect frame = uiwindow != nil ? uiwindow.bounds : "
        "UIKit_ComputeViewFrame(window, displaydata.uiscreen);"
    )

    old_window = """        /* ignore the size user requested, and make a fullscreen window */
        /* !!! FIXME: can we have a smaller view? */
        uiwindow = [[SDL_uikitwindow alloc] initWithFrame:data.uiscreen.bounds];"""
    new_window = """        /* WrathiOS: SDL 2.32 creates a frame-only UIWindow here. In a custom
         * UIKit host on iOS 13+, that detached window falls back to legacy
         * 320x480 geometry. Attach it to the active UIWindowScene, matching the
         * behavior adopted by newer SDL releases. */
        uiwindow = nil;
        if (@available(iOS 13.0, tvOS 13.0, *)) {
            UIWindowScene *activeScene = nil;
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (![scene isKindOfClass:[UIWindowScene class]]) {
                    continue;
                }
                UIWindowScene *candidate = (UIWindowScene *)scene;
                if (candidate.activationState == UISceneActivationStateForegroundActive) {
                    activeScene = candidate;
                    break;
                }
                if (activeScene == nil && candidate.activationState != UISceneActivationStateUnattached) {
                    activeScene = candidate;
                }
            }
            if (activeScene != nil) {
                uiwindow = [[SDL_uikitwindow alloc] initWithWindowScene:activeScene];
                uiwindow.frame = activeScene.coordinateSpace.bounds;
            }
        }
        if (uiwindow == nil) {
            uiwindow = [[SDL_uikitwindow alloc] initWithFrame:data.uiscreen.bounds];
        }"""

    for old, new, label in (
        (old_frame, new_frame, "scene-backed initial view geometry"),
        (old_window, new_window, "active UIWindowScene attachment"),
    ):
        count = text.count(old)
        if count != 1:
            return fail(f"expected exactly one {label} patch site, found {count}")
        text = text.replace(old, new, 1)

    target.write_text(text, encoding="utf-8")
    print(f"materialized SDL2 iOS patches at {DERIVED.relative_to(ROOT)}")
    print(f"patched {TARGET_RELATIVE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
