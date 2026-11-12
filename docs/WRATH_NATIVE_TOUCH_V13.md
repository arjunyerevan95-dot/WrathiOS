# WRATH v13 input candidate

Physical validation pending. Same bundle ID; no game-data changes.

Fixes: removed gameplay-reset caused by menu HUD rendering; corrected QC nested STRETCH click scale; added profile iOS keyboard using compiled field names and authentic validation; added menu cursor stick plus virtual A Accept/B Back; audited all 34 game controls and exposed missing actions in a compact tray.

Movement remains left stick, look right swipe/gyro, primary buttons fire/alt/jump/crouch/use. Actions include all weapons, cycling, artifacts/tether, journal/inventory, zoom/walk/swim and load. Held actions have matched release identifiers. Captured CSQC UI retains held inventory ownership, disables gyro, uses right swipe as cursor and Fire as Accept.

Device test: load existing save with cursor+A; create profile with keyboard; persistent gameplay overlay; move/look/fire together; crouch/use; weapons/artifacts; journal/inventory cursor+Accept; landscape rotation and resume. Do not uninstall or reimport.

Menu program rebuilt locally with pinned compiler, source patch, repeat-build, same-compiler baseline and interpreter opcode checks. See Resources README.

## Final requested layout
Compact upper-right 3x3 cluster: alt/fire/jump, use/crouch/next weapon, radial actions/previous weapon/settings. Floating movement at left; lower-right deliberately clear for true relative swipe-look. Menu controls are separate. Radial actions expose inventory, journal, artifact use/cycle, tether, load, zoom and More; More exposes the rest of the audited set. Persistent settings adjust swipe sensitivity, gyro strength (zero disables), button scale and opacity. Physical usability is pending device feedback.
