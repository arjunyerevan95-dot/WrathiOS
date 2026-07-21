// SPDX-License-Identifier: GPL-2.0-only

#import "WrathGraphicsDiagnostic.h"

#if WRATH_GATE3_DIAGNOSTIC

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#include <SDL.h>
#include <SDL_syswm.h>
#include <OpenGLES/ES2/gl.h>

static SDL_Window *gWindow = nullptr;
static SDL_GLContext gContext = nullptr;
static GLuint gProgram = 0;
static GLint gPositionAttribute = -1;
static GLint gColorAttribute = -1;
static GLuint gFramebuffer = 0;
static CADisplayLink *gDisplayLink = nil;
static NSObject *gDisplayLinkTarget = nil;
static UIWindow *gNativeWindow = nil;
static UIView *gOverlayPanel = nil;
static UILabel *gStatusLabel = nil;
static UILabel *gFooterLabel = nil;
static NSString *gFailureMessage = nil;
static BOOL gStarted = NO;
static BOOL gActive = NO;
static BOOL gFailed = NO;
static NSUInteger gFrameCount = 0;
static NSUInteger gRecoveryCount = 0;
static NSUInteger gLaunchCount = 0;
static int gWindowWidth = 0;
static int gWindowHeight = 0;
static int gDrawableWidth = 0;
static int gDrawableHeight = 0;

static NSString *Gate3StringFromGL(const GLubyte *value) {
    if (value == nullptr) {
        return @"unavailable";
    }
    NSString *string = [NSString stringWithUTF8String:reinterpret_cast<const char *>(value)];
    return string ?: @"unavailable";
}

static void Gate3PresentBootstrapFailure(NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
        UIViewController *controller = window.rootViewController;
        if (controller.presentedViewController != nil) {
            controller = controller.presentedViewController;
        }
        if (controller == nil) {
            return;
        }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Gate 3 failed"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [controller presentViewController:alert animated:YES completion:nil];
    });
}

static void Gate3UpdateOverlay(void);

static void Gate3SetFailure(NSString *message) {
    gFailed = YES;
    gActive = NO;
    gFailureMessage = [message copy];
    gDisplayLink.paused = YES;

    if (gOverlayPanel != nil) {
        gOverlayPanel.backgroundColor = [UIColor colorWithRed:0.38 green:0.02 blue:0.03 alpha:0.92];
        Gate3UpdateOverlay();
    } else {
        Gate3PresentBootstrapFailure(message);
    }
}

static GLuint Gate3CompileShader(GLenum type, const char *source, NSString **errorMessage) {
    GLuint shader = glCreateShader(type);
    if (shader == 0) {
        if (errorMessage != nullptr) {
            *errorMessage = @"glCreateShader returned 0.";
        }
        return 0;
    }

    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);

    GLint compiled = GL_FALSE;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
    if (compiled == GL_TRUE) {
        return shader;
    }

    GLint logLength = 0;
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &logLength);
    NSMutableData *logData = [NSMutableData dataWithLength:MAX(logLength, 1)];
    GLsizei written = 0;
    glGetShaderInfoLog(shader, logLength, &written, static_cast<GLchar *>(logData.mutableBytes));
    NSString *log = [[NSString alloc] initWithBytes:logData.bytes
                                             length:MAX(written, 0)
                                           encoding:NSUTF8StringEncoding];
    if (errorMessage != nullptr) {
        *errorMessage = [NSString stringWithFormat:@"Shader compilation failed: %@", log ?: @"unknown error"];
    }
    glDeleteShader(shader);
    return 0;
}

