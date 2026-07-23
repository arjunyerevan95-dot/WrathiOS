// SPDX-License-Identifier: GPL-2.0-only
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef enum WrathIOSInputMode {
    WrathIOSInputModeOther = 0,
    WrathIOSInputModeMenu = 1,
    WrathIOSInputModeGameplay = 2,
} WrathIOSInputMode;

void WrathIOSInputSetMode(WrathIOSInputMode mode, int logicalWidth, int logicalHeight);
void WrathIOSInputFingerDown(long long fingerID, float normalizedX, float normalizedY);
void WrathIOSInputFingerMotion(long long fingerID, float normalizedX, float normalizedY);
void WrathIOSInputFingerUp(long long fingerID, float normalizedX, float normalizedY);
int WrathIOSInputConsumeMenuPosition(float *logicalX, float *logicalY);
int WrathIOSInputConsumeMenuButtonPhase(void);
void WrathIOSInputConsumeGameplayLook(float *mouseDeltaX, float *mouseDeltaY);
void WrathIOSInputReset(const char *reason);
void WrathIOSInputEnteredForeground(void);

#ifdef __cplusplus
}
#endif
