# v18 artifact and touch layout update

Preserves the real SDL Xbox device and existing data slot. Captured swipe and
gyro accumulate a sustained native right-stick direction for the artifact
wheel, including hold-and-drag on the artifact button. Gyro no longer stops
when CSQC captures input. Capture exit discards its last motion frame.

Outside capture, touch angular deltas reach the engine mouse-look stage
before view clamps, independently of physical-mouse sensitivity, filtering
and acceleration. Game zoom and sensitivity scale remain applied.

Main controls use SF Symbol glyphs; captured wheel hides combat clutter.
Settings supports persistent normalized draggable button positions and reset,
with existing scale/opacity/swipe/gyro preferences retained.

Native fixture checks sustained and reversed radial direction, capture exit,
linear touch look, no camera look in capture, existing SDL/controller pairs
and source handlers. UIKit test covers layout edit/persistence/reset.
Device proof still required for completing tutorial artifact selection, gyro,
perceived swipe speed and custom layout usability.

Renderer: arm64 USE_GLES2 build uses hardware OpenGL ES; software rasterizer
selection is guarded by x86 SSE_POSSIBLE. No performance gain claimed.
