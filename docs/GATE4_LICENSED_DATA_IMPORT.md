# Gate 4 licensed-data importer

## Scope

Gate 4 imports files from a user-selected licensed WRATH installation into the app sandbox. It does not start the WRATH engine, initialize the engine filesystem, render the menu, play audio, or begin controls/gameplay work.

The importer accepts either:

- the WRATH installation root containing `kp1`; or
- the `kp1` directory itself.

The official WRATH engine baseline defines `kp1` as the base game directory. The matching QC baseline produces three required runtime outputs:

- `progs.dat`
- `csprogs.dat`
- `menu.dat`

These files may be loose or contained within indexed PK3/Quake PAK packages.

## Compatibility profile

Gate 4 reports structural compatibility with:

`wrath-1.1.2-qc-layout-v1`

This profile is tied to:

- engine revision `f6862f628d6ddc133a9ef67bc4631b6137809772`
- QC revision `bf7f46792ed3ed018a3d30bf6ca773900d816de1`

The importer validates the required QC outputs and package structure. It does not claim a cryptographic identification of a particular retail depot because no authoritative public package hashes are available in the pinned source baseline.

## Validation rules

Before copying, and again after copying, the importer:

1. resolves the selected directory to a `kp1` root;
2. recursively enumerates regular files;
3. rejects symbolic links and unsafe relative paths;
4. limits imports to 64 GiB as a defensive bound;
5. validates PK3 central directories without extracting package contents;
6. validates Quake PAK headers and directories;
7. rejects encrypted, multi-volume, ZIP64, malformed, or traversal-bearing packages;
8. confirms `progs.dat`, `csprogs.dat`, and `menu.dat` are visible as loose files or package entries.

A missing BSP map is reported as a warning rather than a hard rejection because package layouts may vary.

## Import transaction

The app uses a folder document picker and security-scoped access. A compatible `kp1` tree is copied into a unique staging directory under Application Support, validated again, and then atomically moved into:

`Application Support/WrathiOS/GameData/kp1`

An existing import is moved aside until the new copy and manifest are committed. Failure restores the previous import where possible.

The manifest contains only structural metadata:

- schema and compatibility profile
- pinned engine/QC revisions
- import timestamp
- file, package, and byte counts
- package paths relative to `kp1`
- required sentinel names

It never records the user's original filesystem path.

## CI acceptance

CI must prove:

- synthetic valid PK3 and extracted layouts pass;
- missing sentinels fail with useful output;
- traversal-bearing PK3 entries fail;
- symbolic links fail;
- the arm64 iOS importer builds;
- the existing Gate 3 App ID is reused;
- the importer binary does not link `Host_Main` or `SDL_Init`;
- only system dynamic dependencies are present;
- the unsigned IPA contains no commercial game archives.

## Physical-device acceptance

Gate 4 passes only after device evidence confirms:

- an unrelated or incomplete folder is rejected clearly;
- the user's licensed WRATH folder imports successfully;
- source and sandboxed-copy validation both pass;
- the app reports file/package/size metadata without exposing private source paths;
- a relaunch validates the installed data without selecting the source again;
- removal deletes only the app's sandboxed copy.

Run the complete ordered acceptance procedure in `docs/GATE4_DEVICE_CHECKLIST.md`. The UI exposes screenshot-safe states for no data, invalid selection, source validation, copying, post-copy validation, relaunch detection, and removal.

## Stop condition

Do not call `Host_Main`, initialize WRATH's filesystem, mount imported packages, reach the menu, initialize audio, or begin controls/gameplay until Gate 4 physical-device acceptance is recorded.
