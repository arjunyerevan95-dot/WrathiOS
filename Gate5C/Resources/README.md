# Derived menu program

`wrathios-menu.dat` is QuakeC bytecode compiled from
`Official3DRealms/wrath-qc` commit
`bf7f46792ed3ed018a3d30bf6ca773900d816de1` after applying only
`config/qc/ios_semantic_menu_patches.json`.

The v13 compiler is native FTEQCC from `https://github.com/fte-team/fteqw`
commit `f09ac7cccd2d713ddf881d3f1324703082c2cfe4`, built with `make qcc`
and invoked with `-Tq1` (standard Quake version 6 opcodes, matching the original resource).
Do not use `-Tdp`: this WRATH fork does not enable the extended interpreter
opcodes that current FTEQCC emits for that target.
`config/qc/fteqcc-pragma-once.patch` corrects include-once bookkeeping to
identify the included `s_filen` rather than its parent compilation unit;
without it this compiler redeclares the project's pragma-once UI header.
No gameplay source is transformed outside the recorded QC patch specification.
Reproduce using `scripts/build_gate5c_menu_qc.sh`.

The original v11/v12 compiler was pinned `ssqc/fteqccgui64.exe` (SHA-256
`12cb7a868b883455951fb61b5d307518bf0078bb269814878c0c78cdbdad9456`).
It failed process creation on the Legion with WinError 623, so it was not
silently replaced: baseline v12 QC and patched v13 QC were both compiled with
the new compiler. Baseline SHA-256:
`949c024eab701ae3a2dc8a35d72db38ef97e7915b2ed8fcabfa3f98b718c44b4`.
The scale fix adds eight statements/64 bytes; globals, fields, function counts
and string table size remain identical between these two builds. A repeated
patched compile is byte-identical. Compiler drift from the original binary is
separate from that narrow source change; physical behavior still needs testing.
The derived bytecode SHA-256 is
`f10318db61dc037ead5228b222fa4c0dc7ef8fee5cacc76174b3a62286ab317c`.

This is GPL-derived program code, not the licensed commercial `menu.dat` from
the user's WRATH installation. No artwork, archive, package, map, sound,
texture, or other commercial data is present. Runtime assets continue to come
only from the user's sandboxed import.