static BOOL Gate3BuildProgram(NSString **errorMessage) {
    static const char *vertexSource =
        "attribute vec2 a_position;\n"
        "attribute vec4 a_color;\n"
        "varying lowp vec4 v_color;\n"
        "void main(void) {\n"
        "    gl_Position = vec4(a_position, 0.0, 1.0);\n"
        "    v_color = a_color;\n"
        "}\n";

    static const char *fragmentSource =
        "precision mediump float;\n"
        "varying lowp vec4 v_color;\n"
        "void main(void) {\n"
        "    gl_FragColor = v_color;\n"
        "}\n";

    GLuint vertexShader = Gate3CompileShader(GL_VERTEX_SHADER, vertexSource, errorMessage);
    if (vertexShader == 0) {
        return NO;
    }
    GLuint fragmentShader = Gate3CompileShader(GL_FRAGMENT_SHADER, fragmentSource, errorMessage);
    if (fragmentShader == 0) {
        glDeleteShader(vertexShader);
        return NO;
    }

    gProgram = glCreateProgram();
    glAttachShader(gProgram, vertexShader);
    glAttachShader(gProgram, fragmentShader);
    glBindAttribLocation(gProgram, 0, "a_position");
    glBindAttribLocation(gProgram, 1, "a_color");
    glLinkProgram(gProgram);

    glDeleteShader(vertexShader);
    glDeleteShader(fragmentShader);

    GLint linked = GL_FALSE;
    glGetProgramiv(gProgram, GL_LINK_STATUS, &linked);
    if (linked != GL_TRUE) {
        GLint logLength = 0;
        glGetProgramiv(gProgram, GL_INFO_LOG_LENGTH, &logLength);
        NSMutableData *logData = [NSMutableData dataWithLength:MAX(logLength, 1)];
        GLsizei written = 0;
        glGetProgramInfoLog(gProgram, logLength, &written, static_cast<GLchar *>(logData.mutableBytes));
        NSString *log = [[NSString alloc] initWithBytes:logData.bytes
                                                 length:MAX(written, 0)
                                               encoding:NSUTF8StringEncoding];
        if (errorMessage != nullptr) {
            *errorMessage = [NSString stringWithFormat:@"Program link failed: %@", log ?: @"unknown error"];
        }
        glDeleteProgram(gProgram);
        gProgram = 0;
        return NO;
    }

    gPositionAttribute = glGetAttribLocation(gProgram, "a_position");
    gColorAttribute = glGetAttribLocation(gProgram, "a_color");
    if (gPositionAttribute < 0 || gColorAttribute < 0) {
        if (errorMessage != nullptr) {
            *errorMessage = @"Required GLES2 shader attributes were not found.";
        }
        return NO;
    }
    return YES;
}

static BOOL Gate3RefreshNativeWindow(NSString **errorMessage) {
    if (gWindow == nullptr) {
        if (errorMessage != nullptr) {
            *errorMessage = @"SDL window is unavailable.";
        }
        return NO;
    }

    SDL_SysWMinfo windowInfo;
    SDL_VERSION(&windowInfo.version);
    if (SDL_GetWindowWMInfo(gWindow, &windowInfo) != SDL_TRUE || windowInfo.subsystem != SDL_SYSWM_UIKIT) {
        if (errorMessage != nullptr) {
            *errorMessage = [NSString stringWithFormat:@"SDL_GetWindowWMInfo failed: %s", SDL_GetError()];
        }
        return NO;
    }

    gNativeWindow = windowInfo.info.uikit.window;
    gFramebuffer = windowInfo.info.uikit.framebuffer;
    if (gNativeWindow == nil || gFramebuffer == 0) {
        if (errorMessage != nullptr) {
            *errorMessage = @"SDL did not expose a valid UIKit window and drawable framebuffer.";
        }
        return NO;
    }

    SDL_GetWindowSize(gWindow, &gWindowWidth, &gWindowHeight);
    SDL_GL_GetDrawableSize(gWindow, &gDrawableWidth, &gDrawableHeight);
    return gDrawableWidth > 0 && gDrawableHeight > 0;
}

static UILabel *Gate3CreateLabel(UIFont *font, UIColor *color) {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    label.adjustsFontSizeToFitWidth = NO;
    return label;
}

