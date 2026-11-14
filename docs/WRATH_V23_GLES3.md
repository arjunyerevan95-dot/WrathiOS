# v23 native GLES3 candidate

Single combined candidate: native GLES3 context; implemented FBO, raw depth/manual-PCF shadow path, RGBA8 color/depth/stencil formats and live UIKit screen framebuffer restoration. GLES2 rollback retained separately, same bundle identity.

Resolution: new Native/67%/50% selector is a fraction of native display pixels and requires restart. Default for the new selector is Native. Existing custom control layouts and UI dimension opt-out are preserved. No texture smoothing is introduced. Native UIKit controls stay at logical point size; stock engine UI uses logical dimensions rather than shrinking at higher pixel resolution.

Controls: tap an individual button in edit mode to select; drag moves; pinch changes only that button's saved size/hit rectangle; selected-button size slider retained. Swipe ceiling0.4->2.0; gyro ceiling3->5; existing values/default gyro1 untouched.

Not implemented/claimed: deferred MRT shading, HDR float targets,3D bouncegrid,UBO skinning, exact desktop parity or performance gains. Shared bloom/material paths can now use real FBO support but visual correctness needs actual scene comparison. GLES3 uses existing ESSL100 shaders with raw-depth comparisons, not invented capability flags.

Validation scope: changed renderer/FBO/depth GPU primitives, source wiring, resolution math, per-button editor/persistence and directly affected input routing. GPU probe is a real simulator context but not the entire WRATH renderer; device scene comparison still required. No retail content distributed.
