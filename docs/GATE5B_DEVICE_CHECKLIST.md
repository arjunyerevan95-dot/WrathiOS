# Gate 5B Revision 4 physical-device checklist

Install `WrathiOSGate5B-v10-unsigned.ipa` over the current app. Do not
uninstall or reimport data. CI confirms only that the diagnostic and packaging
contracts compiled; pointer, keyboard, and physical sensor behavior remain
device-unverified.

## Build provenance

1. Confirm the launcher says **Gate 5B Revision 4**, **0.0.10 (10)**, shows a
   branch-head marker, and shows `gate5b-r4-input-contract-v1`.

## Menu pointer and hit target

2. Launch WRATH and confirm the diagnostic overlay appears.
3. Tap **Options** directly.
4. Capture the overlay values for stored logical, engine logical, menu builtin,
   QC mouse/draw, hover, selected, last writer, and click sequence.
5. Confirm Options opens rather than Begin.
6. Drag the authentic cursor elsewhere and wait ten seconds.
7. Confirm the cursor stays at its last position and does not snap back.
8. Return and tap **Begin** directly.

## Profile text

9. On New Profile, tap the authentic field.
10. Capture profile-screen, field/text/Accept identifiers, focus detector,
    SDL-active, first-responder, backend, event count, and keyboard reason.
11. Confirm the native keyboard appears.
12. Enter a short name containing letters and numbers.
13. Test Backspace.
14. Dismiss with Done if desired, tap the authentic Accept item, and confirm
    profile creation proceeds.

## Raw gyro axes

15. Without requiring gameplay, hold the phone still and note raw X/Y/Z,
    dominant axis, and landscape orientation.
16. Rotate left/right as if steering; report dominant raw axis and signs.
17. Tilt the top edge forward/back; report dominant raw axis and signs.
18. Roll clockwise/counterclockwise around the screen normal; report dominant
    raw axis and signs.
19. Repeat in the other landscape orientation if practical.
20. Confirm the authentic menu cursor does not move during any motion.
21. Confirm the overlay says
    `mapping=disabled-awaiting-device-axes` and gameplay-applied remains zero.

## Gameplay swipe and lifecycle

22. Only if profile creation succeeds, enter the first scene.
23. Test right-side horizontal and vertical swipe-look, hold still, then lift
    and retouch; confirm there is no jump.
24. Confirm the left 35% does not aim. Do not assess gyro aiming in this build.
25. Background for three seconds and return.
26. Confirm no keyboard, click, swipe, or motion state is stuck; note GL,
    animation, and audio behavior.

Do not test movement, combat, firing, or other controls.
