// SPDX-License-Identifier: GPL-2.0-only
#import "WrathIOSInputBridge.h"

#import "WrathIOSInputMath.hpp"
#import "WrathRuntimeHooks.h"

#import <CoreMotion/CoreMotion.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <SDL.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <mutex>

namespace {

using wrathios::input::LandscapeOrientation;
using InputPoint = wrathios::input::Point;
using wrathios::input::GestureState;

struct InputCounters {
    unsigned int menuBegins = 0;
    unsigned int menuAbsoluteMoves = 0;
    unsigned int menuTaps = 0;
    unsigned int menuResets = 0;
    unsigned int aimBegins = 0;
    unsigned int swipeEvents = 0;
    unsigned int swipeDeltas = 0;
    unsigned int aimResets = 0;
    unsigned int gyroStarts = 0;
    unsigned int gyroSamples = 0;
    unsigned int gyroDeltas = 0;
    unsigned int gyroSuspends = 0;
    unsigned int gyroResumes = 0;
    unsigned int gyroBaselines = 0;
    unsigned int gyroDiagnostics = 0;
    unsigned int textStarts = 0;
    unsigned int textStops = 0;
};

struct InputState {
    WrathIOSInputMode mode = WrathIOSInputModeOther;
    int logicalWidth = 0;
    int logicalHeight = 0;
    GestureState gesture = {};
    wrathios::input::MenuCursorState menuCursor = {};
    bool forcedMenuButtonRelease = false;
    bool textEntryActive = false;
    bool textEntryDismissed = false;
    bool foregroundPending = false;
    unsigned int stageBudget = 48;
    InputCounters counters;
};

struct GyroAccumulator {
    double lastTimestamp = 0.0;
    float yawRadians = 0.0f;
    float pitchRadians = 0.0f;
    unsigned int samples = 0;
    float rawX = 0.0f;
    float rawY = 0.0f;
    float rawZ = 0.0f;
    float mappedYaw = 0.0f;
    float mappedPitch = 0.0f;
    double snapshotTimestamp = 0.0;
};

InputState gInput;
CMMotionManager *gMotionManager;
NSOperationQueue *gMotionQueue;
std::mutex gGyroMutex;
GyroAccumulator gGyro;
std::atomic<int> gOrientation(static_cast<int>(LandscapeOrientation::unknown));
std::atomic<bool> gGameplayMotionEnabled(false);
bool gMotionRunning = false;
double gLastDiagnosticTimestamp = 0.0;
#if WRATH_IOS_GYRO_DIAGNOSTIC
UILabel *gGyroDiagnosticLabel;
#endif

const char *modeName(WrathIOSInputMode mode) {
    switch (mode) {
        case WrathIOSInputModeMenu:
            return "menu";
        case WrathIOSInputModeMenuText:
            return "menu-text";
        case WrathIOSInputModeGameplay:
            return "gameplay";
        case WrathIOSInputModeOther:
            return "other";
    }
    return "unknown";
}

const char *orientationName(LandscapeOrientation orientation) {
    switch (orientation) {
        case LandscapeOrientation::left:
            return "landscape-left";
        case LandscapeOrientation::right:
            return "landscape-right";
        case LandscapeOrientation::unknown:
            return "unknown";
    }
    return "unknown";
}

#if WRATH_IOS_GYRO_DIAGNOSTIC
UIWindow *foregroundWindow() {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState != UISceneActivationStateForegroundActive) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) {
                return window;
            }
        }
    }
    return nil;
}

void updateGyroDiagnosticOverlay(NSString *text) {
    UIWindow *window = foregroundWindow();
    if (window == nil) {
        return;
    }
    if (gGyroDiagnosticLabel == nil) {
        gGyroDiagnosticLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        gGyroDiagnosticLabel.userInteractionEnabled = NO;
        gGyroDiagnosticLabel.numberOfLines = 2;
        gGyroDiagnosticLabel.font = [UIFont monospacedSystemFontOfSize:10.0
                                                               weight:UIFontWeightSemibold];
        gGyroDiagnosticLabel.textColor = UIColor.whiteColor;
        gGyroDiagnosticLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.62];
        gGyroDiagnosticLabel.layer.cornerRadius = 5.0;
        gGyroDiagnosticLabel.layer.masksToBounds = YES;
        gGyroDiagnosticLabel.textAlignment = NSTextAlignmentCenter;
    }
    if (gGyroDiagnosticLabel.superview != window) {
        [gGyroDiagnosticLabel removeFromSuperview];
        [window addSubview:gGyroDiagnosticLabel];
    }
    const CGFloat width = std::min<CGFloat>(460.0, window.bounds.size.width - 24.0);
    gGyroDiagnosticLabel.frame = CGRectMake(12.0, window.safeAreaInsets.top + 6.0, width, 38.0);
    gGyroDiagnosticLabel.text = text;
    gGyroDiagnosticLabel.hidden = NO;
}

