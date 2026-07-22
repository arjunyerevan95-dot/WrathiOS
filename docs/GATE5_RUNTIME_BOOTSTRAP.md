# Gate 5A controlled runtime bootstrap

## Upstream ownership evidence

The runtime remains pinned to `Official3DRealms/wrath-darkplaces` commit
`f6862f628d6ddc133a9ef67bc4631b6137809772` (`RELEASE_1.1.2`). At that revision:

- `Host_Main` is declared as `void Host_Main(void)` in `quakedef.h` and defined
  in `host.c`.
- `Host_Main` calls the file-local `Host_Init`, then owns an unconditional
  frame loop. There is no exported `Host_Frame` API. The loop performs SDL
  event polling through `Sys_SendKeyEvents`, client/server work, rendering,
  sound updates, and frame pacing.
- the desktop `sys_sdl.c` populates `com_argc`/`com_argv`, calls `SDL_Init(0)`,
  then calls `Host_Main`. Gate 1 correctly excluded that desktop `main` and
  terminal lifecycle in favor of an iOS system backend.
- `FS_Init` honors `-basedir` and an explicit `-userdir`. `-wrath` selects
  `GAME_WRATH`, whose base game directory is `kp1`; a separate `-game kp1` is
  neither needed nor supplied.
- `VID_Init` initializes SDL video. `Host_StartVideo`, reached by the authentic
  menu toggle path, creates the SDL window and OpenGL ES context and starts
  sound. `MR_Init` loads the QuakeC `menu.dat`; the first `MP_Draw` call is the
  earliest source-supported evidence that the genuine menu VM drew a frame.
- early `Host_Error` paths escalate to `Sys_Error`. Upstream `Sys_Error` and
  `Sys_Quit` terminate a desktop process after shutdown.

## Chosen iOS runtime model

Gate 5 keeps UIKit launch ownership and starts WRATH only from the explicit
`Launch WRATH` action. It runs the authentic `Host_Main` loop on the main
thread, with `SDL_iPhoneSetEventPump(SDL_TRUE)` active for the duration.

This is the source-supported SDL 2.32.10 iOS ownership model: the pinned
`SDLUIKitDelegate` schedules its application entry point on the main thread,
enables the iPhone event pump, and relies on SDL event polling to service the
UIKit run loop. It also keeps SDL window creation and the OpenGL ES context on
the main thread. Running `Host_Main` on a worker would instead move UIKit video
work and GL ownership away from SDL's own iOS model. Splitting the monolithic
host loop into a new public frame API would be a broader upstream rewrite.

UIKit lifecycle notifications can therefore be delivered while WRATH polls
SDL events. SDL window events remain the authoritative input to the upstream
`vid_hidden`/focus behavior. Gate 5 records the corresponding UIKit lifecycle
frontiers but does not claim physical background recovery until device proof
exists.

## Filesystem contract

Gate 4 remains authoritative for the installed location. Gate 5 derives paths
only from `WrathDataImporter.installedKP1URL`:

- read-only data root argument: the parent of the installed `kp1` URL via
  `-basedir`;
- game selection: `-wrath`, which selects the upstream `kp1` base game;
- writable root argument: `Application Support/WrathiOS/Runtime/UserData` via
  `-userdir`;
- startup transcript: `Application Support/WrathiOS/Runtime/last-startup.json`.

The original security-scoped source is never reopened. Generated configuration,
saves, logs, and screenshots resolve through the separate user directory rather
than modifying imported package data. Private absolute paths are used only as
engine arguments inside the process and are replaced with `<private-path>` in
diagnostics.

## Error and evidence boundary

The iOS `Sys_Error` replacement records a sanitized fatal message, performs the
upstream shutdown, and returns control to the launcher through a same-thread
`setjmp`/`longjmp` boundary around `Host_Main`. The Gate 5-only `Sys_Quit`
adaptation uses the same boundary instead of `exit`. This is intentionally
narrow: a second engine startup in the same process is refused because upstream
global shutdown state is not designed for reinitialization.

Stage hooks are provenance-checked derived-source substitutions. They do not
change runtime decisions. The persisted transcript contains ordered stage names
and sanitized details only; filtered engine output is sent to Apple unified
logging and is not persisted. Archive/map/texture/sound names are excluded from
that forwarding.

## Menu input experiment

The Gate 5 engine flavor defines upstream `DP_MOBILETOUCH`. The existing
`vid_sdl.c` touch path maps menu touches to pointer motion and `K_MOUSE1` through
the engine's own touchscreen cursor area. This is the minimum menu-responsiveness
experiment and is not a final gameplay control layout.
