#!/usr/bin/env python3
"""Verify the Gate 5B deterministic-menu-input source contract."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def require(text: str, marker: str, source: str) -> None:
    if marker not in text:
        raise SystemExit(f"error: {source} is missing {marker!r}")


def main() -> int:
    spec = json.loads((ROOT / "config/engine/ios_source_patches.json").read_text(encoding="utf-8"))
    patched_text = "\n".join(
        replacement["new"]
        for patch in spec["patches"]
        if patch["path"] == "vid_sdl.c"
        for replacement in patch["replacements"]
    )
    runtime = (ROOT / "Gate5/WrathRuntime.mm").read_text(encoding="utf-8")
    delegate = (ROOT / "Gate5/AppDelegate.mm").read_text(encoding="utf-8")
    project = (ROOT / "project-gate5b.yml").read_text(encoding="utf-8")

    for marker in (
        "WRATH_IOS_MENU_TAP_THRESHOLD_FRACTION 0.018f",
        "WRATH_IOS_MENU_POINTER_SENSITIVITY 1.0f",
        "SDL_FingerID finger_id",
        "previous_x",
        "accumulated_movement",
        "click_emitted",
        "WrathIOSMenuPointerBegin(&event.tfinger)",
        "WrathIOSMenuPointerMove(&event.tfinger)",
        "WrathIOSMenuPointerEnd(&event.tfinger)",
        "button down emitted; release deferred to the next engine frame",
        "normalized finger delta converted once to logical window coordinates",
        "keydest == key_menu",
        "Gate 5B background pointer reset",
        "Gate 5B foreground first frame",
    ):
        require(patched_text, marker, "Gate 5B vid_sdl derived-source patch")

    require(runtime, 'SDL_HINT_TOUCH_MOUSE_EVENTS, "0", SDL_HINT_OVERRIDE', "WrathRuntime.mm")
    require(runtime, "Gate 5B direct touch path selected", "WrathRuntime.mm")
    require(delegate, 'WrathIOSMenuPointerReset("background")', "AppDelegate.mm")
    require(delegate, "WrathIOSMenuPointerEnteredForeground()", "AppDelegate.mm")
    require(project, "WRATH_IOS_GATE5B=1", "project-gate5b.yml")
    require(project, "com.arjukstudios.wrathios.gate3", "project-gate5b.yml")

    forbidden = (
        "virtual joystick",
        "gyro aiming",
        "fire button",
        "movement zone",
    )
    lowered = (patched_text + runtime + delegate).lower()
    found = [term for term in forbidden if term in lowered]
    if found:
        raise SystemExit("error: gameplay-control markers entered Gate 5B: " + ", ".join(found))

    print("Gate 5B relative-touchpad source contract: passed")
    print("SDL touch-to-mouse synthesis conflict guard: passed")
    print("tap/drag/frame-separated click contract: passed")
    print("focus/background/foreground reset contract: passed")
    print("gameplay virtual controls: absent")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
