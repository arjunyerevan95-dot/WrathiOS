# Gate 3 graphics-context diagnostic

## Scope

Gate 3 proves that the statically linked iOS application can create and maintain an SDL2-backed OpenGL ES 2 context without commercial WRATH data.

It does not:

- call `Host_Main`
- initialize the WRATH filesystem
- import game data
- render WRATH assets or menus
- begin gameplay or controls work

## Diagnostic design

The UIKit bootstrap remains the application owner. SDL2main is disabled in the static SDL build. The Gate 3 entry point defines `SDL_MAIN_HANDLED`, includes `SDL_main.h`, and calls `SDL_SetMainReady()` before `UIApplicationMain` so SDL accepts the custom UIKit-owned entry point without renaming `main`.

After the bootstrap view becomes visible, the diagnostic:

1. initializes SDL video and events;
2. requests an OpenGL ES 2 context with an RGBA8 double-buffered drawable;
3. creates SDL's single fullscreen high-DPI iOS window;
4. obtains SDL's native UIKit window and framebuffer through `SDL_GetWindowWMInfo`;
5. compiles a minimal project-authored shader pair;
6. renders a deterministic RGB triangle over a pulsing dark background;
7. overlays live context, renderer, drawable, safe-area, frame, launch, and foreground-recovery metadata;
8. pauses on background entry and validates the existing context before resuming.

No proprietary files are read or copied.

## Physical-device finding and correction

The first device build reached the UIKit bootstrap but failed at `SDL_Init` with:

`Application didn't initialize properly, did you include SDL_main.h in the file containing your main() function?`

The pinned SDL 2.32.10 source initializes its main-readiness flag to false on iOS when SDL owns the conventional entry-point path. Because WrathiOS deliberately keeps its own `UIApplicationMain`, it must call `SDL_SetMainReady()` before initializing SDL.

Including `SDL_main.h` alone is insufficient because it renames `main` to `SDL_main` on iOS. The corrected entry point therefore uses both parts of SDL's documented custom-main contract:

- define `SDL_MAIN_HANDLED` before including `SDL_main.h`;
- call `SDL_SetMainReady()` before `UIApplicationMain`.

Corrected branch commit:

`c154f4f023c80838f5278f1ffb96d3b7f8458b10`

GitHub Actions run 74 passed every enforced compile, link, audit, and packaging step for that commit.

Corrected unsigned IPA SHA-256:

`772397022236e9e7d5db487bd61e030ea47c688a976c42d676345292d541a5ba`

## CI acceptance

CI must confirm:

- Gate 1 and Gate 2 regressions remain green;
- all 93 WRATH engine units still compile for arm64 iPhoneOS;
- the engine and dependency archives remain arm64 and statically linked;
- the unchanged simulator shell remains free of an SDL entry-point dependency;
- the Gate 3 device target links as a monolithic arm64 executable with a real `_main`;
- `Host_Main`, `SDL_GL_CreateContext`, `SDL_SetMainReady`, the WRATH build string, and the Gate 3 entry point are present;
- no non-system dynamic dependencies are introduced;
- no commercial-style game archive appears in the application bundle;
- a valid unsigned IPA is produced for external signing.

## Physical-device acceptance

Gate 3 passes only after evidence shows:

- the RGB triangle and diagnostic panel render on a physical device;
- the SDL driver, GL renderer, GL version, and non-zero drawable dimensions are visible;
- the panel respects the safe area in landscape;
- backgrounding and returning leaves rendering active and increments the recovery counter;
- at least three separate launches create the context successfully and increment the persisted launch counter.

## Stop condition

Do not begin licensed-data import, WRATH menu startup, renderer adaptation inside the engine, touch controls, or gameplay until the physical-device Gate 3 acceptance evidence is recorded.
