// SPDX-License-Identifier: GPL-2.0-only

#import "AppDelegate.h"
#import "BootstrapViewController.h"
#import "WrathEngineBridge.h"

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
    WrathEngineWillResignActive();
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    (void)application;
    WrathEngineDidEnterBackground();
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    (void)application;
    WrathEngineWillEnterForeground();
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    (void)application;
    WrathEngineDidBecomeActive();
}

- (void)applicationWillTerminate:(UIApplication *)application {
    (void)application;
    WrathEngineWillTerminate();
}

@end
