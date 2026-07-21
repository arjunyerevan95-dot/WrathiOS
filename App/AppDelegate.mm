// SPDX-License-Identifier: GPL-2.0-only

#import "AppDelegate.h"
#import "BootstrapViewController.h"
#import "WrathEngineBridge.h"
#import "WrathGraphicsDiagnostic.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;
    (void)launchOptions;

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[BootstrapViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    (void)application;
#if WRATH_GATE3_DIAGNOSTIC
    WrathGraphicsDiagnosticWillResignActive();
#else
    WrathEngineWillResignActive();
#endif
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    (void)application;
#if WRATH_GATE3_DIAGNOSTIC
    WrathGraphicsDiagnosticDidEnterBackground();
#else
    WrathEngineDidEnterBackground();
#endif
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    (void)application;
#if WRATH_GATE3_DIAGNOSTIC
    WrathGraphicsDiagnosticWillEnterForeground();
#else
    WrathEngineWillEnterForeground();
#endif
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    (void)application;
#if WRATH_GATE3_DIAGNOSTIC
    WrathGraphicsDiagnosticDidBecomeActive();
#else
    WrathEngineDidBecomeActive();
#endif
}

- (void)applicationWillTerminate:(UIApplication *)application {
    (void)application;
#if WRATH_GATE3_DIAGNOSTIC
    WrathGraphicsDiagnosticWillTerminate();
#else
    WrathEngineWillTerminate();
#endif
}

@end
