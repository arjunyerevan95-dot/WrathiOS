// SPDX-License-Identifier: GPL-2.0-only

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WrathEngineBridgeState) {
    WrathEngineBridgeStateNotLinked = 0,
    WrathEngineBridgeStateStarting,
    WrathEngineBridgeStateRunning,
    WrathEngineBridgeStateSuspended,
    WrathEngineBridgeStateFailed
};

FOUNDATION_EXPORT WrathEngineBridgeState WrathEngineCurrentState(void);
FOUNDATION_EXPORT NSString *WrathEngineStatusText(void);

FOUNDATION_EXPORT void WrathEngineWillResignActive(void);
FOUNDATION_EXPORT void WrathEngineDidEnterBackground(void);
FOUNDATION_EXPORT void WrathEngineWillEnterForeground(void);
FOUNDATION_EXPORT void WrathEngineDidBecomeActive(void);
FOUNDATION_EXPORT void WrathEngineWillTerminate(void);

NS_ASSUME_NONNULL_END
