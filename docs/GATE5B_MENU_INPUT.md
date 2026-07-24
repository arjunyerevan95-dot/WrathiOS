# Gate 5B Revision 2 input architecture

## Physical-device reassessment

The v7 direct-touch bridge converted finger coordinates correctly, but
`WrathIOSInputConsumeMenuPosition` cleared the coordinate after one engine
frame. Upstream `vid_shared.c` also initialized `in_windowmouse_x/y` to the
video center whenever touchscreen video mode was established. The result was
one transient absolute update followed by the shared center-ish coordinate.

`Sys_SendKeyEvents` applies bridge state before polling the current frame's SDL
finger events. A tap discovered during polling therefore cannot safely click
immediately: the menu VM has not yet drawn and updated `ui_hover` at that new
coordinate. Revision 2 makes the cursor persistent and uses an explicit
position/draw/down/up sequence.

## Persistent menu ownership

`MenuCursorState` owns the last valid logical-window coordinate while the
engine is in menu or menu-text mode. Reading the coordinate never consumes it.
Every menu input frame reapplies it to `in_windowmouse_x/y`; the menu VM retains
its existing logical-to-virtual conversion:

`virtual = logical * vid_con dimension / vid dimension`

No drawable-pixel scale is used. The upstream touchscreen center initialization
is bypassed only under `WRATH_IOS_GATE5B`. The existing Gate 5B touchscreen
branch continues to bypass SDL mouse polling, mouse warping, the 128 by 128
legacy touch areas, and the multitouch mouse-button path. SDL synthesized
touch-to-mouse events remain disabled.

A tap captured in frame N queues the coordinate generation. Frame N+1 reapplies
the coordinate and lets the authentic menu draw/update hover. Frame N+2 sends
`K_MOUSE1` down, and frame N+3 sends button up. Finger-up preserves the last
coordinate. Dragging updates it absolutely and suppresses a click after the
1.2-percent movement threshold.

## Authentic profile-name text entry

Pinned WRATH menu QC already owns the field and accepts alphanumeric Unicode
key events plus Backspace. It tries to open a keyboard only through the
Steam-specific `steam_openkeyboard` command, so a non-Steam iOS build never
requests one.

The engine-side `MR_WrathIOSProfileTextEntryActive` query reads the loaded menu
VM's actual `menu_current`, `menu_createprofile`, `ui_selected`, and `partner`
entity globals. Text mode is selected only when the authentic New Profile
screen is current and its authentic field is selected. No screen coordinate,
artwork name, fake UIKit text field, or replacement `menu.dat` is involved.

Text mode calls SDL's native iOS `SDL_StartTextInput`. Existing
`SDL_TEXTINPUT` decoding delivers `K_TEXT` to the menu VM; existing key events
provide Backspace and Return. Because the authentic field does not bind Return,
Gate 5B treats the native Return/Done key as keyboard dismissal after delivering
the key event; the authentic Accept control still submits the profile. SDL text
input also stops when the field/menu is left, gameplay begins, focus is lost,
or the app backgrounds. WRATH QC intentionally accepts only letters and numbers
and limits profile names to 16 characters.

## Mode separation

- Menu: persistent direct touch and frame-sequenced click; no gyro or swipe.
- Menu text: the same direct touch plus SDL native text input; no gyro or
  gameplay swipe.
- Gameplay: rightmost-65-percent relative swipe-look plus gyro; no cursor
  writes, menu clicks, or fire.
- Other/loading/inactive: touch, click, text, swipe, and gyro state reset.

Transitions between the two menu modes preserve the cursor coordinate but
cancel a pending click. Transitions out of the menu family reset cursor
ownership. Gameplay and lifecycle transitions clear pending look deltas and
Core Motion history.

## Gyro diagnosis boundary

The v7 mapping uses device X for yaw and device Y for pitch (with
landscape-specific signs). Physical evidence showed forward/back tilt producing
horizontal motion, so that mapping is not accepted. The available report does
not establish which remaining raw axis and signs correspond to deliberate yaw
in both physical landscape orientations.

The v8 diagnostic candidate therefore records bounded 5 Hz snapshots of raw
Core Motion rotation-rate X/Y/Z plus the v7 baseline mapped yaw/pitch. Up to 24
snapshots are written to the sanitized transcript and shown in a small,
non-interactive gameplay-only overlay compiled with
`WRATH_IOS_GYRO_DIAGNOSTIC`. The overlay is hidden whenever gameplay motion is
suspended. Core Motion continues to use bias-corrected
`CMDeviceMotion.rotationRate` at 120 Hz; no high-rate transcript is produced.

This build deliberately does not claim a corrected final axis mapping. The
isolated left/right, forward/back, and roll device test in both landscape
orientations must identify the physical axes before the mapping is changed.
Swipe-look is otherwise unchanged.

## Evidence boundary

Host tests prove persistent cursor state, position-before-click ordering,
explicit reset behavior, normalized/logical/virtual coordinate math, the
right-side aim zone, baseline landscape transform math, and mode-gated text and
gyro source contracts. CI cannot prove UIKit keyboard presentation, touch hit
quality, physical gyro axes, stationary drift, or foreground recovery.