static void Gate3InstallOverlay(void) {
    if (gNativeWindow == nil || gOverlayPanel != nil) {
        return;
    }

    UIView *panel = [[UIView alloc] init];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.userInteractionEnabled = NO;
    panel.backgroundColor = [UIColor colorWithWhite:0.015 alpha:0.82];
    panel.layer.cornerRadius = 18.0;
    panel.layer.borderWidth = 1.0;
    panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;

    UILabel *eyebrow = Gate3CreateLabel([UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightSemibold],
                                        [UIColor colorWithRed:0.35 green:0.94 blue:0.88 alpha:1.0]);
    eyebrow.text = @"GATE 3 · SDL2 + OPENGL ES 2";

    UILabel *title = Gate3CreateLabel([UIFont systemFontOfSize:29.0 weight:UIFontWeightBold], UIColor.whiteColor);
    title.text = @"Graphics context diagnostic";

    gStatusLabel = Gate3CreateLabel([UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightRegular],
                                    [UIColor colorWithWhite:0.94 alpha:1.0]);

    gFooterLabel = Gate3CreateLabel([UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular],
                                    [UIColor colorWithWhite:0.72 alpha:1.0]);
    gFooterLabel.text = @"Background the app and return once. Rendering must continue and the recovery count must increase.";

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[eyebrow, title, gStatusLabel, gFooterLabel]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 11.0;
    stack.alignment = UIStackViewAlignmentFill;

    [panel addSubview:stack];
    [gNativeWindow addSubview:panel];

    UILayoutGuide *safe = gNativeWindow.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [panel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20.0],
        [panel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:20.0],
        [panel.widthAnchor constraintLessThanOrEqualToConstant:640.0],
        [panel.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-20.0],
        [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:20.0],
        [stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-20.0],
        [stack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:18.0],
        [stack.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-18.0]
    ]];

    gOverlayPanel = panel;
    Gate3UpdateOverlay();
}

static void Gate3UpdateOverlay(void) {
    if (gStatusLabel == nil) {
        return;
    }

    if (gFailed) {
        gStatusLabel.text = [NSString stringWithFormat:@"FAILED\n%@", gFailureMessage ?: @"Unknown Gate 3 failure."];
        gFooterLabel.text = @"Runtime startup remains disabled. Inspect the device log before continuing.";
        return;
    }

    UIEdgeInsets insets = gNativeWindow.safeAreaInsets;
    NSString *driver = SDL_GetCurrentVideoDriver() != nullptr
        ? [NSString stringWithUTF8String:SDL_GetCurrentVideoDriver()]
        : @"unknown";
    NSString *renderer = Gate3StringFromGL(glGetString(GL_RENDERER));
    NSString *version = Gate3StringFromGL(glGetString(GL_VERSION));

    gStatusLabel.text = [NSString stringWithFormat:
        @"Context: ACTIVE\n"
         "SDL driver: %@\n"
         "GL renderer: %@\n"
         "GL version: %@\n"
         "Window: %d × %d pt\n"
         "Drawable: %d × %d px\n"
         "Safe area: T%.0f L%.0f B%.0f R%.0f pt\n"
         "Launch count: %lu\n"
         "Frames presented: %lu\n"
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
        (unsigned long)gRecoveryCount];
}

