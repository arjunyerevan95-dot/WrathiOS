# Focused native GLES3 GPU probe

Run on a macOS CI runner with an installed iOS Simulator runtime:

```sh
bash scripts/test_gles3_gpu_probe.sh
```

The script creates its own simulator and removes only that simulator on exit. It compiles a tiny native UIKit/OpenGLES app, runs real ES3 GPU calls, and verifies its JSON receipt. No retail assets, phone, gameplay suite, or existing simulator data are used.

Checks: RGBA8 with depth16; RGBA8 with packed depth24-stencil8; depth-only framebuffer and actual ESSL100 draw; depth texture `.r` sampling/manual four-tap comparison with exact expected pixel; restoring a nonzero UIKit framebuffer, resizing drawable storage and presenting it. Missing ES3 support is a failure, never a skip.

Output: `Artifacts/gles3-probe/gles3-probe.json`.

Scope: this tests the GPU operations/formats/shader language underpinning the new path. It does not link the WRATH engine or prove the production framebuffer-routing helper, full production shader permutations, scene appearance, device rendering or performance. Those require separate targeted tests and phone comparison. The probe is authored on Windows and must be built/run with Apple's SDK before calling it passed.
