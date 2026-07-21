# Gate 1 source inventory and compile manifest

## Scope

This gate records the disposition of every C translation unit referenced by the
official WRATH 1.1.2 `makefile` and `makefile.inc`. It does not link the engine,
create an OpenGL ES context, import game data, or claim runtime progress.

Canonical engine revision:

- repository: `Official3DRealms/wrath-darkplaces`
- commit: `f6862f628d6ddc133a9ef67bc4631b6137809772`
- release: `RELEASE_1.1.2`

## Result

The upstream build graph contains **117 recorded C translation units**.

- 93 upstream units are selected for the first arm64 iOS static-link experiment.
- 1 desktop system unit, `sys_sdl.c`, requires an iOS replacement.
- 1 x86-only SSE unit is excluded in favor of its generic implementation.
- 20 desktop, server, audio, CD, or platform backends are excluded.
- 2 video-capture units are disabled for first boot.

The machine-readable disposition of every unit is in:

- `config/engine/source_dispositions.json`

The exact selected upstream compile list is in:

- `config/engine/ios_upstream_sources.txt`

Run the structural validator with:

```sh
python3 scripts/validate_engine_manifest.py
```

Run the authoritative validation against the pinned upstream checkout with:

```sh
./scripts/fetch_upstream.sh
python3 scripts/validate_engine_manifest.py --require-upstream
```

## Key decisions

### UIKit owns process entry

`sys_sdl.c` is not part of the iOS compile list. It defines a desktop `main()`,
initializes terminal input, and exits the process directly. Gate 2 must replace
it with `Platform/Engine/sys_ios.mm`, started through the existing UIKit bridge.

The replacement must provide engine startup and shutdown, logging, fatal-error
reporting, sandbox path handoff, and SDL timing hooks without assuming stdin or
ownership of the application process.

### arm64 uses generic skeletal animation

`mod_skeletal_animatevertices_sse.c` is excluded. The selected graph retains
`mod_skeletal_animatevertices_generic.c`. No x86 or simulator convenience source
may enter the physical-device build merely because it silences a compiler error.

### Steam is disabled by upstream's own stub branch

`cl_steam.c` remains selected. At the pinned revision it compiles a built-in
no-Steam implementation when `steamlauncher/wrath_common.h` is absent. WrathiOS
must not add that proprietary launcher header or link Steamworks.

### Dynamic third-party loading is forbidden for Gate 2

Several selected files contain optional runtime-library loaders:

- `crypto.c`
- `ft2.c`
- `image_png.c`
- `jpeg.c`
- `libcurl.c`
- `snd_ogg.c`
- `sys_shared.c`

They remain in the source graph because other engine code references their
interfaces. Gate 2 must make non-system runtime loading deterministically fail
and must not package arbitrary dylibs. Static codec and font bindings are
deferred until a later gate demonstrates they are required.

### Filesystem and renderer need iOS adaptation

`fs.c`, `sys_shared.c`, and `vid_sdl.c` are selected but explicitly marked for
iOS adaptation. The required work includes:

- sandbox-owned base, user, configuration, save, and imported-data paths
- non-desktop quit and error semantics
- a no-dlopen policy for bundled third-party libraries
- UIKit lifecycle coordination
- drawable-size and foreground/background context recovery
- preservation and testing of the existing SDL/OpenGL ES 2 path

## Feature policy for first static link

Gate 2 uses these deliberate choices:

- `CONFIG_MENU=1`
- `USE_GLES2=1`
- CD audio disabled, selecting `cd_shared.c` and `cd_null.c`
- video capture disabled, excluding `cap_avi.c` and `cap_ogg.c`
- Steam integration absent
- no runtime-loaded third-party libraries

## Dependency provenance

Approved Gate 2 link inputs are:

- SDL 2.32.10 from `libsdl-org/SDL`, commit
  `5d249570393f7a37e037abf22cd6012a4cc56a71`
- zlib supplied by the selected Apple iOS SDK
- Apple system frameworks listed in `source_dispositions.json`

PNG, JPEG, FreeType, curl, Ogg/Vorbis/Theora, external crypto providers, ODE,
and Steamworks are not approved Gate 2 link inputs.

## Gate 1 pass conditions

Gate 1 passes only when CI demonstrates all of the following:

1. The pinned WRATH and SDL repositories can be fetched and verified.
2. Every upstream translation unit discovered from the pinned makefiles has
   exactly one recorded disposition.
3. The explicit compile list exactly matches the selected manifest entries.
4. Every selected upstream file exists.
5. The repository policy and UIKit shell build still pass.

Passing Gate 1 authorizes planning Gate 2. It does not prove that the engine
compiles, links, renders, or runs on an iPhone.
