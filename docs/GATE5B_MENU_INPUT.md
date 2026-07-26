# Gate 5B Revision 4 input architecture

## Authentic menu pointer call graph

The pinned WRATH menu QC source establishes this path:

1. SDL finger events are polled by `Sys_SendKeyEvents`.
2. The project bridge converts normalized finger coordinates once into logical
   SDL-window coordinates and retains the last value.
3. `VM_M_getmousepos` converts logical coordinates into the engine console
   coordinate space with
   `logical * vid_con dimension / vid dimension`.
4. QC `getpointerpos()` calls that `getmousepos` builtin.
5. `m_draw()` assigns the returned vector to the QC global
   `ui_mouseposition`.
6. `UI_RenderElements()` compares `ui_mouseposition` with authentic element
   bounds, writes `ui_hover`, and the menu draws `gfx/cursor` at
   `ui_mouseposition`.
7. On `K_MOUSE1`, `UI_CheckClick()` performs the same authentic element-bound
   traversal using `ui_mouseposition`, writes `ui_selected`, and invokes the
   selected element's real `m_click` callback.

The R3 overlay called a value such as `(390,105)` a “menu VM writer” after a
logical value such as `(515,105)`. That was not a competing writer: it was the
expected logical-to-console conversion. The real defect was timing.

## Authoritative hit testing and click order

`Key_Event(K_MOUSE1)` runs during `Sys_SendKeyEvents`, before the next menu
draw. R3 applied the direct coordinate to `in_windowmouse_x/y`, but the QC
global `ui_mouseposition` still held the prior drawn position when
`UI_CheckClick()` ran. The stale center position selected Begin.

R4 writes the converted position to the authentic QC `ui_mouseposition`
global through `MR_WrathIOSApplyMenuPointer` before a pending mouse-button
phase can be consumed. The bridge marks a position generation applied only
after this write. Button down is therefore gated on the exact coordinate used
by `UI_CheckClick`; button up remains on a later frame. No item rectangles,
fake cursor, generic confirm event, or menu command substitution is used.

The persistent bridge value still feeds `VM_M_getmousepos` on every draw, so
hover and authentic cursor rendering use the same coordinate. The overlay
labels logical, engine, builtin, QC-global, draw, hover, selected, and click
sequence values separately.

## Authentic profile-field focus and keyboard

The pinned QC creates the New Profile editor as follows:

- `menu_current` is the active New Profile screen;
- `menu_current.partner` is the selectable/clickable field box;
- the field's `partner` is the visible authentic text entity;
- the field's `partner2` is the authentic Accept entity;
- `ui_selected == menu_current.partner` is the edit-focus condition;
- the screen's `option_input` consumes `K_TEXT`, Backspace, and other keys.

R3 also required the separately named `menu_createprofile` global. On device
that symbol was not discoverable, so the detector returned false despite a
valid active screen. R4 detects the source-defined active-screen structure and
focus state instead. It does not use artwork coordinates.

When that authentic field has focus, text input is requested on the UIKit main
thread. SDL text input is started, and a narrow project-owned hidden
`UITextField` becomes first responder because prior devices showed that
SDL's active flag alone did not present a keyboard under the custom
UIKit/`Host_Main` ownership model. The responder pushes Unicode as
`SDL_TEXTINPUT`, Backspace as SDL key events, and Done as Return. WRATH's
existing SDL decoder delivers `K_TEXT`/ASCII to the menu VM. The authentic
field remains the only visible editor.

The responder resigns and is removed on field/menu exit, gameplay, focus loss,
or backgrounding. The overlay reports structural detector values, backend,
first-responder result, text-event count, accepted character count, and the
last show/hide reason.

## Raw Core Motion diagnostic

The previously enabled landscape transform is known wrong: physical
forward/back tilt produced horizontal movement. R4 therefore samples Core
Motion for diagnostics but applies exactly zero gyro input to
`in_mouse_x/y`, including in gameplay.

Raw rotation-rate X/Y/Z, dominant axis, interface orientation, samples
ignored, and samples applied are visible at roughly 5 Hz in the menu. The
engine callback remains lightweight and no per-sample transcript is written.
Physical isolated yaw, pitch, and roll evidence in both landscape
orientations is required before a new transform is enabled.

Right-side swipe-look remains unchanged: the rightmost 65% produces relative
look deltas, the left 35% is reserved, finger-down only establishes an origin,
and gameplay touches never click or fire.

## Evidence boundary

CI proves source contracts, deterministic state tests, compilation, linkage,
and packaging. It cannot prove physical hit testing, keyboard presentation,
sensor axes, or lifecycle recovery. R4 is an evidence-producing partial
candidate until those device checks pass.
