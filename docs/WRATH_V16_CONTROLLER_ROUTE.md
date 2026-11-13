# v16 controller-path repair

v15 used command injection and a separate menu click adapter. Its UIKit harness
proved callbacks, not WRATH profile/save loading. It did not satisfy the requested
controller path.

v16 merges virtual controls into `vid_joystate_t` immediately before the pinned
`VID_ApplyJoyState`, the shared SDL GameController/Windows XInput path. It resolves
named actions against loaded controller bindings first, and retains the chosen key
until release even if a profile/remap changes. There are no binding writes.
Auxiliary radial actions absent from the controller preset resolve their existing
keyboard binding through normal `Key_Event`, not Cbuf command injection; unbound
actions log a diagnostic rather than invent a binding. Relative mouse aiming is
independent of Fire/Alt, including dragging the held button itself, as requested.

Menus use paired native Xbox A/B and the game's right-stick cursor semantics.
Manual `input_mode` changes, synthetic A-down/mouse-up, and parallel mouse clicks
are removed. Selecting an existing profile then Load follows authentic QC; the
first available save is selected by the game, and other save slots remain selectable.
No save data, compatibility rules or profile metadata is rewritten.

Verification:
- Repository/data/portable controls checks.
- Production route plus exact upstream VID_ApplyJoyState compiled and executed:
  held-trigger+look, movement, remap during hold, A/B pairs and short taps.
- Extracted actual upstream QC controller/profile/save/load handlers executed with
  fixtures. Not a complete VM/UI/file-loading test.
- UIKit test now drags held Fire and requires look while Fire is down, retaining
  keyboard and geometry tests.
- Device selection/load, physical controller coexistence, gyro, and actual gameplay
  remain mandatory on-phone acceptance. Do not claim them from callback counts.
