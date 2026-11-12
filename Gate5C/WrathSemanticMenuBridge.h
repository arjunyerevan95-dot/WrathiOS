#pragma once

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
int WrathIOSTouchNextKey(void);
int WrathIOSTouchTakeMenuRelease(void);
void WrathIOSTouchFrame( float *yaw, float *pitch, float *side, float *forward, unsigned *buttons);

#ifdef __cplusplus
}
#endif
