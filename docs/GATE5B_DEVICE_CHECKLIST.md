# Gate 5B Revision 2 physical-device checklist

Install `WrathiOSGate5B-v8-unsigned.ipa` over the current app. Do not uninstall
or reimport data.

## Menu

1. Launch WRATH and tap **Options** directly. Confirm Options—not Begin—opens.
2. Return and tap **Begin** directly.
3. Confirm the cursor remains at the last touched coordinate.
4. Wait ten seconds without touching; confirm it does not snap to center.
5. Drag the cursor to several positions and confirm it remains at the final
   position without a release click.

## Profile text

6. Open **New Profile** and select the authentic name field.
7. Confirm the standard landscape iOS keyboard appears.
8. Enter a short letters/numbers name, test Backspace, then use the authentic
   Accept control to proceed. WRATH QC does not permit spaces in this field.

## Gyro raw-axis diagnostic

9. Enter the first playable scene only to test camera input.
10. Read or screenshot the small `RAW x/y/z` and `BASELINE yaw/pitch` overlay.
11. Perform each motion separately and report the dominant signed raw axis:
    rotate left/right, tilt the top edge forward/back, and roll
    clockwise/counterclockwise.
12. If practical, repeat after rotating to the other supported landscape
    orientation. Do not interpret the v7 baseline labels as an accepted final
    mapping.

## Preserved swipe-look

13. On the rightmost 65 percent, touch without moving; confirm no camera jump.
14. Swipe horizontally and vertically, hold still, then lift and retouch.
15. Confirm the left reserved 35 percent does not aim and aim gestures do not
    click or fire.

## Lifecycle

16. Background the app for three seconds and return.
17. Confirm the keyboard is not stuck, no menu button is held, a new swipe is
    required, and no suspended gyro delta is applied.
18. Note GL, animation, audio, keyboard, touch, and motion behavior.

Return one menu screenshot, one keyboard screenshot, the raw-axis overlay
screenshots/values for the isolated motions, and a concise touch/swipe/lifecycle
description. Do not test movement or combat.
