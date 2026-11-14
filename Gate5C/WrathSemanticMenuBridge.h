#pragma once
#include "WrathReadableDimensions.h"

#ifdef __cplusplus
extern "C" {
#endif

const unsigned char *WrathIOSGate5CMenuProgramData(long long *size);

void WrathIOSGate5CSnapshotBegin(int menuIdentifier, float menuWidth, float menuHeight);
void WrathIOSGate5CSnapshotEntry(int entryIdentifier,
                                float x,
                                float y,
                                float width,
                                float height,
                                int flags,
                                int order);
void WrathIOSGate5CSnapshotEnd(int hoverIdentifier);

int WrathIOSGate5CPointer(float *x, float *y);
int WrathIOSGate5CNextButtonEvent(void);
void WrathIOSGate5CSetMenuActive(int active);
void WrathIOSTouchSetMode(int menu, int game);
void WrathIOSTouchSetCapture(int captured);
void WrathIOSTouchBeginControllerFrame(void);
void WrathIOSControllerTakeRelativeLook(float *yaw,float *pitch);
int WrathIOSTouchNextKey(void);
void WrathIOSTouchTextFocus(int active);
int WrathIOSTouchNextText(void);
int WrathIOSTouchMenuPad(float *x,float *y);
int WrathIOSTouchNextPadButton(void);
const char *WrathIOSTouchActionCommand(int action,int down);
int WrathIOSTouchTakeMenuRelease(void);
void WrathIOSLogicalWindowSize(int *width,int *height);
void WrathIOSTouchFrame( float *yaw, float *pitch, float *side, float *forward, unsigned *buttons);

#ifdef __cplusplus
}
#endif
