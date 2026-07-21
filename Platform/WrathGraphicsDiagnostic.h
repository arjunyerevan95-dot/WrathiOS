// SPDX-License-Identifier: GPL-2.0-only

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Starts the bounded SDL2/OpenGL ES graphics diagnostic on the main thread.
/// This does not call Host_Main or access commercial WRATH data.
FOUNDATION_EXPORT BOOL WrathGraphicsDiagnosticStart(void);
FOUNDATION_EXPORT NSString *WrathGraphicsDiagnosticStatusText(void);

FOUNDATION_EXPORT void WrathGraphicsDiagnosticWillResignActive(void);
FOUNDATION_EXPORT void WrathGraphicsDiagnosticDidEnterBackground(void);
FOUNDATION_EXPORT void WrathGraphicsDiagnosticWillEnterForeground(void);
FOUNDATION_EXPORT void WrathGraphicsDiagnosticDidBecomeActive(void);
FOUNDATION_EXPORT void WrathGraphicsDiagnosticWillTerminate(void);

NS_ASSUME_NONNULL_END
