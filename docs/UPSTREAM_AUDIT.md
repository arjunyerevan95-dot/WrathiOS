# Initial upstream audit

## Findings

The official WRATH 1.1.2 engine repository retains an old `DPiOS.xcodeproj`, iOS preprocessor branches, an SDL video backend, touchscreen input logic, and a `USE_GLES2` build path.

The legacy project is not directly usable. Its recorded settings include iOS 5.0, armv7, obsolete prebuilt SDL archives, iPad-only targeting, and Steel Storm-specific compile definitions. It also lists `mod_skeletal_animatevertices_sse.c`, which is an x86-specific implementation and cannot be used for arm64.

The upstream `makefile.inc` defines the SDL client from a common object list plus menu, sound, SDL system, SDL video, and SDL thread objects. That list will be converted into an explicit iOS compile manifest at Gate 1 rather than relying on Xcode's file discovery.

## First-pass dependency classes

Expected system frameworks:

- UIKit
- Foundation
- QuartzCore
- CoreGraphics
- AVFoundation or AudioToolbox/CoreAudio, depending on the selected SDL audio backend
- OpenGLES for the first renderer experiment
- GameController for controller support

Expected third-party/open-source dependencies requiring exact pins and license review:

- SDL2
- zlib
- libpng
- libjpeg
- Ogg/Vorbis components if retained
- any crypto or network implementation that remains enabled

Features likely disabled during first boot:

- Steam integration
- video capture
- CD audio
- multiplayer networking
- dynamic plugin/library loading
- desktop-only controller and window-system backends

No dependency is approved merely because the desktop build happens to find it on a developer machine.