void hideGyroDiagnosticOverlay() {
    gGyroDiagnosticLabel.hidden = YES;
}
#else
void hideGyroDiagnosticOverlay() {
}
#endif

void report(const char *stage, const char *reason) {
    if (gInput.stageBudget == 0) {
        return;
    }
    gInput.stageBudget -= 1;
    char detail[512];
    std::snprintf(detail,
                  sizeof(detail),
                  "menu begins=%u moves=%u taps=%u resets=%u; aim begins=%u moves=%u deltas=%u resets=%u; "
                  "gyro starts=%u samples=%u deltas=%u suspends=%u resumes=%u baselines=%u diagnostics=%u; "
                  "text starts=%u stops=%u; %s",
                  gInput.counters.menuBegins,
                  gInput.counters.menuAbsoluteMoves,
                  gInput.counters.menuTaps,
                  gInput.counters.menuResets,
                  gInput.counters.aimBegins,
                  gInput.counters.swipeEvents,
                  gInput.counters.swipeDeltas,
                  gInput.counters.aimResets,
                  gInput.counters.gyroStarts,
                  gInput.counters.gyroSamples,
                  gInput.counters.gyroDeltas,
                  gInput.counters.gyroSuspends,
                  gInput.counters.gyroResumes,
                  gInput.counters.gyroBaselines,
                  gInput.counters.gyroDiagnostics,
                  gInput.counters.textStarts,
                  gInput.counters.textStops,
                  reason != nullptr ? reason : "event recorded");
    WrathIOSRuntimeStage(stage, detail);
}

bool isMenuMode(WrathIOSInputMode mode) {
    return mode == WrathIOSInputModeMenu || mode == WrathIOSInputModeMenuText;
}

void setTextInputActive(bool active, const char *reason) {
    if (active == gInput.textEntryActive) {
        return;
    }
    if (active) {
        SDL_StartTextInput();
        gInput.counters.textStarts += 1;
        report("Gate 5B profile text entry started",
               reason != nullptr ? reason : "authentic New Profile field selected");
    } else {
        SDL_StopTextInput();
        gInput.counters.textStops += 1;
        report("Gate 5B profile text entry stopped",
               reason != nullptr ? reason : "left authentic New Profile field");
    }
    gInput.textEntryActive = active;
}

LandscapeOrientation currentLandscapeOrientation() {
    UIInterfaceOrientation orientation = UIInterfaceOrientationUnknown;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (windowScene.activationState == UISceneActivationStateForegroundActive ||
            windowScene.activationState == UISceneActivationStateForegroundInactive) {
            orientation = windowScene.interfaceOrientation;
            break;
        }
    }
    if (orientation == UIInterfaceOrientationUnknown) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        orientation = UIApplication.sharedApplication.statusBarOrientation;
#pragma clang diagnostic pop
    }
    if (orientation == UIInterfaceOrientationLandscapeLeft) {
        return LandscapeOrientation::left;
    }
    if (orientation == UIInterfaceOrientationLandscapeRight) {
        return LandscapeOrientation::right;
    }
    return LandscapeOrientation::unknown;
}

void clearGyroAccumulator() {
    std::lock_guard<std::mutex> lock(gGyroMutex);
    gGyro = {};
    gInput.counters.gyroBaselines += 1;
}

void refreshOrientation() {
    LandscapeOrientation orientation = currentLandscapeOrientation();
    int oldValue = gOrientation.exchange(static_cast<int>(orientation));
    if (oldValue != static_cast<int>(orientation)) {
        clearGyroAccumulator();
        report("Gate 5B gyro baseline reset", "landscape orientation changed; pending gyro input discarded");
    }
}

