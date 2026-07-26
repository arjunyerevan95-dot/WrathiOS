// SPDX-License-Identifier: GPL-2.0-only
#import "WrathIOSInputBridge.h"
#import "WrathRuntimeHooks.h"

#import <QuartzCore/QuartzCore.h>
#import <SDL.h>
#import <UIKit/UIKit.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>

namespace {

static NSString * const WrathInputContractVersion = @"gate5b-r3-input-contract-v1";

struct DiagnosticState {
    WrathIOSInputMode mode = WrathIOSInputModeOther;
    int keyDest = -1;
    int consoleActive = 0;
    int textRequested = 0;
    int sdlTextActive = 0;
    int firstResponder = 0;
    int motionRunning = 0;
    int menuIdentifier = 0;
    int selectedIdentifier = 0;
    int hoverIdentifier = 0;
    int profileIdentifier = 0;
    int profileFieldIdentifier = 0;
    int profileFieldDetector = 0;
    float storedX = 0.0f;
    float storedY = 0.0f;
    float appliedX = 0.0f;
    float appliedY = 0.0f;
    float finalX = 0.0f;
    float finalY = 0.0f;
    float menuVMX = 0.0f;
    float menuVMY = 0.0f;
    float rawX = 0.0f;
    float rawY = 0.0f;
    float rawZ = 0.0f;
    float mappedYaw = 0.0f;
    float mappedPitch = 0.0f;
    WrathIOSCursorWriter writer = WrathIOSCursorWriterUnknown;
    int buttonPhase = 0;
    unsigned long long frame = 0;
    unsigned long long fingerSequence = 0;
    unsigned long long storedSequence = 0;
    unsigned long long appliedSequence = 0;
    unsigned long long hoverSequence = 0;
    unsigned long long downSequence = 0;
    unsigned long long upSequence = 0;
    unsigned long long writerGeneration = 0;
    unsigned int gyroSamplesObserved = 0;
    unsigned int gyroMenuSamplesIgnored = 0;
    unsigned int gyroGameplaySamplesApplied = 0;
    unsigned int textEvents = 0;
    char lastReset[48] = "startup";
    char keyboardBackend[32] = "inactive";
};

DiagnosticState gDiagnostic;
UILabel *gDiagnosticOverlay;
double gLastOverlayUpdate = 0.0;
std::atomic<unsigned long long> gKeyboardRequestGeneration(0);
int gLastTranscriptMenuIdentifier = -1;
int gLastTranscriptDetector = -1;
unsigned int gTranscriptBudget = 24;

const char *modeName(WrathIOSInputMode mode) {
    switch (mode) {
        case WrathIOSInputModeMenu:
            return "menu";
        case WrathIOSInputModeMenuText:
            return "menu-text";
        case WrathIOSInputModeGameplay:
            return "gameplay";
        case WrathIOSInputModeOther:
            return "other";
    }
    return "unknown";
}

const char *writerName(WrathIOSCursorWriter writer) {
    switch (writer) {
        case WrathIOSCursorWriterBridgeDirectTouch:
            return "bridge-direct-touch";
        case WrathIOSCursorWriterVidCenterInit:
            return "vid-center-init";
        case WrathIOSCursorWriterSDLMouseMotion:
            return "SDL-mouse-motion";
        case WrathIOSCursorWriterSDLMouseState:
            return "SDL-mouse-state";
        case WrathIOSCursorWriterMenuTransitionInit:
            return "menu-transition-init";
        case WrathIOSCursorWriterLegacyTouch:
            return "legacy-touch";
        case WrathIOSCursorWriterMenuVMBuiltin:
            return "menu-vm-builtin";
        case WrathIOSCursorWriterUnknown:
            return "unknown";
    }
    return "unknown";
}

const char *phaseName(int phase) {
    switch (phase) {
        case 1:
            return "position-wait";
        case 2:
            return "down";
        case 3:
            return "up";
        default:
            return "none";
    }
}

NSString *orientationName() {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        switch (windowScene.interfaceOrientation) {
            case UIInterfaceOrientationLandscapeLeft:
                return @"landscape-left";
            case UIInterfaceOrientationLandscapeRight:
                return @"landscape-right";
            case UIInterfaceOrientationPortrait:
                return @"portrait";
            case UIInterfaceOrientationPortraitUpsideDown:
                return @"portrait-upside-down";
            case UIInterfaceOrientationUnknown:
                break;
        }
    }
    return @"unknown";
}

