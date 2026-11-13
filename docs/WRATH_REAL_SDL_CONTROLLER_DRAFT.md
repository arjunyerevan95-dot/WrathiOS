# Real SDL touch controller draft

Current base: 36f2432d4ff2d44871542e9fff1c51580bb111b1.

The former route set is360/joy_active but did not enumerate a controller. Native
Controller_Query consequently could not identify an Xbox for glyph selection.
This change registers a real SDL virtual Xbox, resolves its device index, feeds
its buttons/axes through VID_BuildJoyState, and retains independent relative
mouse look. Loaded bindings are used, not rewritten. Video shutdown releases
and detaches the virtual device; reinitialization is tested.

Focused host checks pass: native SDL enumeration/type query, non-controller
index0, native sampler/apply, index shifts, rapid A/B pairs, remapped held-key
release, simultaneous fire/mouse look/movement, lifecycle reinitialization.
Existing semantic-menu and extracted QC-handler regression checks pass.

Private Windows retail host check (not an iOS test): registered virtual Xbox
opened by engine, right-stick pointer + A/B navigate menus, all four copied
profiles and save slots appear, existing autosave loads The Undercrofts and
movement/journal/artifact wheel work. Original installation and saves untouched.
No retail data or screenshots are in this repository.

Actual retail Controller Settings additionally rendered Xbox diagram and colored
A/B/X/Y glyphs with trigger/shoulder/D-pad glyphs during native-controller navigation.
Still required: real iOS build/device behavior. Do not report full controller/UI fix from these results.