float removeDeadZone(float value) {
    return std::fabs(value) < wrathios::input::kGyroDeadZoneRadiansPerSecond ? 0.0f : value;
}

void startMotionIfNeeded(bool resumed) {
    if (gMotionRunning) {
        return;
    }
    if (gMotionManager == nil) {
        gMotionManager = [[CMMotionManager alloc] init];
        gMotionQueue = [[NSOperationQueue alloc] init];
        gMotionQueue.name = @"com.arjukstudios.wrathios.gyro";
        gMotionQueue.qualityOfService = NSQualityOfServiceUserInteractive;
        gMotionManager.deviceMotionUpdateInterval = 1.0 / 120.0;
    }
    if (!gMotionManager.deviceMotionAvailable) {
        report("Gate 5B gyro unavailable", "Core Motion device-motion data is unavailable on this device");
        return;
    }
    clearGyroAccumulator();
    gGameplayMotionEnabled.store(true);
    [gMotionManager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical
                                                        toQueue:gMotionQueue
                                                    withHandler:^(CMDeviceMotion *motion, NSError *error) {
        if (error != nil || motion == nil || !gGameplayMotionEnabled.load()) {
            return;
        }
        const double timestamp = motion.timestamp;
        std::lock_guard<std::mutex> lock(gGyroMutex);
        if (gGyro.lastTimestamp == 0.0) {
            gGyro.lastTimestamp = timestamp;
            return;
        }
        const double deltaTime = timestamp - gGyro.lastTimestamp;
        gGyro.lastTimestamp = timestamp;
        if (deltaTime <= 0.0 || deltaTime > 0.1) {
            gGyro.yawRadians = 0.0f;
            gGyro.pitchRadians = 0.0f;
            gGyro.samples = 0;
            return;
        }
        InputPoint mapped = wrathios::input::mapGyroRotationRate(
            static_cast<LandscapeOrientation>(gOrientation.load()),
            static_cast<float>(motion.rotationRate.x),
            static_cast<float>(motion.rotationRate.y),
            static_cast<float>(motion.rotationRate.z));
        mapped.x = removeDeadZone(mapped.x);
        mapped.y = removeDeadZone(mapped.y);
        gGyro.rawX = static_cast<float>(motion.rotationRate.x);
        gGyro.rawY = static_cast<float>(motion.rotationRate.y);
        gGyro.rawZ = static_cast<float>(motion.rotationRate.z);
        gGyro.mappedYaw = mapped.x;
        gGyro.mappedPitch = mapped.y;
        gGyro.snapshotTimestamp = timestamp;
        gGyro.yawRadians += mapped.x * static_cast<float>(deltaTime);
        gGyro.pitchRadians += mapped.y * static_cast<float>(deltaTime);
        gGyro.samples += 1;
    }];
    gMotionRunning = true;
    gInput.counters.gyroStarts += 1;
    if (resumed) {
        gInput.counters.gyroResumes += 1;
    }
    report(resumed ? "Gate 5B gyro resumed" : "Gate 5B gyro started",
           "Core Motion device-motion updates running at 120 Hz; gameplay gate enabled");
}

void stopMotion(const char *reason) {
    gGameplayMotionEnabled.store(false);
    if (gMotionRunning) {
        [gMotionManager stopDeviceMotionUpdates];
        gMotionRunning = false;
        gInput.counters.gyroSuspends += 1;
        report("Gate 5B gyro suspended", reason);
    }
    clearGyroAccumulator();
    hideGyroDiagnosticOverlay();
}

void clearFingerState(bool modeTransition, const char *reason) {
    if (gInput.gesture.active) {
        if (isMenuMode(gInput.mode)) {
            gInput.counters.menuResets += 1;
        } else if (gInput.mode == WrathIOSInputModeGameplay) {
            gInput.counters.aimResets += 1;
        }
    }
    wrathios::input::resetGestureState(gInput.gesture);
    (void)modeTransition;
    report("Gate 5B input state reset", reason);
}

