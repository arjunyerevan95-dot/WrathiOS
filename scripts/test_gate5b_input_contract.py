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
    menu_patch = "\n".join(
        replacement["new"]
        for patch in spec["patches"]
        if patch["path"] == "menu.c"
        for replacement in patch["replacements"]
    )
    mvm_patch = "\n".join(
        replacement["new"]
        for patch in spec["patches"]
        if patch["path"] == "mvm_cmds.c"
        for replacement in patch["replacements"]
    )
    shared_video_patch = "\n".join(
        replacement["new"]
        for patch in spec["patches"]
        if patch["path"] == "vid_shared.c"
        for replacement in patch["replacements"]
    )
    bridge = (ROOT / "Gate5/WrathIOSInputBridge.mm").read_text(encoding="utf-8")
    diagnostics = (ROOT / "Gate5/WrathIOSInputDiagnostics.mm").read_text(encoding="utf-8")
    bridge_header = (ROOT / "Gate5/WrathIOSInputBridge.h").read_text(encoding="utf-8")
    math_header = (ROOT / "Gate5/WrathIOSInputMath.hpp").read_text(encoding="utf-8")
    runtime = (ROOT / "Gate5/WrathRuntime.mm").read_text(encoding="utf-8")
    delegate = (ROOT / "Gate5/AppDelegate.mm").read_text(encoding="utf-8")
    project = (ROOT / "project-gate5b.yml").read_text(encoding="utf-8")
    launcher = (ROOT / "Gate4/WrathImportViewController.mm").read_text(encoding="utf-8")
    plist = (ROOT / "App/Gate5BInfo.plist").read_text(encoding="utf-8")

    for marker in (
        "WrathIOSInputModeMenu",
        "WrathIOSInputModeMenuText",
        "WrathIOSInputModeGameplay",
        "key_dest == key_menu || key_dest == key_menu_grabbed",
        "cls.state == ca_connected",
        "cls.signon == SIGNONS",
        "!cl.intermission",
        "!cl.csqc_wantsmousemove",
        "MR_WrathIOSProfileTextEntryActive",
        "WrathIOSInputBeginFrame",
        "WrathIOSInputGetMenuPosition",
        "WrathIOSInputMarkMenuPositionApplied",
        "in_windowmouse_x = bound",
        "WrathIOSInputSetTextEntryActive",
        "WrathIOSInputTraceEngineState",
        "WrathIOSInputTraceCursorFinal",
        "WrathIOSInputTraceSDLTextEvent",
        "WrathIOSInputDismissTextEntry",
        "SDLK_RETURN",
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
        "MenuCursorState",
        "queueMenuTap",
        "consumeMenuButtonPhase",
        "resetMenuCursor",
    ):
        require(math_header, marker, "WrathIOSInputMath.hpp")

    for marker in (
        "CMMotionManager",
        "startDeviceMotionUpdatesUsingReferenceFrame",
        "deviceMotionUpdateInterval = 1.0 / 120.0",
        "WrathIOSInputModeMenu",
        "WrathIOSInputModeMenuText",
        "WrathIOSInputModeGameplay",
        "isGameplayLookZone",
        "getMenuCursor",
        "markMenuCursorApplied",
        "queueMenuTap",
        "consumeMenuButtonPhase",
        "forcedMenuButtonRelease",
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
        "Gate 5B gyro axis diagnostic",
        "raw rotation-rate rad/s",
        "Gate 5B profile text entry started",
        "Gate 5B profile text entry stopped",
        "native Return/Done dismissed the profile keyboard",
        "Gate 5B input mode changed",
        "Gate 5B foreground first frame",
        "resetGestureState(gInput.gesture)",
    ):
        require(bridge, marker, "WrathIOSInputBridge.mm")

    for marker in (
        "WrathIOSProfileKeyboardField",
        "UITextFieldDelegate",
        "becomeFirstResponder",
        "SDL_StartTextInput",
        "SDL_StopTextInput",
        "SDL_IsTextInputActive",
        "SDL_TEXTINPUT",
        "SDLK_BACKSPACE",
        "SDLK_RETURN",
        "deleteBackward",
        "hasText",
        "UIKit fallback",
        "SDL native text input",
        "gate5b-r3-input-contract-v1",
        "bridge-direct-touch",
        "menu-vm-builtin",
        "gyroMenuSamplesIgnored",
        "gyroGameplaySamplesApplied",
        "WrathIOSDiagnosticsSetMotionRunning",
        "candidate(unverified)",
        "orientationName()",
        "WrathIOSRuntimeStage(\"Gate 5B R3 menu detector\"",
        "userInteractionEnabled = NO",
    ):
        require(diagnostics, marker, "WrathIOSInputDiagnostics.mm")

    for marker in (
        "WrathIOSInputSetMode",
        "WrathIOSInputBeginFrame",
        "WrathIOSInputGetMenuPosition",
        "WrathIOSInputMarkMenuPositionApplied",
        "WrathIOSInputConsumeGameplayLook",
        "WrathIOSInputSetTextEntryActive",
        "WrathIOSInputDismissTextEntry",
        "WrathIOSInputReset",
        "WrathIOSInputEnteredForeground",
        "WrathIOSInputTraceCursorWrite",
        "WrathIOSInputTraceCursorFinal",
        "WrathIOSInputTraceMenuVMRead",
        "WrathIOSInputTraceMenuState",
        "WrathIOSInputTraceSDLTextEvent",
        "WrathIOSInputTraceGyro",
        "WrathIOSDiagnosticsSetMotionRunning",
    ):
        require(bridge_header, marker, "WrathIOSInputBridge.h")

    require(runtime, 'SDL_HINT_TOUCH_MOUSE_EVENTS, "0", SDL_HINT_OVERRIDE', "WrathRuntime.mm")
    require(runtime, "Gate 5B mode-specific input bridge selected", "WrathRuntime.mm")
    for marker in (
        "MR_WrathIOSProfileTextEntryActive",
        'PRVM_ED_FindGlobal(prog, "menu_current")',
        'PRVM_ED_FindGlobal(prog, "menu_createprofile")',
        'PRVM_ED_FindGlobal(prog, "ui_selected")',
        'PRVM_ED_FindField(prog, "partner")',
        "*selected_entity == *field_entity",
        "MR_WrathIOSRecordMenuDiagnosticState",
        'PRVM_ED_FindGlobal(prog, "ui_hover")',
        'PRVM_ED_FindGlobal(prog, "ui_mouseposition")',
        "WrathIOSInputTraceMenuState",
    ):
        require(menu_patch, marker, "Gate 5B authentic profile-field state patch")

    for marker in (
        "VM_M_getmousepos",
        "WrathIOSInputGetMenuPosition",
        "WrathIOSInputTraceMenuVMRead",
        "wrath_virtual_x",
        "wrath_virtual_y",
        "return;",
    ):
        require(mvm_patch, marker, "Gate 5B menu-VM cursor boundary patch")

    require(shared_video_patch, "#ifndef WRATH_IOS_GATE5B", "Gate 5B center-reset bypass")
    require(shared_video_patch, "in_windowmouse_x = vid_width.value / 2.f", "Gate 5B center-reset bypass")

    require(runtime, 'WrathTranscriptVersion = @"0.0.9 (9)"', "WrathRuntime.mm")
    require(delegate, 'WrathIOSInputReset("background")', "AppDelegate.mm")
    require(delegate, 'WrathIOSInputReset("focus loss")', "AppDelegate.mm")
    require(delegate, "WrathIOSInputEnteredForeground()", "AppDelegate.mm")
    require(project, "WRATH_IOS_GATE5B=1", "project-gate5b.yml")
    require(project, "CoreMotion.framework", "project-gate5b.yml")
    require(project, "WRATH_IOS_GYRO_DIAGNOSTIC=1", "project-gate5b.yml")
    require(project, "com.arjukstudios.wrathios.gate3", "project-gate5b.yml")
    require(project, "MARKETING_VERSION: 0.0.9", "project-gate5b.yml")
    require(project, "CURRENT_PROJECT_VERSION: 9", "project-gate5b.yml")
    require(project, "WRATH_GIT_HEAD_SHORT: unknown", "project-gate5b.yml")
    require(plist, "<string>0.0.9</string>", "Gate5BInfo.plist")
    require(plist, "<string>9</string>", "Gate5BInfo.plist")
    require(plist, "<key>WrathBuildHead</key>", "Gate5BInfo.plist")
    require(launcher, "GATE 5B REVISION 3", "Gate 5B launcher provenance")
    require(launcher, "gate5b-r3-input-contract-v1", "Gate 5B launcher provenance")

    combined = patched_text + menu_patch + mvm_patch + shared_video_patch + bridge + diagnostics + runtime + delegate
    for marker in (
        "WrathIOSMenuPointer",
        "WRATH_IOS_MENU_POINTER_SENSITIVITY",
        "relative origin established; cursor unchanged",
        "single-finger relative touchpad",
        "menuPositionPending",
        "WrathIOSInputConsumeMenuPosition",
    ):
        forbid(combined, marker, "revised Gate 5B input sources")

    forbid(bridge, "Key_Event(", "project-owned input bridge")
    forbid(bridge, "fire button", "project-owned input bridge")
    forbid(bridge, "movement joystick", "project-owned input bridge")
    forbid(diagnostics, "movement joystick", "project-owned diagnostics")
    forbid(diagnostics, "fire button", "project-owned diagnostics")

    print("Gate 5B R3 menu-VM cursor ownership instrumentation: compiled contract passed; device-unverified")
    print("Gate 5B R3 position/hover/down/up sequence instrumentation: compiled contract passed; device-unverified")
    print("Gate 5B R3 SDL plus narrow UIKit profile keyboard bridge: compiled contract passed; device-unverified")
    print("Gate 5B R3 pre-gameplay raw-axis diagnostic contract: passed; physical axes device-unverified")
    print("Gate 5B right-side gameplay swipe-look source contract: passed")
    print("Gate 5B Core Motion gyro source contract: passed")
    print("menu/gameplay/other mutual-exclusion and reset contract: passed")
    print("SDL touch-to-mouse synthesis conflict guard: passed")
    print("gameplay movement and firing controls: absent")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
