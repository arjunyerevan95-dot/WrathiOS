// SPDX-License-Identifier: GPL-2.0-only
#import "WrathRuntime.h"

#import "WrathDataImporter.h"
#import "WrathRuntimeHooks.h"

#import <UIKit/UIKit.h>
#import <os/log.h>
#import <SDL.h>
#import <SDL_system.h>

#include <setjmp.h>
#include <stdarg.h>
#include <stdio.h>
#include <string>
#include <vector>

NSNotificationName const WrathRuntimeStageDidChangeNotification = @"WrathRuntimeStageDidChangeNotification";
NSString * const WrathRuntimeStageNameKey = @"stage";
NSString * const WrathRuntimeStageDetailKey = @"detail";

static NSString * const WrathStageImportedDetected = @"Imported data detected";
static NSString * const WrathStageValidationPassed = @"Imported data validation passed";
static NSString * const WrathStagePathsPrepared = @"Runtime path contract prepared";
static NSString * const WrathStageSDLMainReady = @"SDL main readiness established";
static NSString * const WrathStageSDLInitialized = @"SDL initialized";
#ifdef WRATH_IOS_GATE5B
static NSString * const WrathTranscriptVersion = @"0.0.6 (6)";
#else
static NSString * const WrathTranscriptVersion = @"0.0.5 (5)";
#endif

static jmp_buf gRuntimeAbortTarget;
static WrathRuntime *gActiveRuntime;

extern "C" {
extern int com_argc;
extern const char **com_argv;
void Host_Main(void);
void Host_Shutdown(void);
void Sys_ProvideSelfFD(void);
}

@interface WrathRuntime ()
@property(nonatomic, readwrite, getter=isStartingOrActive) BOOL startingOrActive;
@property(nonatomic, copy, readwrite) NSString *lastStage;
@property(nonatomic) NSMutableArray<NSDictionary<NSString *, id> *> *entries;
@property(nonatomic) NSUInteger sequence;
@property(nonatomic) BOOL attempted;
@property(nonatomic, copy) WrathRuntimeCompletion completion;
- (void)recordStage:(NSString *)stage detail:(NSString *)detail;
- (void)recordFatalError:(NSString *)message;
- (NSString *)sanitize:(NSString *)text;
@end

static int WrathRunHostMain(void) {
    int result = setjmp(gRuntimeAbortTarget);
    if (result == 0) {
        Host_Main();
        return 0;
    }
    return result;
}

@implementation WrathRuntime

+ (instancetype)sharedRuntime {
    static WrathRuntime *runtime;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        runtime = [[WrathRuntime alloc] initPrivate];
    });
    return runtime;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _entries = [NSMutableArray array];
        _lastStage = @"Runtime not started";
    }
    return self;
}

- (instancetype)init {
    return [WrathRuntime sharedRuntime];
}

+ (NSURL *)runtimeRootURL {
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                          inDomains:NSUserDomainMask].firstObject;
    return [[[support URLByAppendingPathComponent:@"WrathiOS" isDirectory:YES]
             URLByAppendingPathComponent:@"Runtime" isDirectory:YES] URLByStandardizingPath];
}

+ (NSURL *)transcriptURL {
    return [[self runtimeRootURL] URLByAppendingPathComponent:@"last-startup.json" isDirectory:NO];
}

- (NSString *)sanitize:(NSString *)text {
    if (text.length == 0) {
        return @"";
    }
    NSMutableString *sanitized = [text mutableCopy];
    NSArray<NSString *> *privateRoots = @[
        NSHomeDirectory() ?: @"",
        NSBundle.mainBundle.bundlePath ?: @"",
        WrathDataImporter.installedKP1URL.path ?: @"",
        WrathRuntime.runtimeRootURL.path ?: @""
    ];
    for (NSString *root in privateRoots) {
        if (root.length > 0) {
            [sanitized replaceOccurrencesOfString:root
                                       withString:@"<private-path>"
                                          options:NSCaseInsensitiveSearch
                                            range:NSMakeRange(0, sanitized.length)];
        }
    }
    NSError *regexError = nil;
    NSRegularExpression *containerPath = [NSRegularExpression
        regularExpressionWithPattern:@"/(?:private/)?var/mobile/Containers/[^\\s\\\"']+"
                             options:NSRegularExpressionCaseInsensitive
                               error:&regexError];
    if (containerPath != nil && regexError == nil) {
        [containerPath replaceMatchesInString:sanitized
                                       options:0
                                         range:NSMakeRange(0, sanitized.length)
                                  withTemplate:@"<private-path>"];
    }
    return sanitized;
}

- (void)persistTranscript {
    NSURL *url = WrathRuntime.transcriptURL;
    NSError *directoryError = nil;
    [NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:&directoryError];
    if (directoryError != nil) {
        os_log_error(OS_LOG_DEFAULT, "Gate 5 transcript directory error: %{public}@", directoryError.localizedDescription);
        return;
    }
    NSDictionary *document = @{
        @"schema": @1,
        @"version": WrathTranscriptVersion,
        @"entries": self.entries
    };
    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:document options:NSJSONWritingPrettyPrinted error:&jsonError];
    if (data == nil || ![data writeToURL:url options:NSDataWritingAtomic error:&jsonError]) {
        os_log_error(OS_LOG_DEFAULT, "Gate 5 transcript write error: %{public}@", jsonError.localizedDescription);
    }
}

