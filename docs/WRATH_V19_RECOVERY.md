# WRATH v19 recovery checkpoint

2026-11-14. Recovered from exact published v18 048b0c42; prior uncommitted cloud v19 lost. No remote push or CI run yet.

Implemented locally:
- UIKit batched native typing; exact complete keyboard JSON receipt checks unchanged.
- Per-button resize in existing drag editor; old 2-number positions accepted, 3rd number scale persisted. Expanded real UIKit resize/relaunch/reset fixture.
- Optional desktop GL2.1 compatibility OSMesa/Zink adapter, GL function loading, CPU readback to Metal presenter. Actual runtime GL renderer/version gate; no GL version override or software fallback. Not yet iOS compiled or device tested.
- Exact donor Mesa/MoltenVK SHA manifests and notices; only library/notice members extracted; separate packaged hash and codesign evidence.
- Sequential GLES rollback then Zink workflow. Same slot/data identity; v19. Neither published nor run.
- Background frame gate and drain on resign active.

Local validation: source patch materialization pinned upstream passed; C++ native touch tests passed under MSVC; nested menu geometry tests and exact menu bytecode contract passed; Python compilation passed; git diff whitespace check passed.

Remaining BEFORE publication:
1. Coordinate-aware in-game HUD/text readability. Inspect csqc/hud.qc and menu renderer sizing. Auto HUD scale .5 at small conheight; blindly raising all HUD scale can clip. Do not claim native resolution composition or overwrite custom cvars.
2. Audit backend lifecycle/SDL interactions and new packaging scripts; macOS SDK compile only available in CI. Check all source contract references to old 'GLES context created' marker after rename.
3. Check no active remote build, commit/push existing review/gate5c-click-pairing branch via authorized arjunyerevan95-dot account, ONE run only after coherent combined candidate.
4. Device tests for real rendering, artifact selection/gyro, profile/save load, drag/resize persistence and readability. No success/performance claim beforehand.

Paths private outside repo must remain private. Do not copy retail game data or logs. No phone use by this worker.

## Readability implementation follow-up
Zink scene buffers now use 2x UIKit-point dimensions. The original menu computes console dimensions as half scene resolution, which otherwise shrinks text when scene resolution rises. A pure C helper recognizes only that stock dimension pair and retains its previous logical point-space size; custom pairs and explicit wrathios_readable_ui=0 are untouched. Engine menu and CSQC paths share the helper. Native menu pointer already maps normalized touch to vid_conwidth/height, so hit coordinates follow the same logical space. SDL resize notifications cannot overwrite the Zink buffer dimensions with UIKit points. Test covers physical text size, idempotence, custom dimensions and opt-out. This is higher-resolution scene/UI rendering, NOT separate native-resolution HUD composition, and can increase GPU/readback cost. GLES rollback retains old scene density.

Full repository checks pass on Windows; MSVC touch and readability tests pass. Actual UIKit/iOS build remains CI-only and phone results unverified.