UIWindow *foregroundWindow() {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            (scene.activationState != UISceneActivationStateForegroundActive &&
             scene.activationState != UISceneActivationStateForegroundInactive)) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) {
                return window;
            }
        }
    }
    return nil;
}

UIView *findFirstResponder(UIView *view) {
    if (view.isFirstResponder) {
        return view;
    }
    for (UIView *child in view.subviews) {
        UIView *found = findFirstResponder(child);
        if (found != nil) {
            return found;
        }
    }
    return nil;
}

void pushKey(SDL_Keycode key) {
    SDL_Event event = {};
    event.type = SDL_KEYDOWN;
    event.key.type = SDL_KEYDOWN;
    event.key.state = SDL_PRESSED;
    event.key.keysym.sym = key;
    SDL_PushEvent(&event);
    event.type = SDL_KEYUP;
    event.key.type = SDL_KEYUP;
    event.key.state = SDL_RELEASED;
    SDL_PushEvent(&event);
}

void pushText(NSString *text) {
    NSData *utf8 = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (utf8.length == 0) {
        return;
    }
    const unsigned char *bytes = static_cast<const unsigned char *>(utf8.bytes);
    NSUInteger offset = 0;
    while (offset < utf8.length) {
        SDL_Event event = {};
        event.type = SDL_TEXTINPUT;
        const NSUInteger maximum = sizeof(event.text.text) - 1;
        NSUInteger count = std::min(maximum, utf8.length - offset);
        while (count > 0 && offset + count < utf8.length &&
               (bytes[offset + count] & 0xC0) == 0x80) {
            count -= 1;
        }
        if (count == 0) {
            count = std::min(maximum, utf8.length - offset);
        }
        std::memcpy(event.text.text, bytes + offset, count);
        event.text.text[count] = '\0';
        SDL_PushEvent(&event);
        offset += count;
    }
}

} // namespace

@interface WrathIOSProfileKeyboardField : UITextField <UITextFieldDelegate>
@end

WrathIOSProfileKeyboardField *gFallbackField;

@implementation WrathIOSProfileKeyboardField

- (BOOL)hasText {
    // The authentic WRATH field owns the text, so this hidden responder stays
    // empty. Report text as present to keep iOS's Backspace key enabled.
    return YES;
}

- (void)deleteBackward {
    pushKey(SDLK_BACKSPACE);
}

- (BOOL)textField:(UITextField *)textField
shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string {
    (void)textField;
    if (string.length > 0) {
        pushText(string);
    }
    (void)range;
    return NO;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    pushKey(SDLK_RETURN);
    [textField resignFirstResponder];
    return NO;
}

@end

