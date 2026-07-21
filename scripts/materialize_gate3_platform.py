#!/usr/bin/env python3
"""Materialize a Gate 3-only platform source tree.

The canonical Platform directory remains unchanged. This script copies it into
Derived and applies bounded diagnostic substitutions used only by the Gate 3
device target:

- reset the persisted launch counter namespace without changing the bundle ID;
- add bundle/build and UIKit geometry telemetry to the diagnostic panel;
- slightly reduce the telemetry font size so the expanded report remains legible.
"""

from __future__ import annotations

import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Platform"
DESTINATION = ROOT / "Derived" / "gate3-platform"
DIAGNOSTIC = DESTINATION / "WrathGraphicsDiagnostic.mm"


def replace_once(text: str, old: str, new: str, description: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(
            f"expected exactly one {description} anchor, found {count}"
        )
    return text.replace(old, new, 1)


def main() -> None:
    if not SOURCE.is_dir():
        raise SystemExit(f"error: missing platform source directory: {SOURCE}")

    shutil.rmtree(DESTINATION, ignore_errors=True)
    shutil.copytree(SOURCE, DESTINATION)

    text = DIAGNOSTIC.read_text(encoding="utf-8")

    text = replace_once(
        text,
        'integerForKey:@"WrathGate3LaunchCount"',
        'integerForKey:@"WrathGate3LaunchCountV2"',
        "Gate 3 launch-counter read",
    )
    text = replace_once(
        text,
        'setInteger:(NSInteger)gLaunchCount forKey:@"WrathGate3LaunchCount"',
        'setInteger:(NSInteger)gLaunchCount forKey:@"WrathGate3LaunchCountV2"',
        "Gate 3 launch-counter write",
    )
    text = replace_once(
        text,
        "monospacedSystemFontOfSize:14.0 weight:UIFontWeightRegular",
        "monospacedSystemFontOfSize:11.5 weight:UIFontWeightRegular",
        "Gate 3 telemetry font",
    )

    old_overlay = '''    UIEdgeInsets insets = gNativeWindow.safeAreaInsets;
    NSString *driver = SDL_GetCurrentVideoDriver() != nullptr
        ? [NSString stringWithUTF8String:SDL_GetCurrentVideoDriver()]
        : @"unknown";
    NSString *renderer = Gate3StringFromGL(glGetString(GL_RENDERER));
    NSString *version = Gate3StringFromGL(glGetString(GL_VERSION));

    gStatusLabel.text = [NSString stringWithFormat:
        @"Context: ACTIVE\\n"
         "SDL driver: %@\\n"
         "GL renderer: %@\\n"
         "GL version: %@\\n"
         "Window: %d × %d pt\\n"
         "Drawable: %d × %d px\\n"
         "Safe area: T%.0f L%.0f B%.0f R%.0f pt\\n"
         "Launch count: %lu\\n"
         "Frames presented: %lu\\n"
         "Foreground recoveries: %lu",
        driver ?: @"unknown",
        renderer,
        version,
        gWindowWidth,
        gWindowHeight,
        gDrawableWidth,
        gDrawableHeight,
        insets.top,
        insets.left,
        insets.bottom,
        insets.right,
        (unsigned long)gLaunchCount,
        (unsigned long)gFrameCount,
        (unsigned long)gRecoveryCount];'''

    new_overlay = '''    UIEdgeInsets insets = gNativeWindow.safeAreaInsets;
    NSString *driver = SDL_GetCurrentVideoDriver() != nullptr
        ? [NSString stringWithUTF8String:SDL_GetCurrentVideoDriver()]
        : @"unknown";
    NSString *renderer = Gate3StringFromGL(glGetString(GL_RENDERER));
    NSString *version = Gate3StringFromGL(glGetString(GL_VERSION));

    NSBundle *bundle = NSBundle.mainBundle;
    NSString *bundleIdentifier = bundle.bundleIdentifier ?: @"unknown";
    NSString *shortVersion = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
    NSString *buildVersion = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"unknown";

    id<UIApplicationDelegate> appDelegate = UIApplication.sharedApplication.delegate;
    UIWindow *hostWindow = nil;
    if ([appDelegate respondsToSelector:@selector(window)]) {
        hostWindow = appDelegate.window;
    }
    UIWindowScene *hostScene = hostWindow.windowScene ?: gNativeWindow.windowScene;
    UIScreen *screen = hostScene.screen ?: UIScreen.mainScreen;
    CGRect hostBounds = hostWindow != nil ? hostWindow.bounds : CGRectZero;
    CGRect sceneBounds = hostScene != nil ? hostScene.coordinateSpace.bounds : CGRectZero;
    CGRect screenBounds = screen.bounds;
    CGRect nativeBounds = screen.nativeBounds;

    gStatusLabel.text = [NSString stringWithFormat:
        @"App: %@ %@ (%@)\\n"
         "Context: ACTIVE · SDL: %@\\n"
         "GL renderer: %@\\n"
         "GL version: %@\\n"
         "Host window: %.0f × %.0f pt\\n"
         "Host scene: %.0f × %.0f pt\\n"
         "Screen/native: %.0f × %.0f pt / %.0f × %.0f px\\n"
         "SDL window: %d × %d pt\\n"
         "Drawable: %d × %d px\\n"
         "Safe area: T%.0f L%.0f B%.0f R%.0f pt\\n"
         "Launches: %lu · Frames: %lu · Recoveries: %lu",
        bundleIdentifier,
        shortVersion,
        buildVersion,
        driver ?: @"unknown",
        renderer,
        version,
        CGRectGetWidth(hostBounds),
        CGRectGetHeight(hostBounds),
        CGRectGetWidth(sceneBounds),
        CGRectGetHeight(sceneBounds),
        CGRectGetWidth(screenBounds),
        CGRectGetHeight(screenBounds),
        CGRectGetWidth(nativeBounds),
        CGRectGetHeight(nativeBounds),
        gWindowWidth,
        gWindowHeight,
        gDrawableWidth,
        gDrawableHeight,
        insets.top,
        insets.left,
        insets.bottom,
        insets.right,
        (unsigned long)gLaunchCount,
        (unsigned long)gFrameCount,
        (unsigned long)gRecoveryCount];'''

    text = replace_once(text, old_overlay, new_overlay, "Gate 3 telemetry block")
    DIAGNOSTIC.write_text(text, encoding="utf-8")

    print(f"materialized Gate 3 platform sources at {DESTINATION}")


if __name__ == "__main__":
    main()