- (void)recordStage:(NSString *)stage detail:(NSString *)detail {
    NSString *safeStage = [self sanitize:stage];
    NSString *safeDetail = [self sanitize:detail];
    self.sequence += 1;
    self.lastStage = safeStage;
    [self.entries addObject:@{
        @"sequence": @(self.sequence),
        @"stage": safeStage,
        @"detail": safeDetail
    }];
    static const NSUInteger WrathMaximumTranscriptEntries = 128;
    if (self.entries.count > WrathMaximumTranscriptEntries) {
        [self.entries removeObjectsInRange:NSMakeRange(0, self.entries.count - WrathMaximumTranscriptEntries)];
    }
    [self persistTranscript];
    os_log_info(OS_LOG_DEFAULT, "Gate 5 [%{public}lu] %{public}@ - %{public}@",
                (unsigned long)self.sequence, safeStage, safeDetail);
    [NSNotificationCenter.defaultCenter postNotificationName:WrathRuntimeStageDidChangeNotification
                                                      object:self
                                                    userInfo:@{
                                                        WrathRuntimeStageNameKey: safeStage,
                                                        WrathRuntimeStageDetailKey: safeDetail
                                                    }];
}

- (void)recordFatalError:(NSString *)message {
    NSString *safe = [self sanitize:message.length > 0 ? message : @"Unknown engine error"];
    self.sequence += 1;
    [self.entries addObject:@{
        @"sequence": @(self.sequence),
        @"stage": @"Runtime failure recorded",
        @"detail": safe
    }];
    [self persistTranscript];
    os_log_error(OS_LOG_DEFAULT, "Gate 5 runtime failure after %{public}@: %{public}@", self.lastStage, safe);
}