namespace {

void updateOverlayNow() {
    const double now = CACurrentMediaTime();
    if (now - gLastOverlayUpdate < 0.2) {
        return;
    }
    gLastOverlayUpdate = now;
    UIWindow *window = foregroundWindow();
    if (window == nil) {
        return;
    }
    if (gDiagnosticOverlay == nil) {
        gDiagnosticOverlay = [[UILabel alloc] initWithFrame:CGRectZero];
        gDiagnosticOverlay.userInteractionEnabled = NO;
        gDiagnosticOverlay.accessibilityElementsHidden = YES;
        gDiagnosticOverlay.numberOfLines = 0;
        gDiagnosticOverlay.font = [UIFont monospacedSystemFontOfSize:8.0 weight:UIFontWeightSemibold];
        gDiagnosticOverlay.textColor = UIColor.whiteColor;
        gDiagnosticOverlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.68];
        gDiagnosticOverlay.layer.cornerRadius = 5.0;
        gDiagnosticOverlay.layer.masksToBounds = YES;
        gDiagnosticOverlay.textAlignment = NSTextAlignmentLeft;
    }
    if (gDiagnosticOverlay.superview != window) {
        [gDiagnosticOverlay removeFromSuperview];
        [window addSubview:gDiagnosticOverlay];
    }
    NSString *version = [NSString stringWithFormat:@"%@ (%@)",
        [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?",
        [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?"];
    NSString *text = [NSString stringWithFormat:
        @"G5B R3 %@  %@\n"
         "mode=%s key_dest=%d console=%d menu=%d sel=%d hover=%d\n"
         "text requested=%d SDL-active=%d responder=%d backend=%s detector=%d field=%d/%d events=%u\n"
         "touch stored=(%.0f,%.0f) applied=(%.0f,%.0f) final=(%.0f,%.0f) VM=(%.0f,%.0f)\n"
         "writer=%s gen=%llu phase=%s frame=%llu\n"
         "seq finger=%llu stored=%llu applied=%llu hover=%llu down=%llu up=%llu reset=%s\n"
         "motion running=%d orientation=%@ raw x=%+.3f y=%+.3f z=%+.3f\n"
         "candidate(unverified) yaw=%+.3f pitch=%+.3f\n"
         "gyro samples=%u menu-ignored=%u gameplay-applied=%u",
        version,
        WrathInputContractVersion,
        modeName(gDiagnostic.mode),
        gDiagnostic.keyDest,
        gDiagnostic.consoleActive,
        gDiagnostic.menuIdentifier,
        gDiagnostic.selectedIdentifier,
        gDiagnostic.hoverIdentifier,
        gDiagnostic.textRequested,
        gDiagnostic.sdlTextActive,
        gDiagnostic.firstResponder,
        gDiagnostic.keyboardBackend,
        gDiagnostic.profileFieldDetector,
        gDiagnostic.profileIdentifier,
        gDiagnostic.profileFieldIdentifier,
        gDiagnostic.textEvents,
        gDiagnostic.storedX,
        gDiagnostic.storedY,
        gDiagnostic.appliedX,
        gDiagnostic.appliedY,
        gDiagnostic.finalX,
        gDiagnostic.finalY,
        gDiagnostic.menuVMX,
        gDiagnostic.menuVMY,
        writerName(gDiagnostic.writer),
        gDiagnostic.writerGeneration,
        phaseName(gDiagnostic.buttonPhase),
        gDiagnostic.frame,
        gDiagnostic.fingerSequence,
        gDiagnostic.storedSequence,
        gDiagnostic.appliedSequence,
        gDiagnostic.hoverSequence,
        gDiagnostic.downSequence,
        gDiagnostic.upSequence,
        gDiagnostic.lastReset,
        gDiagnostic.motionRunning,
        orientationName(),
        gDiagnostic.rawX,
        gDiagnostic.rawY,
        gDiagnostic.rawZ,
        gDiagnostic.mappedYaw,
        gDiagnostic.mappedPitch,
        gDiagnostic.gyroSamplesObserved,
        gDiagnostic.gyroMenuSamplesIgnored,
        gDiagnostic.gyroGameplaySamplesApplied];
    const CGFloat width = std::min<CGFloat>(650.0, window.bounds.size.width - 16.0);
    gDiagnosticOverlay.frame = CGRectMake(8.0,
                                          window.safeAreaInsets.top + 4.0,
                                          width,
                                          142.0);
    gDiagnosticOverlay.text = text;
    gDiagnosticOverlay.hidden = NO;
    [window bringSubviewToFront:gDiagnosticOverlay];
}

void updateOverlay() {
    if (NSThread.isMainThread) {
        updateOverlayNow();
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            updateOverlayNow();
        });
    }
}

void stopKeyboardOnMain() {
    [gFallbackField resignFirstResponder];
    [gFallbackField removeFromSuperview];
    gFallbackField = nil;
    SDL_StopTextInput();
    gDiagnostic.sdlTextActive = SDL_IsTextInputActive() ? 1 : 0;
    gDiagnostic.firstResponder = 0;
    std::snprintf(gDiagnostic.keyboardBackend, sizeof(gDiagnostic.keyboardBackend), "%s", "inactive");
    updateOverlayNow();
}

void startKeyboardOnMain(unsigned long long generation) {
    if (generation != gKeyboardRequestGeneration.load() || !gDiagnostic.textRequested) {
        return;
    }
    SDL_StartTextInput();
    gDiagnostic.sdlTextActive = SDL_IsTextInputActive() ? 1 : 0;

    // Repeated physical-device evidence showed that SDL's text-active flag did
    // not produce a visible responder under the custom Host_Main/UIKit launch
    // architecture. The R3 diagnostic therefore uses a narrow responder whose
    // only job is to feed SDL_TEXTINPUT and authentic key events back to WRATH.
    UIWindow *window = foregroundWindow();
    if (window != nil) {
        if (gFallbackField == nil) {
            gFallbackField = [[WrathIOSProfileKeyboardField alloc] initWithFrame:CGRectMake(1, 1, 2, 2)];
            gFallbackField.delegate = gFallbackField;
            gFallbackField.autocorrectionType = UITextAutocorrectionTypeNo;
            gFallbackField.spellCheckingType = UITextSpellCheckingTypeNo;
            gFallbackField.autocapitalizationType = UITextAutocapitalizationTypeNone;
            gFallbackField.keyboardType = UIKeyboardTypeDefault;
            gFallbackField.returnKeyType = UIReturnKeyDone;
            gFallbackField.textColor = UIColor.clearColor;
            gFallbackField.backgroundColor = UIColor.clearColor;
            gFallbackField.alpha = 0.01;
            gFallbackField.accessibilityElementsHidden = YES;
            [window addSubview:gFallbackField];
        }
        [gFallbackField becomeFirstResponder];
        gDiagnostic.firstResponder = gFallbackField.isFirstResponder ? 1 : 0;
        std::snprintf(gDiagnostic.keyboardBackend,
                      sizeof(gDiagnostic.keyboardBackend),
                      "%s",
                      "UIKit fallback");
        char detail[192];
        std::snprintf(detail,
                      sizeof(detail),
                      "detector=true; SDL-active=%d; UIKit fallback first-responder=%d",
                      gDiagnostic.sdlTextActive,
                      gDiagnostic.firstResponder);
        WrathIOSRuntimeStage("Gate 5B R3 keyboard backend", detail);
    } else {
        std::snprintf(gDiagnostic.keyboardBackend,
                      sizeof(gDiagnostic.keyboardBackend),
                      "%s",
                      "SDL native text input");
    }
    updateOverlayNow();
}

} // namespace

