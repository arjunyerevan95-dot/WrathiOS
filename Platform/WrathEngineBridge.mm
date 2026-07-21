// SPDX-License-Identifier: GPL-2.0-only

#import "WrathEngineBridge.h"

#if WRATH_ENGINE_LINKED
extern "C" const char *buildstring;
static WrathEngineBridgeState gWrathEngineState = WrathEngineBridgeStateLinkedDiagnostic;
#else
static WrathEngineBridgeState gWrathEngineState = WrathEngineBridgeStateNotLinked;
#endif

WrathEngineBridgeState WrathEngineCurrentState(void) {
    return gWrathEngineState;
}

NSString *WrathEngineStatusText(void) {
    switch (gWrathEngineState) {
        case WrathEngineBridgeStateLinkedDiagnostic: {
#if WRATH_ENGINE_LINKED
            NSString *revision = buildstring != nullptr
                ? [NSString stringWithUTF8String:buildstring]
                : @"unknown revision";
            return [NSString stringWithFormat:
                @"Gate 2 static-link diagnostic passed. WRATH engine build: %@. Runtime startup is intentionally disabled.",
                revision];
#else
            return @"Engine diagnostic state is unavailable in this build.";
#endif
        }
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