void setMenuPosition(float normalizedX, float normalizedY) {
    InputPoint logical = wrathios::input::normalizedToLogical(
        normalizedX, normalizedY, gInput.logicalWidth, gInput.logicalHeight);
    wrathios::input::updateMenuCursor(gInput.menuCursor, logical);
}

} // namespace

extern "C" void WrathIOSInputBeginFrame(void) {
    wrathios::input::beginMenuFrame(gInput.menuCursor);
}

extern "C" void WrathIOSInputSetMode(WrathIOSInputMode mode, int logicalWidth, int logicalHeight) {
    gInput.logicalWidth = std::max(0, logicalWidth);
    gInput.logicalHeight = std::max(0, logicalHeight);
    refreshOrientation();

    if (gInput.mode != mode) {
        WrathIOSInputMode oldMode = gInput.mode;
        const bool oldWasMenu = isMenuMode(oldMode);
        const bool newIsMenu = isMenuMode(mode);
        clearFingerState(true, "engine input mode transition");
        if (oldMode == WrathIOSInputModeGameplay) {
            stopMotion("left gameplay input state");
        }
        if (!newIsMenu) {
            setTextInputActive(false, "left menu text-entry state");
        }
        if (oldWasMenu != newIsMenu) {
            if (oldWasMenu &&
                gInput.menuCursor.buttonPhase == wrathios::input::MenuButtonPhase::down) {
                gInput.forcedMenuButtonRelease = true;
            }
            wrathios::input::resetMenuCursor(gInput.menuCursor);
        }
        if (mode == WrathIOSInputModeMenuText && oldMode != WrathIOSInputModeMenuText) {
            gInput.textEntryDismissed = false;
        } else if (mode != WrathIOSInputModeMenuText) {
            gInput.textEntryDismissed = false;
        }
        gInput.mode = mode;
        char reason[96];
        std::snprintf(reason, sizeof(reason), "%s to %s", modeName(oldMode), modeName(mode));
        report("Gate 5B input mode changed", reason);
        if (mode == WrathIOSInputModeGameplay) {
            startMotionIfNeeded(false);
        }
    } else if (mode == WrathIOSInputModeGameplay && !gMotionRunning) {
        startMotionIfNeeded(true);
    }

    if (gInput.foregroundPending) {
        gInput.foregroundPending = false;
        report("Gate 5B foreground first frame", "first engine input frame after UIKit foreground notification");
    }
}

extern "C" void WrathIOSInputFingerDown(long long fingerID, float normalizedX, float normalizedY) {
    if (gInput.gesture.active) {
        return;
    }
    if (isMenuMode(gInput.mode)) {
        gInput.gesture.active = true;
        gInput.gesture.fingerID = fingerID;
        gInput.gesture.previousX = normalizedX;
        gInput.gesture.previousY = normalizedY;
        gInput.gesture.movement = 0.0f;
        gInput.gesture.drag = false;
        gInput.gesture.movementReported = false;
        setMenuPosition(normalizedX, normalizedY);
        gInput.counters.menuBegins += 1;
        report("Gate 5B menu touch began", "absolute logical cursor positioned under the primary finger");
        return;
    }
    if (gInput.mode == WrathIOSInputModeGameplay &&
        wrathios::input::isGameplayLookZone(normalizedX)) {
        gInput.gesture.active = true;
        gInput.gesture.fingerID = fingerID;
        gInput.gesture.previousX = normalizedX;
        gInput.gesture.previousY = normalizedY;
        gInput.gesture.movementReported = false;
        gInput.counters.aimBegins += 1;
        report("Gate 5B gameplay aim touch began", "origin established in the rightmost 65 percent; camera unchanged");
    }
}

