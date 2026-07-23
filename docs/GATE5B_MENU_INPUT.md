# Gate 5B direct menu touch and gameplay look input

## Reassessment

The first Gate 5B candidate correctly disabled SDL's synthesized touch mouse and
stopped cursor drift, but it replaced one desktop abstraction with another: the
entire screen became a relative laptop-style touchpad. A tap emitted
`K_MOUSE1` at the old engine cursor instead of selecting the visible location.
Gameplay remained on WRATH's upstream fixed 128 by 128 bottom-right virtual aim
pad, which explains why swipes were accepted only in limited regions.

The revised build removes the project-authored relative menu pointer and bypasses
the complete upstream Quake touchscreen-area layout under `WRATH_IOS_GATE5B`.
SDL touch-to-mouse synthesis remains disabled. One project-owned
`WrathIOSInputBridge` now selects menu, gameplay, or other behavior explicitly.

## Engine-state boundary

- Menu mode requires no active console and `key_dest` equal to `key_menu` or
  `key_menu_grabbed`.
- Gameplay mode requires no active console, `key_dest == key_game`, a connected
  client with `cls.signon == SIGNONS`, no intermission, no CSQC mouse request,
  and no Prydon cursor.
- Console, chat, loading/sign-on, intermission, CSQC cursor, and all other
  states select other mode.

Every transition clears the primary finger, previous coordinate, drag state,
pending swipe delta, and gyro accumulator. A touch begun in one mode cannot
continue in another.

## Direct menu touch

SDL reports normalized finger coordinates. The bridge clamps them and converts
them once into the current logical SDL window:

`logical = normalized * (logical dimension - 1)`

The engine patch assigns that result to `in_windowmouse_x/y`. The authentic menu
VM already performs the only logical-to-virtual conversion in
`mvm_cmds.c`:

`virtual = logical * vid_con dimension / vid dimension`

No 3x drawable-pixel scale is used. The verified 956 by 440 logical window and
2868 by 1320 drawable therefore do not require device-specific constants.

Finger-down places the authentic cursor under the finger. Dragging tracks the
finger absolutely. Motion above 1.2 percent of the shorter logical dimension is
a drag and does not click on release. A tap queues one `K_MOUSE1` down after the
absolute position update; the following engine input frame emits the release.
Additional fingers are ignored.

## Gameplay swipe-look

Gameplay accepts one aim finger only when it begins at normalized X >= 0.35,
the rightmost 65 percent of the logical surface. The left 35 percent is reserved
for later movement work and has no effect in this milestone.

Finger-down stores an origin without producing motion. Each finger-motion event
is differenced from the preceding normalized position and converted once using
the current logical dimensions. Experimental multipliers are 2.0 horizontally
and 1.65 vertically. Deltas accumulate until `IN_Move_TouchScreen_Quake` calls
`WrathIOSInputConsumeGameplayLook`; they are then assigned to `in_mouse_x/y`.

This is WRATH's authentic mouse-look boundary. Existing `CL_Input` continues to
own sensitivity, acceleration, filtering, inversion, view zoom, pitch drift,
and final pitch clamps. No frame-time multiplier is added to swipe displacement.
Aim gestures never emit a mouse button, click, or fire action.

## Gyroscope

`CMMotionManager` supplies fused `CMDeviceMotion.rotationRate` samples at a
requested 120 Hz. The callback performs only orientation mapping, a 0.015
radian/second per-axis dead zone, timestamp integration, and a locked
accumulation. The engine input frame consumes and clears that accumulation.

Core Motion uses portrait-natural device axes, so the bridge maps them into
screen-relative yaw and pitch:

| Interface orientation | Screen yaw rate | Screen pitch rate |
| --- | --- | --- |
| Landscape left | `device x` | `-device y` |
| Landscape right | `-device x` | `device y` |

Device Z rotation (roll) is ignored. Integrated radians are converted at the
experimental rate of 900 WRATH mouse units per radian and added to the same
`in_mouse_x/y` frame delta as swipe input. This intentionally preserves WRATH's
downstream look behavior rather than fabricating an XInput controller.

Motion starts only in gameplay mode. It stops and discards pending samples in
menus, other engine states, focus loss, and backgrounding. Entering gameplay,
changing orientation, foregrounding, or resuming motion establishes a fresh
timestamp baseline so suspended samples cannot become a camera jump.

## Evidence boundary

Bounded instrumentation reports menu, aim, gyro, mode-transition, and lifecycle
counters without raw coordinates. CI proves source selection, deterministic
coordinate formulas, both landscape mappings, symbol linkage, Core Motion
linkage, packaging, and regression checks. Only a physical device can establish
touch feel, gyro signs, negligible stationary drift, and lifecycle recovery.
