# Gate 5B Revision 3 runtime-observable input architecture

## Why Revision 2 was insufficient

Revision 2 proved only that project symbols were present. Physical hardware
showed that WRATH's authentic cursor still returned to a center-ish coordinate,
every initial tap activated Begin, SDL text-input activation did not display a
keyboard, and the candidate gyro mapping was wrong.

The missing boundary was the menu VM builtin `getmousepos()`. WRATH QC copies
that result into `ui_mouseposition` every draw, recomputes `ui_hover`, and
routes `K_MOUSE1` through the resulting selected element. Writing only
`in_windowmouse_x/y` was therefore insufficient evidence of the coordinate
actually consumed by the menu VM.

## Cursor ownership and ordering

The Gate 5B bridge retains the latest direct-touch coordinate in logical video
space. The R3 derived `VM_M_getmousepos` path returns that persistent coordinate
directly, converted once with the authentic engine formula:

`virtual = logical * vid_con dimension / vid dimension`

The old one-shot path remains absent. SDL touch-to-mouse synthesis and the
legacy touchscreen mouse-area path remain bypassed. The touchscreen video
center initializer remains disabled under `WRATH_IOS_GATE5B`.

Runtime instrumentation records:

- finger receipt and stored logical coordinate;
- application to `in_windowmouse_x/y`;
- final lower-level coordinate and last writer;
- coordinate returned by `VM_M_getmousepos`;
- menu VM `ui_mouseposition`, `ui_hover`, and `ui_selected`;
- position-wait, button-down, and button-up sequence numbers.

The click state machine still requires a new position to be applied and drawn
before down, with up on a later frame. CI tests this deterministic state
machine, but device evidence is authoritative.

## Profile text and UIKit fallback

The detector reads the authentic menu VM's `menu_current`,
`menu_createprofile`, `ui_selected`, `ui_hover`, `ui_mouseposition`, and the
profile field reached through `partner`. The overlay shows the sanitized
numeric identifiers and detector result.

R3 still calls SDL text input and displays `SDL_IsTextInputActive()`. Repeated
hardware evidence showed that this flag did not create a usable responder
under the custom UIKit/`Host_Main` launch architecture, so R3 also creates one
project-owned, nearly invisible `UITextField` only while the authentic profile
field is selected. It becomes first responder on the UIKit main thread and
pushes:

- Unicode through `SDL_TEXTINPUT`;
- Backspace through SDL key down/up;
- Done through Return down/up.

WRATH's existing SDL event decoder then sends authentic `K_TEXT` and key events
to the menu VM. The fallback neither draws a profile form nor owns profile
text. It resigns and is removed on field/menu exit, gameplay, focus loss, or
backgrounding.

## Pre-gameplay Core Motion diagnosis

Core Motion sampling now starts with the runtime rather than waiting for
gameplay. A 5 Hz overlay shows raw rotation-rate X/Y/Z, physical landscape
orientation, and the current candidate yaw/pitch mapping. The 120 Hz callback
does not write high-frequency logs.

Sampling and applying are separate. In menu and menu-text modes, samples update
diagnostics only: the gyro accumulator is cleared and no value is injected
into `in_mouse_x/y`. Counters distinguish samples observed, menu samples
ignored, and gameplay samples applied.

The existing axis transform is deliberately labeled unverified. Physical
isolated-axis evidence must be returned before another mapping is accepted.

## Preserved boundaries

Gameplay right-side swipe-look remains unchanged and no movement or firing
controls were added. The renderer, audio, filesystem, runtime ownership,
engine/QC pins, dependency pins, bundle identifier, and imported app container
remain unchanged.

CI proves compilation, deterministic state tests, markers, framework linkage,
and artifact audits. It cannot prove cursor persistence, keyboard visibility,
physical gyro axes, stationary drift, or lifecycle recovery.
