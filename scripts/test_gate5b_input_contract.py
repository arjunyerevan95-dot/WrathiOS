#!/usr/bin/env python3
"""Verify the revised Gate 5B mode-specific iOS input source contract."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def require(text: str, marker: str, source: str) -> None:
    if marker not in text:
        raise SystemExit(f"error: {source} is missing {marker!r}")


def forbid(text: str, marker: str, source: str) -> None:
    if marker in text:
        raise SystemExit(f"error: {source} still contains forbidden marker {marker!r}")


def main() -> int:
    spec = json.loads((ROOT / "config/engine/ios_source_patches.json").read_text(encoding="utf-8"))
    patched_text = "\n".join(
        replacement["new"]
        for patch in spec["patches"]
        if patch["path"] == "vid_sdl.c"
        for replacement in patch["replacements"]
    )
    bridge = (ROOT / "Gate5/WrathIOSInputBridge.mm").read_text(encoding="utf-8")
    bridge_header = (ROOT / "Gate5/WrathIOSInputBridge.h").read_text(encoding="utf-8")
    math_header = (ROOT / "Gate5/WrathIOSInputMath.hpp").read_text(encoding="utf-8")
    runtime = (ROOT / "Gate5/WrathRuntime.mm").read_text(encoding="utf-8")
    delegate = (ROOT / "Gate5/AppDelegate.mm").read_text(encoding="utf-8")
    project = (ROOT / "project-gate5b.yml").read_text(encoding="utf-8")

    for marker in (
        "WrathIOSInputModeMenu",
        "WrathIOSInputModeGameplay",
        "key_dest == key_menu || key_dest == key_menu_grabbed",
        "cls.state == ca_connected",
        "cls.signon == SIGNONS",
        "!cl.intermission",
        "!cl.csqc_wantsmousemove",
        "WrathIOSInputConsumeMenuPosition",
        "in_windowmouse_x = bound",
        "WrathIOSInputConsumeMenuButtonPhase",
        "Key_Event(K_MOUSE1",
        "WrathIOSInputConsumeGameplayLook",
        "in_mouse_x += wrath_look_x",
        "in_mouse_y += wrath_look_y",
        "WrathIOSInputFingerDown",
        "WrathIOSInputFingerMotion",
        "WrathIOSInputFingerUp",
        'WrathIOSInputReset("SDL window hidden")',
        'WrathIOSInputReset("SDL focus loss")',
    ):
        require(patched_text, marker, "Gate 5B vid_sdl derived-source patch")

    for marker in (
        "kMenuTapThresholdFraction = 0.012f",
        "kGameplayLookZoneStart = 0.35f",
        "kSwipeSensitivityX = 2.0f",
        "kSwipeSensitivityY = 1.65f",
        "kGyroDeadZoneRadiansPerSecond = 0.015f",
        "kGyroMouseUnitsPerRadian = 900.0f",
        "normalizedToLogical",
        "logicalToVirtual",
        "mapGyroRotationRate",
        "resetGestureState",
    ):
        require(math_header, marker, "WrathIOSInputMath.hpp")

    for marker in (
        "CMMotionManager",
        "startDeviceMotionUpdatesUsingReferenceFrame",
        "deviceMotionUpdateInterval = 1.0 / 120.0",
        "WrathIOSInputModeMenu",
        "WrathIOSInputModeGameplay",
        "isGameplayLookZone",
        "menuClickPending",
        "menuButtonDown",
        "Gate 5B menu touch began",
        "Gate 5B menu absolute position updated",
        "Gate 5B menu tap emitted",
        "Gate 5B gameplay aim touch began",
        "Gate 5B gameplay swipe movement emitted",
        "no click or fire event emitted",
        "Gate 5B gyro started",
        "Gate 5B gyro delta applied",
        "Gate 5B gyro suspended",
        "Gate 5B gyro baseline reset",
        "Gate 5B input mode changed",
        "Gate 5B foreground first frame",
        "resetGestureState(gInput.gesture)",
    ):
        require(bridge, marker, "WrathIOSInputBridge.mm")

    for marker in (
        "WrathIOSInputSetMode",
        "WrathIOSInputConsumeMenuPosition",
        "WrathIOSInputConsumeGameplayLook",
        "WrathIOSInputReset",
        "WrathIOSInputEnteredForeground",
    ):
        require(bridge_header, marker, "WrathIOSInputBridge.h")

    require(runtime, 'SDL_HINT_TOUCH_MOUSE_EVENTS, "0", SDL_HINT_OVERRIDE', "WrathRuntime.mm")
    require(runtime, "Gate 5B mode-specific input bridge selected", "WrathRuntime.mm")
    require(runtime, 'WrathTranscriptVersion = @"0.0.7 (7)"', "WrathRuntime.mm")
    require(delegate, 'WrathIOSInputReset("background")', "AppDelegate.mm")
    require(delegate, 'WrathIOSInputReset("focus loss")', "AppDelegate.mm")
    require(delegate, "WrathIOSInputEnteredForeground()", "AppDelegate.mm")
    require(project, "WRATH_IOS_GATE5B=1", "project-gate5b.yml")
    require(project, "CoreMotion.framework", "project-gate5b.yml")
    require(project, "com.arjukstudios.wrathios.gate3", "project-gate5b.yml")
    require(project, "MARKETING_VERSION: 0.0.7", "project-gate5b.yml")
    require(project, "CURRENT_PROJECT_VERSION: 7", "project-gate5b.yml")

    combined = patched_text + bridge + runtime + delegate
    for marker in (
        "WrathIOSMenuPointer",
        "WRATH_IOS_MENU_POINTER_SENSITIVITY",
        "relative origin established; cursor unchanged",
        "single-finger relative touchpad",
    ):
        forbid(combined, marker, "revised Gate 5B input sources")

    forbid(bridge, "Key_Event(", "project-owned input bridge")
    forbid(bridge, "fire button", "project-owned input bridge")
    forbid(bridge, "movement joystick", "project-owned input bridge")

    print("Gate 5B direct absolute menu-touch source contract: passed")
    print("Gate 5B right-side gameplay swipe-look source contract: passed")
    print("Gate 5B Core Motion gyro source contract: passed")
    print("menu/gameplay/other mutual-exclusion and reset contract: passed")
    print("SDL touch-to-mouse synthesis conflict guard: passed")
    print("gameplay movement and firing controls: absent")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
