# Gate 5C semantic menu-touch experiment

Gate 5C is based directly on Gate 5A main `538a61f22717c33991c0185b2a7745b18ada5a16`.
It deliberately excludes the abandoned Gate 5B input bridge.

## Authentic menu call graph

The pinned QC revision is `bf7f46792ed3ed018a3d30bf6ca773900d816de1`.

1. `menuqc/menu.qc::MenuInit` creates the home-menu roots and the Begin,
   Return, Options, Achievements, and Depart/quit entities. Each actionable
   entity owns its authentic `m_click` callback and sets `UIFLAG::CLICKABLE`.
2. `menuqc/menu.qc::m_draw` obtains `getpointerpos()`, assigns it to
   `ui_mouseposition`, and walks `ui_screen_queue` through
   `UI_RenderElements`.
3. `uielement.qc::UI_RenderElements` computes `master_position` and
   `chain.totalsize()` after letterboxing, anchor, origin, justification,
   scale, hide, and `active_condition` handling. The same values are used to
   set `ui_hover` and are the Gate 5C snapshot boundary.
4. `menuqc/menu.qc::m_draw` draws the authentic cursor at
   `ui_mouseposition`. No UIKit cursor or button artwork is introduced.
5. Engine `mvm_cmds.c::VM_M_getmousepos` is builtin 66. Gate 5C returns the
   last accepted semantic touch in the menu virtual coordinate space; the
   stock hardware-mouse conversion remains the fallback before any touch.
6. Engine `menu.c::MP_Draw` calls QC `m_draw`. Snapshot builtin 745 publishes
   the final `ui_hover`. Only when it matches the UIKit-hit entity does
   `MP_Draw` call the authentic `MP_KeyEvent(K_MOUSE1, ..., down)` path. Up is
   delivered after the next menu draw.
7. `menuqc/drawmenu.qc::m_keydown` runs `UI_CheckClick`, which recomputes the
   same recursive geometry into `ui_selected`, then invokes the selected
   entity's authentic `m_click` callback.

## Coordinate spaces

- UIKit supplies logical view points.
- The bridge converts once by the current view-size/menu-size ratio.
- QC bounds, `ui_mouseposition`, hover, cursor drawing, and click selection
  use the menu virtual `vid_width` by `vid_height` space.
- Drawable pixels and the device's high-density scale do not enter this
  conversion.

Bounds are per-frame semantic data. Animated or conditional entities are
therefore exported only after QC has applied the current frame's layout and
visibility rules. Reverse snapshot order matches QC's later-entity-wins hover
behavior. The four-menu-unit hit slop is applied around source-derived bounds,
never around guessed screen regions.

## Synchronization

The engine and UIKit callbacks run on the main thread under Gate 5A's
Host_Main ownership model. A mutex still protects immutable snapshot
replacement and the small activation state machine. UIKit never traverses
live QC entities. Menu transitions replace the whole snapshot and invalidate
pending activation for the prior menu. Closing the menu disables and hides
the transparent touch surface.

The bundled `wrathios-menu.dat` is compiled from the pinned GPL QC source plus
the four provenance-checked hook files. It is loaded directly from the app
resource into `PRVM_Prog_Load`; it is not commercial data, is not written to
the imported kp1 tree, and does not alter the filesystem search contract.

## Scope boundary

This experiment contains no profile keyboard, gyro, gameplay swipe, movement,
firing, virtual controls, generic Confirm substitution, hardcoded item
rectangles, direct menu commands, or UIKit menu artwork.
