# WrathiOS porting plan

## Governing objective

Produce a signed, sideloadable iOS application that runs WRATH: Aeon of Ruin using game data imported from the user's own licensed installation. Public source and build artifacts must not contain commercial WRATH data.

## Canonical source baseline

The first supported engine baseline is official WRATH 1.1.2:

- `Official3DRealms/wrath-darkplaces`
- commit `f6862f628d6ddc133a9ef67bc4631b6137809772`

The matching released QuakeC source reference is:

- `Official3DRealms/wrath-qc`
- commit `bf7f46792ed3ed018a3d30bf6ca773900d816de1`

Every experiment must record any deviation from these revisions. Branch names such as `main` or `master` are not reproducible inputs.

## Platform policy

Initial supported platform:

- iOS 16.3 or newer
- arm64 physical devices
- iPhone and iPad
- landscape orientation
- sideloaded development builds before any distribution discussion

The simulator is a compile-time smoke target only. Runtime acceptance requires physical-device evidence.

## Rendering policy

The first renderer experiment will preserve the upstream OpenGL/OpenGL ES architecture and investigate the existing `USE_GLES2` path. A Metal rewrite is explicitly out of scope until the engine can render deterministic diagnostic output and load a WRATH map on-device.

The old `DPiOS.xcodeproj` is evidence and reference material, not the build system. It targets obsolete iOS, armv7, old SDL archives, and Steel Storm configuration.

## Current execution status

- Gate 0: passed
- Gate 1: passed and merged
- Gate 2: passed and merged at repository commit `fed2c72d0fb7497869f5c547d3e4d13b456c719d`
- Gate 2 device evidence: unsigned diagnostic IPA launched on a physical iPhone, displayed the pinned WRATH engine revision, and remained stable with runtime startup intentionally disabled
- Gate 3: passed and merged at repository commit `2fc304e572f1c4f2af733437b99bd6d69651917b`
- Gate 3 device evidence: SDL2/OpenGL ES 2 rendered at native `956 × 440` points and `2868 × 1320` pixels, respected the device safe area, survived foreground recovery, and created the context across three launches
- Gate 4: passed and merged at repository commit `f647cdf7b6c961afc634f70f56329a14d99d7276`
- Gate 4 device evidence: the user's approximately 1.5 GiB licensed installation imported, passed post-copy validation, persisted across relaunch, and was safely removed
- Active work: Gate 5A controlled runtime bootstrap to the authentic WRATH menu
- Blocked: Gates 6 through 8 until Gate 5 physical-device acceptance is complete

The active Gate 5A work may call `Host_Main`, mount the sandboxed import, render the authentic menu, test upstream menu touch input, and observe authentic audio startup. It must not begin gameplay or final control work.

## Milestone gates

### Gate 0: repository bootstrap

Pass conditions:

- modern iOS shell builds in CI
- exact upstream revisions are pinned
- proprietary-data exclusion is documented and enforced
- no upstream engine code has been modified without provenance

Stop condition: do not begin bulk source adaptation if the shell or source pins are not reproducible.

### Gate 1: source inventory and compile manifest

Produce an explicit iOS source manifest from upstream `makefile.inc`. Classify each source file as:

- portable and included
- replaced by iOS implementation
- excluded desktop backend
- architecture-specific replacement required
- optional feature disabled for first boot

Initial known exclusions or replacements include x86 SSE code, Steam integration, desktop dynamic loading, desktop video capture, CD audio, and unsupported platform backends.

Pass condition: every engine translation unit has a recorded disposition and every linked library has an iOS provenance.

### Gate 2: engine static-link smoke

Compile and statically link the engine into the iOS application without proprietary game data.

Pass conditions:

- arm64 device binary links
- no non-system dynamic dependencies
- startup reaches a controlled engine diagnostic or expected missing-data state
- device log identifies the pinned upstream revision

Status: passed in CI and on a physical device. The device diagnostic displayed the pinned engine build string without starting the runtime.

Stop condition: no renderer debugging until the static-link inventory is clean.

### Gate 3: graphics-context diagnostic

Create an SDL2-backed OpenGL ES context and render deterministic diagnostic output.

Pass conditions:

- context creation survives repeated launch
- foreground/background recovery works
- drawable size and safe-area handling are correct
- no game data is needed

Status: passed in CI and on a physical device. The diagnostic rendered at the native landscape drawable, respected safe-area insets, survived foreground recovery, and created the context on three launches.

Stop condition: do not begin Gate 4 until all Gate 3 physical-device criteria pass.

### Gate 4: licensed-data importer

Implement document-picker import from a user-selected WRATH installation directory or its `kp1` directory. Copy validated files into the app sandbox.

Current implementation scope:

- security-scoped folder selection
- loose-file plus PK3/Quake PAK index validation
- required `progs.dat`, `csprogs.dat`, and `menu.dat` sentinels
- traversal, malformed-package, symlink, and import-size rejection
- staged copy, post-copy validation, atomic replacement, rollback, and local manifest
- relaunch validation and sandboxed-copy removal

Status: passed in CI and on a physical device, then merged at `f647cdf7b6c961afc634f70f56329a14d99d7276`.

Pass conditions:

- import contains no hard-coded user paths
- validation uses documented sentinel files and compatibility profile
- failures explain missing or incompatible files
- imported data never enters Git or public CI artifacts
- a licensed installation imports successfully on a physical device
- a relaunch validates the installed copy without reselecting the source
- removal deletes only the app's sandboxed copy

Stop condition: do not begin Gate 5, mount imported packages, or call `Host_Main` until Gate 4 physical-device acceptance is recorded.

### Gate 5: WRATH menu

Reach the real WRATH main menu with readable rendering, audio initialization, and touch menu navigation.

### Gate 6: gameplay

Load a new game and demonstrate world rendering, movement, aiming, primary attack, audio, and pause/resume on a physical device.

### Gate 7: mobile controls and persistence

Add configurable touch controls, gyroscope aiming, controller support, save persistence, and robust lifecycle restoration.

### Gate 8: packaging

Produce a signed IPA containing only redistributable code and original port resources. Verify the bundle inventory before publishing any artifact.

## Evidence rules

A gate is not complete because compilation succeeded once. Record:

- exact commit
- Xcode and iOS SDK version
- target device and OS version
- complete build command
- relevant logs
- binary dependency inventory
- screenshots or video for visual runtime gates

Direct command output and reproducible artifacts outrank narrative summaries.