- (NSString *)transcriptText {
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:self.entries.count];
    for (NSDictionary<NSString *, id> *entry in self.entries) {
        [lines addObject:[NSString stringWithFormat:@"%@. %@ — %@",
                          entry[@"sequence"], entry[@"stage"], entry[@"detail"]]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (void)startWithCompletion:(WrathRuntimeCompletion)completion {
    NSAssert(NSThread.isMainThread, @"WRATH runtime must start on the UIKit main thread");
    if (self.startingOrActive || self.attempted) {
        completion(@"A runtime attempt has already occurred in this process. Relaunch before retrying.");
        return;
    }
    self.attempted = YES;
    self.startingOrActive = YES;
    self.completion = completion;
    [self.entries removeAllObjects];
    self.sequence = 0;

    [[WrathDataImporter sharedImporter] inspectInstalledDataWithCompletion:^(WrathImportReport *report, NSError *error) {
        if (error != nil || report == nil || !report.compatible) {
            self.startingOrActive = NO;
            [self recordFatalError:@"Imported data is absent or failed structural validation."];
            completion(@"Imported data is absent or invalid. Return to data management.");
            return;
        }

        [self recordStage:WrathStageImportedDetected detail:@"Sandboxed kp1 copy is available."];
        [self recordStage:WrathStageValidationPassed detail:@"Profile wrath-1.1.2-qc-layout-v1 and required sentinels passed."];

        NSURL *baseURL = WrathDataImporter.installedKP1URL.URLByDeletingLastPathComponent;
        NSURL *userURL = [WrathRuntime.runtimeRootURL URLByAppendingPathComponent:@"UserData" isDirectory:YES];
        NSError *directoryError = nil;
        if (![NSFileManager.defaultManager createDirectoryAtURL:userURL
                                    withIntermediateDirectories:YES
                                                     attributes:nil
                                                          error:&directoryError]) {
            self.startingOrActive = NO;
            [self recordFatalError:@"The writable runtime directory could not be prepared."];
            completion(@"Could not prepare the writable runtime directory.");
            return;
        }
        [self recordStage:WrathStagePathsPrepared
                   detail:@"Read-only GameData/kp1 and separate Runtime/UserData roots prepared."];
        [self recordStage:WrathStageSDLMainReady
                   detail:@"UIKit owns launch; SDL iOS event pumping is enabled for Host_Main."];

        CGSize size = UIScreen.mainScreen.bounds.size;
        int width = (int)MAX(size.width, size.height);
        int height = (int)MIN(size.width, size.height);
        NSString *executable = NSBundle.mainBundle.executablePath ?: @"WrathiOSGate5";
        std::vector<std::string> arguments = {
            executable.UTF8String,
            "-wrath",
            "-basedir", baseURL.fileSystemRepresentation,
            "-userdir", userURL.fileSystemRepresentation,
            "-fullscreen",
            "-width", std::to_string(width),
            "-height", std::to_string(height),
            "+vid_touchscreen", "1"
        };
        std::vector<const char *> argv;
        argv.reserve(arguments.size());
        for (const std::string &argument : arguments) {
            argv.push_back(argument.c_str());
        }
        com_argc = (int)argv.size();
        com_argv = argv.data();
        Sys_ProvideSelfFD();

#ifdef WRATH_IOS_GATE5B
        if (SDL_SetHintWithPriority(SDL_HINT_TOUCH_MOUSE_EVENTS, "0", SDL_HINT_OVERRIDE) != SDL_TRUE) {
            self.startingOrActive = NO;
            [self recordFatalError:@"SDL touch-to-mouse synthesis could not be disabled."];
            completion(@"Could not establish the Gate 5B touch event contract.");
            return;
        }
        [self recordStage:@"Gate 5B direct touch path selected"
                   detail:@"SDL touch-to-mouse synthesis disabled; direct finger events own menu input."];
#endif
        if (SDL_Init(0) < 0) {
            self.startingOrActive = NO;
            NSString *errorText = [NSString stringWithUTF8String:SDL_GetError()] ?: @"Unknown SDL error";
            [self recordFatalError:errorText];
            completion(errorText);
            return;
        }
        [self recordStage:WrathStageSDLInitialized detail:@"SDL core initialized without prestarting video."];

        gActiveRuntime = self;
        SDL_iPhoneSetEventPump(SDL_TRUE);
        int hostResult = WrathRunHostMain();
        SDL_Quit();
        SDL_iPhoneSetEventPump(SDL_FALSE);
        gActiveRuntime = nil;
        self.startingOrActive = NO;

        NSString *failure = hostResult == 0
            ? @"Host_Main returned before the runtime became active."
            : self.entries.lastObject[@"detail"];
        if (hostResult == 0) {
            [self recordFatalError:failure];
        }
        completion([self sanitize:failure]);
    }];
}

- (void)recordLifecycleEvent:(NSString *)event {
    if (self.startingOrActive) {
        [self recordStage:event detail:@"SDL/UIKit lifecycle notification observed."];
    }
}

@end

extern "C" void WrathIOSRuntimeStage(const char *stage, const char *detail) {
    @autoreleasepool {
        NSString *stageText = stage != nullptr ? [NSString stringWithUTF8String:stage] : @"Unknown runtime stage";
        NSString *detailText = detail != nullptr ? [NSString stringWithUTF8String:detail] : @"";
        [[WrathRuntime sharedRuntime] recordStage:stageText ?: @"Unknown runtime stage"
                                           detail:detailText ?: @""];
    }
}

extern "C" __attribute__((noreturn)) void WrathIOSRuntimeAbort(const char *message) {
    @autoreleasepool {
        NSString *text = message != nullptr ? [NSString stringWithUTF8String:message] : @"Unknown engine error";
        [(gActiveRuntime ?: WrathRuntime.sharedRuntime) recordFatalError:text ?: @"Unknown engine error"];
    }
    longjmp(gRuntimeAbortTarget, 1);
}

static BOOL WrathEngineLineIsSafeAndRelevant(NSString *line) {
    NSString *lower = line.lowercaseString;
    if ([lower containsString:@".pk3"] || [lower containsString:@".pak"] ||
        [lower containsString:@".wad"] || [lower containsString:@"/maps/"] ||
        [lower containsString:@"/textures/"] || [lower containsString:@"/sound/"]) {
        return NO;
    }
    return [lower containsString:@"error"] || [lower containsString:@"warning"] ||
           [lower containsString:@"initialized"] || [lower containsString:@"sdl"] ||
           [lower containsString:@"opengl"] || [lower containsString:@"sound format"] ||
           [lower containsString:@"menu.dat"];
}

extern "C" {

int sys_supportsdlgetticks = 1;

void Sys_InitConsole(void) {
}

void Sys_PrintToTerminal(const char *text) {
    if (text == nullptr) {
        return;
    }
    @autoreleasepool {
        NSString *line = [NSString stringWithUTF8String:text] ?: @"<non-UTF8 engine output>";
        NSString *safe = [WrathRuntime.sharedRuntime sanitize:line];
        if (WrathEngineLineIsSafeAndRelevant(safe)) {
            os_log_info(OS_LOG_DEFAULT, "WRATH engine: %{public}@", safe);
        }
    }
}

void Sys_Shutdown(void) {
    SDL_Quit();
}

__attribute__((noreturn, format(printf, 1, 2)))
void Sys_Error(const char *format, ...) {
    char message[16384];
    va_list arguments;
    va_start(arguments, format);
    vsnprintf(message, sizeof(message), format, arguments);
    va_end(arguments);
    @autoreleasepool {
        NSString *text = [NSString stringWithUTF8String:message] ?: @"Unknown WRATH fatal error";
        [(gActiveRuntime ?: WrathRuntime.sharedRuntime) recordFatalError:text];
    }
    Host_Shutdown();
    longjmp(gRuntimeAbortTarget, 1);
}

char *Sys_ConsoleInput(void) {
    return nullptr;
}

char *Sys_GetClipboardData(void) {
    return nullptr;
}

unsigned int Sys_SDL_GetTicks(void) {
    return SDL_GetTicks();
}

void Sys_SDL_Delay(unsigned int milliseconds) {
    SDL_Delay(milliseconds);
}

} // extern "C"
