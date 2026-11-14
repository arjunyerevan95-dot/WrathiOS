# v20 backend-selection correction

Device evidence: two v19 Zink reports match executable UUID214b9204-e872-3846-8b21-037c6428ed35. Both crash at null strcmp through Cvar_SetQuick and GLES_Init after desktop OSMesa context creation succeeded. Private reports are not in this repository.

Root cause: quakedef.h unconditionally reintroduced USE_GLES2 for iPhone after the command-line define was removed. Correct the actual platform header, and materialize the entire public source tree so every translation unit resolves that same header (no fallback to original Vendor headers).

Regression gates: preprocess the real platform block for both renderers; include the full real iOS header under each engine compile and reject mismatch; audit final Zink binary for desktop GL_Init and absence of GLES_Init. GLES rollback retains GLES_Init. Clear inherited Mesa version overrides; do not spoof capability. App metadata and startup transcript now reflect build20.

No device outcome claimed until installed/tested. Preserve imported data/custom controls. Keep the separately delivered GLES rollback.