static void Gate3RenderFrame(void) {
    if (!gStarted || !gActive || gFailed || gWindow == nullptr || gContext == nullptr) {
        return;
    }

    SDL_Event event;
    while (SDL_PollEvent(&event)) {
        if (event.type == SDL_QUIT) {
            gActive = NO;
        }
    }

    if (SDL_GL_MakeCurrent(gWindow, gContext) != 0) {
        Gate3SetFailure([NSString stringWithFormat:@"SDL_GL_MakeCurrent failed: %s", SDL_GetError()]);
        return;
    }

    NSString *refreshError = nil;
    if (!Gate3RefreshNativeWindow(&refreshError)) {
        Gate3SetFailure(refreshError ?: @"Drawable refresh failed.");
        return;
    }

    static const GLfloat vertices[] = {
         0.00f,  0.72f,   1.00f, 0.18f, 0.20f, 1.00f,
        -0.74f, -0.64f,   0.12f, 0.92f, 0.38f, 1.00f,
         0.74f, -0.64f,   0.15f, 0.42f, 1.00f, 1.00f
    };

    const GLfloat pulse = ((gFrameCount / 45U) % 2U) == 0U ? 0.02f : 0.055f;
    glBindFramebuffer(GL_FRAMEBUFFER, gFramebuffer);
    glViewport(0, 0, gDrawableWidth, gDrawableHeight);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    glClearColor(0.008f, 0.012f, 0.032f + pulse, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    glUseProgram(gProgram);
    glEnableVertexAttribArray((GLuint)gPositionAttribute);
    glEnableVertexAttribArray((GLuint)gColorAttribute);
    glVertexAttribPointer((GLuint)gPositionAttribute, 2, GL_FLOAT, GL_FALSE, 6 * sizeof(GLfloat), vertices);
    glVertexAttribPointer((GLuint)gColorAttribute, 4, GL_FLOAT, GL_FALSE, 6 * sizeof(GLfloat), vertices + 2);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glDisableVertexAttribArray((GLuint)gPositionAttribute);
    glDisableVertexAttribArray((GLuint)gColorAttribute);

    GLenum error = glGetError();
    if (error != GL_NO_ERROR) {
        Gate3SetFailure([NSString stringWithFormat:@"OpenGL ES reported error 0x%04x.", error]);
        return;
    }

    SDL_GL_SwapWindow(gWindow);
    ++gFrameCount;
    if ((gFrameCount % 30U) == 0U) {
        Gate3UpdateOverlay();
    }
}

@interface WrathGraphicsDisplayLinkTarget : NSObject
- (void)tick:(CADisplayLink *)displayLink;
@end

@implementation WrathGraphicsDisplayLinkTarget
- (void)tick:(CADisplayLink *)displayLink {
    (void)displayLink;
    Gate3RenderFrame();
}
@end

BOOL WrathGraphicsDiagnosticStart(void) {
    if (![NSThread isMainThread]) {
        __block BOOL result = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            result = WrathGraphicsDiagnosticStart();
        });
        return result;
    }

    if (gStarted) {
        return !gFailed;
    }

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    gLaunchCount = (NSUInteger)[defaults integerForKey:@"WrathGate3LaunchCount"] + 1U;
    [defaults setInteger:(NSInteger)gLaunchCount forKey:@"WrathGate3LaunchCount"];

    SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) != 0) {
        Gate3SetFailure([NSString stringWithFormat:@"SDL_Init failed: %s", SDL_GetError()]);
        return NO;
    }

    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 0);
    SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 0);
    SDL_GL_SetAttribute(SDL_GL_RETAINED_BACKING, 0);

    CGRect bounds = UIScreen.mainScreen.bounds;
    int width = MAX((int)CGRectGetWidth(bounds), 1);
    int height = MAX((int)CGRectGetHeight(bounds), 1);
    gWindow = SDL_CreateWindow("WrathiOS Gate 3",
                               SDL_WINDOWPOS_CENTERED,
                               SDL_WINDOWPOS_CENTERED,
                               width,
                               height,
                               SDL_WINDOW_OPENGL | SDL_WINDOW_FULLSCREEN |
                               SDL_WINDOW_ALLOW_HIGHDPI | SDL_WINDOW_SHOWN);
    if (gWindow == nullptr) {
        Gate3SetFailure([NSString stringWithFormat:@"SDL_CreateWindow failed: %s", SDL_GetError()]);
        return NO;
    }

    gContext = SDL_GL_CreateContext(gWindow);
    if (gContext == nullptr) {
        Gate3SetFailure([NSString stringWithFormat:@"SDL_GL_CreateContext failed: %s", SDL_GetError()]);
        return NO;
    }
    if (SDL_GL_MakeCurrent(gWindow, gContext) != 0) {
        Gate3SetFailure([NSString stringWithFormat:@"SDL_GL_MakeCurrent failed: %s", SDL_GetError()]);
        return NO;
    }
    (void)SDL_GL_SetSwapInterval(1);

    NSString *programError = nil;
    if (!Gate3BuildProgram(&programError)) {
        Gate3SetFailure(programError ?: @"GLES2 shader setup failed.");
        return NO;
    }

    NSString *windowError = nil;
    if (!Gate3RefreshNativeWindow(&windowError)) {
        Gate3SetFailure(windowError ?: @"SDL UIKit window setup failed.");
        return NO;
    }

    gStarted = YES;
    gActive = YES;
    Gate3InstallOverlay();
    Gate3RenderFrame();

    gDisplayLinkTarget = [[WrathGraphicsDisplayLinkTarget alloc] init];
    gDisplayLink = [CADisplayLink displayLinkWithTarget:gDisplayLinkTarget selector:@selector(tick:)];
    gDisplayLink.preferredFramesPerSecond = 60;
    [gDisplayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    return YES;
}

