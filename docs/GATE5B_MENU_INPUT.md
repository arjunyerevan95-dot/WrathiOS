# Gate 5B deterministic menu touch input

## Source path and root cause

At the pinned WRATH revision, SDL UIKit reports each contact as normalized
`SDL_FINGERDOWN`, `SDL_FINGERMOTION`, and `SDL_FINGERUP` events. The SDL 2.32.10
default also synthesizes an absolute `SDL_TOUCH_MOUSEID` mouse stream from the
same primary finger.

Gate 5A enabled `DP_MOBILETOUCH` and `vid_touchscreen`. Its `vid_sdl.c` path
therefore did all of the following at once:

1. stored the normalized finger stream in `multitouch`;
2. read SDL's synthesized absolute position through `SDL_GetMouseState` into a
   second, special `multitouch` slot;
3. drove the Quake-style menu touch area from those entries; and
4. assigned the absolute mouse position to `in_windowmouse_x/y` only while the
   menu touch button area was active.

That mixed two ownership models. A new contact could replace the engine-owned
cursor with an unrelated absolute finger coordinate. Small contact jitter kept
rewriting the position, and touch-area eligibility controlled whether the
rewrite happened at all. The synthetic special slot also used the upstream
`x * 32768 / vid.width` conversion even though `VID_TouchscreenArea` expects a
normalized 0–1 value. These facts account for the observed anchoring,
discontinuity, and drift. The high-density 3x drawable is not the cause: SDL
touch coordinates and `in_windowmouse_x/y` both use logical window dimensions.

The authentic menu VM reads `in_windowmouse_x/y`, converting once from logical
window coordinates into `vid_conwidth/vid_conheight` menu coordinates. That is
the stable ownership boundary retained by Gate 5B.

## Chosen model

Gate 5B uses one relative touchpad path, scoped by `WRATH_IOS_GATE5B`:

- `SDL_HINT_TOUCH_MOUSE_EVENTS=0` is set with override priority before SDL
  initializes, so the UIKit finger does not also become a mouse.
- The first finger down while `key_dest == key_menu` records only a normalized
  origin. It never changes the cursor.
- Matching finger motion is differenced from the previous normalized position,
  converted once using the current logical `vid.width` and `vid.height`, and
  added to the engine-owned cursor. Sensitivity is 1.0. The engine cursor is
  clamped to the logical window.
- Additional fingers are ignored until the controlling finger is released.
- Movement accumulating to 1.8% of the shorter logical window dimension marks
  a drag. On the verified 956 x 440 surface the threshold is 7.92 logical
  points. A drag never clicks.
- Finger up below that threshold emits one `K_MOUSE1` down. The next
  `Sys_SendKeyEvents` call emits its release, giving the menu VM a full engine
  frame in which to observe the pressed state.
- The legacy Quake menu touch-area/mouse-state path returns early for
  `key_menu`, so absolute and relative behavior cannot combine.

This is intentionally menu-only. The existing upstream game touch layout is
unchanged and is not a Gate 5B acceptance surface.

## Lifecycle and evidence boundary

Finger, drag, and button state is cleared on finger up, UIKit focus loss,
backgrounding, SDL window hide, and SDL focus loss. The background reset
releases any pending mouse button before suspension. A foreground marker is
armed from UIKit and recorded at the next engine input/frame boundary; it proves
only that one frame boundary was reached after return, not full lifecycle
support.

Instrumentation records bounded stage/counter summaries for touch begin, first
relative motion, drag threshold, emitted tap, reset, background reset, return to
foreground, and first foreground frame. Gesture logging has a 32-stage budget,
and the persisted runtime transcript retains at most 128 entries. No touch
coordinates or private paths are recorded.
