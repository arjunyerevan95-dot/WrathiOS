# WrathiOS

WrathiOS is an experimental, community-developed iOS port of **WRATH: Aeon of Ruin**.

This repository contains porting code, build infrastructure, documentation, and open-source engine material permitted by its upstream license. It does **not** contain WRATH's proprietary game data. A legitimate copy of the game is required to run the eventual port.

## Current milestone

Gates 0 through 4 have passed. Gate 5A is a controlled physical-device experiment that starts the authentic WRATH runtime from an explicit launcher action and records the exact startup frontier on the way to the real main menu.

Established foundations include:

- iOS 16.3+ UIKit application shell for iPhone and iPad
- arm64 device requirement
- landscape-only presentation
- SDL2-backed OpenGL ES 2 device rendering
- validated import and persistence of user-owned licensed `kp1` data
- controlled runtime stages, sanitized local diagnostics, and separate writable state
- exact upstream engine and QuakeC revision pins
- scripts to fetch and verify upstream source without silently following a moving branch
- CI smoke build generated with XcodeGen
- explicit prohibition on committing commercial game data

The engine and dependencies are statically linked in the Gate 5 device target. CI cannot establish that the authentic menu renders; that remains a physical-device acceptance result.

## Canonical upstream revisions

Engine:

- Repository: `Official3DRealms/wrath-darkplaces`
- Revision: `f6862f628d6ddc133a9ef67bc4631b6137809772`
- Release: `RELEASE_1.1.2`

QuakeC/game-code reference:

- Repository: `Official3DRealms/wrath-qc`
- Revision: `bf7f46792ed3ed018a3d30bf6ca773900d816de1`
- Release: `RELEASE_1.1.2`

The pins are defined in `scripts/upstream.env`.

## Generate the Xcode project

Install [XcodeGen](https://github.com/yonaskolb/XcodeGen), then run:

```sh
./scripts/generate_project.sh
open WrathiOS.xcodeproj
```

The project file is generated and intentionally not committed. `project.yml` is the source of truth.

## Fetch upstream source

```sh
./scripts/fetch_upstream.sh
./scripts/verify_upstream.sh
```

Fetched repositories live under `Vendor/` and are ignored by Git. This prevents accidental, unattributed source snapshots while the integration strategy is still being audited.

## Legal boundary

Never commit or distribute WRATH's commercial assets, including the user's `kp1` directory, archives, maps, textures, sounds, music, cinematics, or other data copied from Steam, GOG, or another licensed installation.

Public application artifacts must contain only redistributable code and original port assets. Users will later import required game data from their own licensed installation.

See `docs/ASSET_POLICY.md`.

## License

Port code is licensed under GPL-2.0-only unless an individual file states otherwise, matching the upstream engine's licensing requirements. See `COPYING`.
