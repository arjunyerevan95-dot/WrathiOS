// SPDX-License-Identifier: GPL-2.0-only

#import <UIKit/UIKit.h>
#import "AppDelegate.h"

#if WRATH_GATE3_DIAGNOSTIC
#define SDL_MAIN_HANDLED 1
#include <SDL_main.h>
#endif

int main(int argc, char *argv[]) {
    @autoreleasepool {
#if WRATH_GATE3_DIAGNOSTIC
        // UIKit remains the application owner. SDL2main is disabled in the
        // static library, so explicitly satisfy SDL's custom-entry-point contract
        // without allowing SDL_main.h to rename this function.
        SDL_SetMainReady();
#endif
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
