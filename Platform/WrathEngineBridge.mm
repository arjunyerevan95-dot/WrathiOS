// SPDX-License-Identifier: GPL-2.0-only

#import "WrathEngineBridge.h"

static WrathEngineBridgeState gWrathEngineState = WrathEngineBridgeStateNotLinked;

WrathEngineBridgeState WrathEngineCurrentState(void) {
    return gWrathEngineState;
}

NSString *WrathEngineStatusText(void) {
    switch (gWrathEngineState) {
        case WrathEngineBridgeStateStarting:
            return @"Engine bootstrap is starting.";
        case WrathEngineBridgeStateRunning:
            return @"Engine is running.";
        case WrathEngineBridgeStateSuspended:
            return @"Engine is suspended.";
        case WrathEngineBridgeStateFailed:
            return @"Engine startup failed. Inspect the device log.";
        case WrathEngineBridgeStateNotLinked:
        default:
            return @"Milestone 0 shell is operational. The WRATH engine is pinned but not linked yet.";
    }
}

void WrathEngineWillResignActive(void) {
    if (gWrathEngineState == WrathEngineBridgeStateRunning) {
        gWrathEngineState = WrathEngineBridgeStateSuspended;
    }
}

void WrathEngineDidEnterBackground(void) {
    // Reserved for SDL audio pause, render-loop suspension, and save flushing.
}

void WrathEngineWillEnterForeground(void) {
    // Reserved for graphics-context and filesystem revalidation.
}

void WrathEngineDidBecomeActive(void) {
    if (gWrathEngineState == WrathEngineBridgeStateSuspended) {
        gWrathEngineState = WrathEngineBridgeStateRunning;
    }
}

void WrathEngineWillTerminate(void) {
    // Reserved for orderly engine shutdown once the upstream runtime is linked.
}
