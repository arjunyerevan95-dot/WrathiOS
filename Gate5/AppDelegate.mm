// SPDX-License-Identifier: GPL-2.0-only
#import "AppDelegate.h"

#import "WrathImportViewController.h"
#import "WrathRuntime.h"
#ifdef WRATH_IOS_GATE5B
#import "WrathRuntimeHooks.h"
#endif

@implementation Gate5AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;
    (void)launchOptions;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    WrathImportViewController *controller = [[WrathImportViewController alloc] init];
    __weak WrathImportViewController *weakController = controller;
    __weak Gate5AppDelegate *weakSelf = self;
    controller.runtimeLaunchHandler = ^(WrathImportReport *report) {
        (void)report;
        [[WrathRuntime sharedRuntime] startWithCompletion:^(NSString *sanitizedError) {
            Gate5AppDelegate *strongSelf = weakSelf;
            WrathImportViewController *strongController = weakController;
            [strongSelf.window makeKeyAndVisible];
            [strongController showRuntimeFailureAtStage:WrathRuntime.sharedRuntime.lastStage
                                                  error:sanitizedError ?: @"Unknown engine error"
                                             transcript:WrathRuntime.sharedRuntime.transcriptText];
        }];
    };
    [NSNotificationCenter.defaultCenter addObserverForName:WrathRuntimeStageDidChangeNotification
                                                    object:WrathRuntime.sharedRuntime
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *notification) {
        NSString *stage = notification.userInfo[WrathRuntimeStageNameKey] ?: @"Runtime starting";
        NSString *detail = notification.userInfo[WrathRuntimeStageDetailKey] ?: @"";
        [weakController showRuntimeStage:stage
                                  detail:detail
                              transcript:WrathRuntime.sharedRuntime.transcriptText];
    }];
    self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];
    return YES;
}

- (UIInterfaceOrientationMask)application:(UIApplication *)application
       supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    (void)application;
    (void)window;
    return UIInterfaceOrientationMaskLandscape;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    (void)application;
    [WrathRuntime.sharedRuntime recordLifecycleEvent:@"Runtime pause requested"];
#ifdef WRATH_IOS_GATE5B
    WrathIOSMenuPointerReset("focus loss");
#endif
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    (void)application;
    [WrathRuntime.sharedRuntime recordLifecycleEvent:@"Runtime entered background"];
#ifdef WRATH_IOS_GATE5B
    WrathIOSMenuPointerReset("background");
#endif
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    (void)application;
#ifdef WRATH_IOS_GATE5B
    [WrathRuntime.sharedRuntime recordLifecycleEvent:@"Runtime returned to foreground"];
    WrathIOSMenuPointerEnteredForeground();
#else
    [WrathRuntime.sharedRuntime recordLifecycleEvent:@"Runtime foreground recovery entered"];
#endif
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    (void)application;
#ifndef WRATH_IOS_GATE5B
    [WrathRuntime.sharedRuntime recordLifecycleEvent:@"Runtime foreground recovery passed"];
#endif
}

@end