extern "C" void WrathIOSInputFingerMotion(long long fingerID, float normalizedX, float normalizedY) {
    if (!gInput.gesture.active || gInput.gesture.fingerID != fingerID) {
        return;
    }
    if (isMenuMode(gInput.mode)) {
        InputPoint previous = wrathios::input::normalizedToLogical(
            gInput.gesture.previousX, gInput.gesture.previousY, gInput.logicalWidth, gInput.logicalHeight);
        InputPoint current = wrathios::input::normalizedToLogical(
            normalizedX, normalizedY, gInput.logicalWidth, gInput.logicalHeight);
        gInput.gesture.movement += std::hypot(current.x - previous.x, current.y - previous.y);
        gInput.gesture.previousX = normalizedX;
        gInput.gesture.previousY = normalizedY;
        setMenuPosition(normalizedX, normalizedY);
        gInput.counters.menuAbsoluteMoves += 1;
        const float threshold = wrathios::input::kMenuTapThresholdFraction *
            static_cast<float>(std::min(gInput.logicalWidth, gInput.logicalHeight));
        if (gInput.gesture.movement >= threshold) {
            gInput.gesture.drag = true;
        }
        if (!gInput.gesture.movementReported) {
            gInput.gesture.movementReported = true;
            report("Gate 5B menu absolute position updated",
                   "normalized touch converted once to logical window coordinates");
        }
        return;
    }
    if (gInput.mode == WrathIOSInputModeGameplay) {
        InputPoint delta = wrathios::input::swipeDelta(
            gInput.gesture.previousX,
            gInput.gesture.previousY,
            normalizedX,
            normalizedY,
            gInput.logicalWidth,
            gInput.logicalHeight);
        gInput.gesture.previousX = normalizedX;
        gInput.gesture.previousY = normalizedY;
        if (delta.x == 0.0f && delta.y == 0.0f) {
            return;
        }
        gInput.gesture.swipeX += delta.x;
        gInput.gesture.swipeY += delta.y;
        gInput.counters.swipeEvents += 1;
        if (!gInput.gesture.movementReported) {
            gInput.gesture.movementReported = true;
            report("Gate 5B gameplay swipe movement emitted",
                   "finger displacement accumulated as frame-independent WRATH mouse-look delta");
        }
    }
}

extern "C" void WrathIOSInputFingerUp(long long fingerID, float normalizedX, float normalizedY) {
    if (!gInput.gesture.active || gInput.gesture.fingerID != fingerID) {
        return;
    }
    if (isMenuMode(gInput.mode)) {
        setMenuPosition(normalizedX, normalizedY);
        if (!gInput.gesture.drag && wrathios::input::queueMenuTap(gInput.menuCursor)) {
            gInput.counters.menuTaps += 1;
            report("Gate 5B menu tap emitted",
                   "persistent absolute cursor is applied and drawn before frame-separated K_MOUSE1 press/release");
        }
        gInput.counters.menuResets += 1;
    } else if (gInput.mode == WrathIOSInputModeGameplay) {
        gInput.counters.aimResets += 1;
        report("Gate 5B gameplay aim state reset", "finger up; no click or fire event emitted");
    }
    wrathios::input::resetGestureState(gInput.gesture);
}

extern "C" int WrathIOSInputGetMenuPosition(float *logicalX, float *logicalY) {
    if (!isMenuMode(gInput.mode) || logicalX == nullptr || logicalY == nullptr) {
        return 0;
    }
    InputPoint logical = {};
    if (!wrathios::input::getMenuCursor(gInput.menuCursor, logical)) {
        return 0;
    }
    *logicalX = logical.x;
    *logicalY = logical.y;
    return 1;
}

extern "C" void WrathIOSInputMarkMenuPositionApplied(void) {
    wrathios::input::markMenuCursorApplied(gInput.menuCursor);
}

extern "C" int WrathIOSInputConsumeMenuButtonPhase(void) {
    if (gInput.forcedMenuButtonRelease) {
        gInput.forcedMenuButtonRelease = false;
        return -1;
    }
    if (!isMenuMode(gInput.mode)) {
        return 0;
    }
    return wrathios::input::consumeMenuButtonPhase(gInput.menuCursor);
}

