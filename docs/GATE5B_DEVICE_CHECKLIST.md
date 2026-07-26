# Gate 5B Revision 3 physical-device checklist

Install `WrathiOSGate5B-v9-unsigned.ipa` over the current app. Do not uninstall
or reimport data. CI proves that the diagnostic code and packaging contracts
compiled; it does not prove cursor, keyboard, or gyro behavior on hardware.

## Launcher provenance

1. Confirm the launcher visibly says **Gate 5B Revision 3**, **0.0.9 (9)**,
   shows a branch-head marker, and shows
   `gate5b-r3-input-contract-v1`.

## Runtime cursor trace

2. Launch WRATH and confirm the noninteractive diagnostic overlay appears.
3. Tap **Options** directly.
4. Capture or transcribe the overlay values for:
   stored touch, applied cursor, final cursor, VM cursor, final writer,
   menu/selected/hover identifiers, and the position-wait/down/up sequences.
5. Confirm whether Options or Begin activates.
6. Wait ten seconds. If the cursor moves, capture the final writer and writer
   generation after the movement.
7. Drag to several positions and report whether the authentic cursor follows
   and remains at the last position.

## Profile keyboard

8. Open **New Profile** and tap the authentic name field.
9. Capture detector, text-requested, SDL-active, responder, keyboard backend,
   selected/hover, and field identifiers.
10. If the keyboard appears, enter a short letters/numbers name, test
    Backspace, and press Done. Confirm the authentic WRATH field changes.

## Pre-gameplay raw gyro axes

11. While still in the menu/profile screen, hold the phone still and capture
    raw X/Y/Z plus candidate yaw/pitch.
12. Perform each motion separately and report the dominant signed raw axis:
    steering-like left/right rotation, top-edge forward/back tilt, and
    clockwise/counterclockwise roll.
13. Repeat in the other landscape orientation if practical.
14. Confirm the authentic menu cursor does not move during any gyro motion.

## Lifecycle

15. Background for three seconds and return.
16. Confirm no button is held, the keyboard is not stuck, and no gyro motion
    moves the menu cursor.
17. Note GL, animation, and audio behavior.

Gameplay is optional only if profile creation succeeds. Do not test movement,
combat, or other controls in this diagnostic pass.