NSString *WrathGraphicsDiagnosticStatusText(void) {
    if (gFailed) {
        return gFailureMessage ?: @"Gate 3 failed.";
    }
    if (gStarted) {
        return [NSString stringWithFormat:@"Gate 3 active at %d × %d drawable pixels.", gDrawableWidth, gDrawableHeight];
    }
    return @"Gate 3 graphics diagnostic has not started.";
}

void WrathGraphicsDiagnosticWillResignActive(void) {
    if (!gStarted) {
        return;
    }
    gActive = NO;
    gDisplayLink.paused = YES;
    Gate3UpdateOverlay();
}

void WrathGraphicsDiagnosticDidEnterBackground(void) {
    if (!gStarted) {
        return;
    }
    gActive = NO;
    gDisplayLink.paused = YES;
}

void WrathGraphicsDiagnosticWillEnterForeground(void) {
    if (!gStarted || gFailed) {
        return;
    }
    gFooterLabel.text = @"Restoring the SDL2 OpenGL ES context…";
}

void WrathGraphicsDiagnosticDidBecomeActive(void) {
    if (!gStarted || gFailed) {
        return;
    }

    if (SDL_GL_MakeCurrent(gWindow, gContext) != 0) {
        Gate3SetFailure([NSString stringWithFormat:@"Context recovery failed: %s", SDL_GetError()]);
        return;
    }

    NSString *windowError = nil;
    if (!Gate3RefreshNativeWindow(&windowError) || glGetString(GL_VERSION) == nullptr) {
        Gate3SetFailure(windowError ?: @"OpenGL ES context was unavailable after foregrounding.");
        return;
    }

    ++gRecoveryCount;
    gActive = YES;
    gDisplayLink.paused = NO;
    gFooterLabel.text = @"Background the app and return once. Rendering must continue and the recovery count must increase.";
    Gate3RenderFrame();
    Gate3UpdateOverlay();
}

void WrathGraphicsDiagnosticWillTerminate(void) {
    [gDisplayLink invalidate];
    gDisplayLink = nil;
    gDisplayLinkTarget = nil;

    if (gProgram != 0) {
        glDeleteProgram(gProgram);
        gProgram = 0;
    }
    if (gContext != nullptr) {
        SDL_GL_DeleteContext(gContext);
        gContext = nullptr;
    }
    if (gWindow != nullptr) {
        SDL_DestroyWindow(gWindow);
        gWindow = nullptr;
    }
    SDL_QuitSubSystem(SDL_INIT_VIDEO | SDL_INIT_EVENTS);
    gStarted = NO;
    gActive = NO;
}

#else

BOOL WrathGraphicsDiagnosticStart(void) {
    return NO;
}

NSString *WrathGraphicsDiagnosticStatusText(void) {
    return @"Gate 3 graphics diagnostic is not enabled in this build.";
}

void WrathGraphicsDiagnosticWillResignActive(void) {}
void WrathGraphicsDiagnosticDidEnterBackground(void) {}
void WrathGraphicsDiagnosticWillEnterForeground(void) {}
void WrathGraphicsDiagnosticDidBecomeActive(void) {}
void WrathGraphicsDiagnosticWillTerminate(void) {}

#endif