extern "C" void WrathIOSInputConsumeGameplayLook(float *mouseDeltaX, float *mouseDeltaY) {
    if (mouseDeltaX == nullptr || mouseDeltaY == nullptr) {
        return;
    }
    *mouseDeltaX = 0.0f;
    *mouseDeltaY = 0.0f;
    if (gInput.mode != WrathIOSInputModeGameplay) {
        return;
    }

    *mouseDeltaX += gInput.gesture.swipeX;
    *mouseDeltaY += gInput.gesture.swipeY;
    if (gInput.gesture.swipeX != 0.0f || gInput.gesture.swipeY != 0.0f) {
        gInput.counters.swipeDeltas += 1;
    }
    gInput.gesture.swipeX = 0.0f;
    gInput.gesture.swipeY = 0.0f;

    GyroAccumulator accumulated;
    {
        std::lock_guard<std::mutex> lock(gGyroMutex);
        accumulated = gGyro;
        gGyro.yawRadians = 0.0f;
        gGyro.pitchRadians = 0.0f;
        gGyro.samples = 0;
    }
    if (accumulated.samples > 0) {
        gInput.counters.gyroSamples += accumulated.samples;
        *mouseDeltaX += -accumulated.yawRadians * wrathios::input::kGyroMouseUnitsPerRadian;
        *mouseDeltaY += accumulated.pitchRadians * wrathios::input::kGyroMouseUnitsPerRadian;
        if (accumulated.yawRadians != 0.0f || accumulated.pitchRadians != 0.0f) {
            gInput.counters.gyroDeltas += 1;
            if (gInput.counters.gyroDeltas == 1) {
                report("Gate 5B gyro delta applied",
                       "landscape-mapped rotation integrated and added at the WRATH mouse-look boundary");
            }
        }
        if (accumulated.snapshotTimestamp - gLastDiagnosticTimestamp >= 0.2 &&
            gInput.counters.gyroDiagnostics < 24) {
            gLastDiagnosticTimestamp = accumulated.snapshotTimestamp;
            gInput.counters.gyroDiagnostics += 1;
            char snapshot[256];
            std::snprintf(snapshot,
                          sizeof(snapshot),
                          "raw rotation-rate rad/s x=%+.3f y=%+.3f z=%+.3f; "
                          "v7 baseline mapped yaw=%+.3f pitch=%+.3f; orientation=%s; snapshot %u/24",
                          accumulated.rawX,
                          accumulated.rawY,
                          accumulated.rawZ,
                          accumulated.mappedYaw,
                          accumulated.mappedPitch,
                          orientationName(static_cast<LandscapeOrientation>(gOrientation.load())),
                          gInput.counters.gyroDiagnostics);
            WrathIOSRuntimeStage("Gate 5B gyro axis diagnostic", snapshot);
#if WRATH_IOS_GYRO_DIAGNOSTIC
            NSString *overlay = [NSString stringWithFormat:
                @"RAW x=%+.3f  y=%+.3f  z=%+.3f\nBASELINE yaw=%+.3f  pitch=%+.3f  %@",
                accumulated.rawX,
                accumulated.rawY,
                accumulated.rawZ,
                accumulated.mappedYaw,
                accumulated.mappedPitch,
                [NSString stringWithUTF8String:
                    orientationName(static_cast<LandscapeOrientation>(gOrientation.load()))]];
            updateGyroDiagnosticOverlay(overlay);
#endif
        }
    }
}

extern "C" void WrathIOSInputSetTextEntryActive(int active) {
    setTextInputActive(active != 0 &&
                           gInput.mode == WrathIOSInputModeMenuText &&
                           !gInput.textEntryDismissed,
                       active ? "authentic WRATH New Profile field selected"
                              : "authentic WRATH profile field no longer active");
}

extern "C" void WrathIOSInputDismissTextEntry(void) {
    if (gInput.mode != WrathIOSInputModeMenuText) {
        return;
    }
    gInput.textEntryDismissed = true;
    setTextInputActive(false, "native Return/Done dismissed the profile keyboard");
}

extern "C" void WrathIOSInputReset(const char *reason) {
    clearFingerState(false, reason != nullptr ? reason : "external reset");
    if (gInput.menuCursor.buttonPhase == wrathios::input::MenuButtonPhase::down) {
        gInput.forcedMenuButtonRelease = true;
    }
    wrathios::input::resetMenuCursor(gInput.menuCursor);
    gInput.textEntryDismissed = false;
    setTextInputActive(false, reason != nullptr ? reason : "external reset");
    stopMotion(reason != nullptr ? reason : "external reset");
}

extern "C" void WrathIOSInputEnteredForeground(void) {
    gInput.foregroundPending = true;
    clearGyroAccumulator();
    report("Gate 5B runtime returned to foreground",
           "pending touches and gyro history remain cleared until the next engine frame");
}
