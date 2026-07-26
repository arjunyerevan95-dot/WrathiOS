// SPDX-License-Identifier: GPL-2.0-only
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef enum WrathIOSInputMode {
    WrathIOSInputModeOther = 0,
    WrathIOSInputModeMenu = 1,
    WrathIOSInputModeMenuText = 2,
    WrathIOSInputModeGameplay = 3,
} WrathIOSInputMode;

typedef enum WrathIOSCursorWriter {
    WrathIOSCursorWriterUnknown = 0,
    WrathIOSCursorWriterBridgeDirectTouch = 1,
    WrathIOSCursorWriterVidCenterInit = 2,
    WrathIOSCursorWriterSDLMouseMotion = 3,
    WrathIOSCursorWriterSDLMouseState = 4,
    WrathIOSCursorWriterMenuTransitionInit = 5,
    WrathIOSCursorWriterLegacyTouch = 6,
    WrathIOSCursorWriterMenuVMBuiltin = 7,
    WrathIOSCursorWriterMenuQCGlobal = 8,
} WrathIOSCursorWriter;

void WrathIOSInputBeginFrame(void);
void WrathIOSInputSetMode(WrathIOSInputMode mode, int logicalWidth, int logicalHeight);
void WrathIOSInputFingerDown(long long fingerID, float normalizedX, float normalizedY);
void WrathIOSInputFingerMotion(long long fingerID, float normalizedX, float normalizedY);
void WrathIOSInputFingerUp(long long fingerID, float normalizedX, float normalizedY);
int WrathIOSInputGetMenuPosition(float *logicalX, float *logicalY);
void WrathIOSInputMarkMenuPositionApplied(void);
void WrathIOSInputMarkMenuHoverUpdated(void);
int WrathIOSInputConsumeMenuButtonPhase(void);
void WrathIOSInputConsumeGameplayLook(float *mouseDeltaX, float *mouseDeltaY);
void WrathIOSInputSetTextEntryActive(int active);
void WrathIOSInputDismissTextEntry(void);
void WrathIOSInputReset(const char *reason);
void WrathIOSInputEnteredForeground(void);

// Gate 5B Revision 4 runtime-observable diagnostics. These calls are narrow
// instrumentation boundaries used by the derived engine sources.
void WrathIOSInputTraceEngineState(int keyDest, int consoleActive, int textRequested);
void WrathIOSInputTraceCursorWrite(WrathIOSCursorWriter writer, float x, float y);
void WrathIOSInputTraceCursorFinal(float x, float y);
void WrathIOSInputTraceMenuVMRead(float engineX,
                                  float engineY,
                                  float virtualX,
                                  float virtualY,
                                  int usedBridgeCoordinate);
void WrathIOSInputTraceMenuQCPointerApplied(float logicalX,
                                            float logicalY,
                                            float virtualX,
                                            float virtualY);
void WrathIOSInputTraceMenuState(int menuIdentifier,
                                 int selectedIdentifier,
                                 int hoverIdentifier,
                                 float menuCursorX,
                                 float menuCursorY,
                                 int profileFieldDetector,
                                 int profileIdentifier,
                                 int profileFieldIdentifier,
                                 int profileTextIdentifier,
                                 int profileAcceptIdentifier,
                                 int profileScreenActive);
void WrathIOSInputTraceButtonPhase(int phase);
void WrathIOSInputTraceSDLTextEvent(void);
void WrathIOSInputTraceGyro(float rawX,
                            float rawY,
                            float rawZ,
                            float mappedYaw,
                            float mappedPitch,
                            int sampleApplied);

// Project-owned bridge-to-diagnostics calls.
void WrathIOSDiagnosticsSetMode(WrathIOSInputMode mode);
void WrathIOSDiagnosticsBeginFrame(void);
void WrathIOSDiagnosticsStoredTouch(float x, float y);
void WrathIOSDiagnosticsReset(const char *reason);
void WrathIOSDiagnosticsRequestTextEntry(int active);
void WrathIOSDiagnosticsSetMotionRunning(int running);
const char *WrathIOSInputDiagnosticContractMarker(void);

#ifdef __cplusplus
}
#endif
