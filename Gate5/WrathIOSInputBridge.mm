// SPDX-License-Identifier: GPL-2.0-only
#import "WrathIOSInputBridge.h"

#import "WrathIOSInputMath.hpp"
#import "WrathRuntimeHooks.h"

#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>

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
};

struct InputState {
    WrathIOSInputMode mode = WrathIOSInputModeOther;
    int logicalWidth = 0;
    int logicalHeight = 0;
    GestureState gesture = {};
    bool menuPositionPending = false;
    float menuX = 0.0f;
    float menuY = 0.0f;
    bool menuClickPending = false;
    bool menuButtonDown = false;
    bool foregroundPending = false;
    unsigned int stageBudget = 48;
    InputCounters counters;
};

struct GyroAccumulator {
    double lastTimestamp = 0.0;
    float yawRadians = 0.0f;
    float pitchRadians = 0.0f;
    unsigned int samples = 0;
};

InputState gInput;
CMMotionManager *gMotionManager;
NSOperationQueue *gMotionQueue;
std::mutex gGyroMutex;
GyroAccumulator gGyro;
std::atomic<int> gOrientation(static_cast<int>(LandscapeOrientation::unknown));
std::atomic<bool> gGameplayMotionEnabled(false);
bool gMotionRunning = false;

const char *modeName(WrathIOSInputMode mode) {
    switch (mode) {
        case WrathIOSInputModeMenu:
            return "menu";
        case WrathIOSInputModeGameplay:
            return "gameplay";
        case WrathIOSInputModeOther:
            return "other";
    }
    return "unknown";
}

void report(const char *stage, const char *reason) {
    if (gInput.stageBudget == 0) {
        return;
    }
    gInput.stageBudget -= 1;
    char detail[512];
    std::snprintf(detail,
                  sizeof(detail),
                  "menu begins=%u moves=%u taps=%u resets=%u; aim begins=%u moves=%u deltas=%u resets=%u; "
                  "gyro starts=%u samples=%u deltas=%u suspends=%u resumes=%u baselines=%u; %s",
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
                  reason != nullptr ? reason : "event recorded");
    WrathIOSRuntimeStage(stage, detail);
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
            static_cast<float>(motion.rotationRate.y));
        mapped.x = removeDeadZone(mapped.x);
        mapped.y = removeDeadZone(mapped.y);
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
}

void clearFingerState(bool modeTransition, const char *reason) {
    if (gInput.gesture.active) {
        if (gInput.mode == WrathIOSInputModeMenu) {
            gInput.counters.menuResets += 1;
        } else if (gInput.mode == WrathIOSInputModeGameplay) {
            gInput.counters.aimResets += 1;
        }
    }
    wrathios::input::resetGestureState(gInput.gesture);
    if (modeTransition || gInput.mode != WrathIOSInputModeMenu) {
        gInput.menuClickPending = false;
    }
    report("Gate 5B input state reset", reason);
}

void setMenuPosition(float normalizedX, float normalizedY) {
    InputPoint logical = wrathios::input::normalizedToLogical(
        normalizedX, normalizedY, gInput.logicalWidth, gInput.logicalHeight);
    gInput.menuX = logical.x;
    gInput.menuY = logical.y;
    gInput.menuPositionPending = true;
}

} // namespace

extern "C" void WrathIOSInputSetMode(WrathIOSInputMode mode, int logicalWidth, int logicalHeight) {
    gInput.logicalWidth = std::max(0, logicalWidth);
    gInput.logicalHeight = std::max(0, logicalHeight);
    refreshOrientation();

    if (gInput.mode != mode) {
        WrathIOSInputMode oldMode = gInput.mode;
        clearFingerState(true, "engine input mode transition");
        if (oldMode == WrathIOSInputModeGameplay) {
            stopMotion("left gameplay input state");
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
    if (gInput.mode == WrathIOSInputModeMenu) {
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
    if (gInput.mode == WrathIOSInputModeMenu) {
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
    if (gInput.mode == WrathIOSInputModeMenu) {
        setMenuPosition(normalizedX, normalizedY);
        if (!gInput.gesture.drag && !gInput.menuClickPending && !gInput.menuButtonDown) {
            gInput.menuClickPending = true;
            gInput.counters.menuTaps += 1;
            report("Gate 5B menu tap emitted",
                   "absolute cursor update precedes one frame-separated K_MOUSE1 press and release");
        }
        gInput.counters.menuResets += 1;
    } else if (gInput.mode == WrathIOSInputModeGameplay) {
        gInput.counters.aimResets += 1;
        report("Gate 5B gameplay aim state reset", "finger up; no click or fire event emitted");
    }
    wrathios::input::resetGestureState(gInput.gesture);
}

extern "C" int WrathIOSInputConsumeMenuPosition(float *logicalX, float *logicalY) {
    if (!gInput.menuPositionPending || logicalX == nullptr || logicalY == nullptr) {
        return 0;
    }
    *logicalX = gInput.menuX;
    *logicalY = gInput.menuY;
    gInput.menuPositionPending = false;
    return 1;
}

extern "C" int WrathIOSInputConsumeMenuButtonPhase(void) {
    if (gInput.menuClickPending) {
        gInput.menuClickPending = false;
        gInput.menuButtonDown = true;
        return 1;
    }
    if (gInput.menuButtonDown) {
        gInput.menuButtonDown = false;
        return -1;
    }
    return 0;
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
    }
}

extern "C" void WrathIOSInputReset(const char *reason) {
    clearFingerState(false, reason != nullptr ? reason : "external reset");
    gInput.menuClickPending = false;
    gInput.menuPositionPending = false;
    stopMotion(reason != nullptr ? reason : "external reset");
}

extern "C" void WrathIOSInputEnteredForeground(void) {
    gInput.foregroundPending = true;
    clearGyroAccumulator();
    report("Gate 5B runtime returned to foreground",
           "pending touches and gyro history remain cleared until the next engine frame");
}
