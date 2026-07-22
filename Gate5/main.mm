// SPDX-License-Identifier: GPL-2.0-only
#import <UIKit/UIKit.h>
#import "AppDelegate.h"

#define SDL_MAIN_HANDLED 1
#include <SDL_main.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // Gate 5 retains UIKit ownership and satisfies SDL's custom-main
        // contract before any subsystem initialization can occur.
        SDL_SetMainReady();
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(Gate5AppDelegate.class));
    }
}