extern "C" void WrathIOSDiagnosticsSetMode(WrathIOSInputMode mode) {
    gDiagnostic.mode = mode;
    updateOverlay();
}

extern "C" void WrathIOSDiagnosticsBeginFrame(void) {
    gDiagnostic.frame += 1;
    updateOverlay();
}

extern "C" void WrathIOSDiagnosticsStoredTouch(float x, float y) {
    gDiagnostic.storedX = x;
    gDiagnostic.storedY = y;
    gDiagnostic.fingerSequence += 1;
    gDiagnostic.storedSequence = gDiagnostic.fingerSequence;
    updateOverlay();
}

extern "C" void WrathIOSDiagnosticsReset(const char *reason) {
    std::snprintf(gDiagnostic.lastReset,
                  sizeof(gDiagnostic.lastReset),
                  "%s",
                  reason != nullptr ? reason : "reset");
    updateOverlay();
}

extern "C" void WrathIOSDiagnosticsRequestTextEntry(int active) {
    gDiagnostic.textRequested = active != 0;
    const unsigned long long generation = gKeyboardRequestGeneration.fetch_add(1) + 1;
    if (NSThread.isMainThread) {
        active ? startKeyboardOnMain(generation) : stopKeyboardOnMain();
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            active ? startKeyboardOnMain(generation) : stopKeyboardOnMain();
        });
    }
}

extern "C" void WrathIOSDiagnosticsSetMotionRunning(int running) {
    gDiagnostic.motionRunning = running != 0;
    updateOverlay();
}

extern "C" const char *WrathIOSInputDiagnosticContractMarker(void) {
    // Keep launcher provenance observable to a plain Mach-O strings audit;
    // NSString literals alone may be emitted as non-ASCII constant objects.
    return "GATE 5B REVISION 3";
}

extern "C" void WrathIOSInputTraceEngineState(int keyDest, int consoleActive, int textRequested) {
    gDiagnostic.keyDest = keyDest;
    gDiagnostic.consoleActive = consoleActive;
    gDiagnostic.textRequested = textRequested;
    gDiagnostic.sdlTextActive = SDL_IsTextInputActive() ? 1 : 0;
    UIWindow *window = foregroundWindow();
    gDiagnostic.firstResponder = window != nil && findFirstResponder(window) != nil ? 1 : 0;
    updateOverlay();
}

extern "C" void WrathIOSInputTraceCursorWrite(WrathIOSCursorWriter writer, float x, float y) {
    gDiagnostic.writer = writer;
    gDiagnostic.writerGeneration += 1;
    gDiagnostic.appliedX = x;
    gDiagnostic.appliedY = y;
    if (writer == WrathIOSCursorWriterBridgeDirectTouch) {
        gDiagnostic.appliedSequence = ++gDiagnostic.fingerSequence;
    }
    updateOverlay();
}

extern "C" void WrathIOSInputTraceCursorFinal(float x, float y) {
    gDiagnostic.finalX = x;
    gDiagnostic.finalY = y;
    const bool differsFromApplied =
        std::abs(gDiagnostic.finalX - gDiagnostic.appliedX) > 0.5f ||
        std::abs(gDiagnostic.finalY - gDiagnostic.appliedY) > 0.5f;
    if (differsFromApplied &&
        (gDiagnostic.writer == WrathIOSCursorWriterBridgeDirectTouch ||
         gDiagnostic.writer == WrathIOSCursorWriterMenuVMBuiltin)) {
        gDiagnostic.writer = WrathIOSCursorWriterUnknown;
        gDiagnostic.writerGeneration += 1;
    }
    updateOverlay();
}

extern "C" void WrathIOSInputTraceMenuVMRead(float engineX,
                                              float engineY,
                                              float virtualX,
                                              float virtualY,
                                              int usedBridgeCoordinate) {
    gDiagnostic.finalX = engineX;
    gDiagnostic.finalY = engineY;
    gDiagnostic.menuVMX = virtualX;
    gDiagnostic.menuVMY = virtualY;
    if (usedBridgeCoordinate) {
        gDiagnostic.writer = WrathIOSCursorWriterMenuVMBuiltin;
        gDiagnostic.writerGeneration += 1;
    }
    updateOverlay();
}

extern "C" void WrathIOSInputTraceMenuState(int menuIdentifier,
                                             int selectedIdentifier,
                                             int hoverIdentifier,
                                             float menuCursorX,
                                             float menuCursorY,
                                             int profileFieldDetector,
                                             int profileIdentifier,
                                             int profileFieldIdentifier) {
    gDiagnostic.menuIdentifier = menuIdentifier;
    gDiagnostic.selectedIdentifier = selectedIdentifier;
    gDiagnostic.hoverIdentifier = hoverIdentifier;
    gDiagnostic.menuVMX = menuCursorX;
    gDiagnostic.menuVMY = menuCursorY;
    gDiagnostic.profileFieldDetector = profileFieldDetector;
    gDiagnostic.profileIdentifier = profileIdentifier;
    gDiagnostic.profileFieldIdentifier = profileFieldIdentifier;
    gDiagnostic.hoverSequence = ++gDiagnostic.fingerSequence;
    if (gTranscriptBudget > 0 &&
        (gLastTranscriptMenuIdentifier != menuIdentifier ||
         gLastTranscriptDetector != profileFieldDetector)) {
        gLastTranscriptMenuIdentifier = menuIdentifier;
        gLastTranscriptDetector = profileFieldDetector;
        gTranscriptBudget -= 1;
        char detail[224];
        std::snprintf(detail,
                      sizeof(detail),
                      "menu=%d selected=%d hover=%d detector=%d profile=%d field=%d",
                      menuIdentifier,
                      selectedIdentifier,
                      hoverIdentifier,
                      profileFieldDetector,
                      profileIdentifier,
                      profileFieldIdentifier);
        WrathIOSRuntimeStage("Gate 5B R3 menu detector", detail);
    }
    updateOverlay();
}

extern "C" void WrathIOSInputTraceButtonPhase(int phase) {
    gDiagnostic.buttonPhase = phase;
    if (phase == 2) {
        gDiagnostic.downSequence = ++gDiagnostic.fingerSequence;
    } else if (phase == 3) {
        gDiagnostic.upSequence = ++gDiagnostic.fingerSequence;
    }
    updateOverlay();
}

extern "C" void WrathIOSInputTraceSDLTextEvent(void) {
    gDiagnostic.textEvents += 1;
    updateOverlay();
}

extern "C" void WrathIOSInputTraceGyro(float rawX,
                                        float rawY,
                                        float rawZ,
                                        float mappedYaw,
                                        float mappedPitch,
                                        int sampleApplied) {
    void (^record)(void) = ^{
        gDiagnostic.rawX = rawX;
        gDiagnostic.rawY = rawY;
        gDiagnostic.rawZ = rawZ;
        gDiagnostic.mappedYaw = mappedYaw;
        gDiagnostic.mappedPitch = mappedPitch;
        gDiagnostic.gyroSamplesObserved += 1;
        if (sampleApplied) {
            gDiagnostic.gyroGameplaySamplesApplied += 1;
        } else if (gDiagnostic.mode == WrathIOSInputModeMenu ||
                   gDiagnostic.mode == WrathIOSInputModeMenuText) {
            gDiagnostic.gyroMenuSamplesIgnored += 1;
        }
        updateOverlayNow();
    };
    if (NSThread.isMainThread) {
        record();
    } else {
        dispatch_async(dispatch_get_main_queue(), record);
    }
}
