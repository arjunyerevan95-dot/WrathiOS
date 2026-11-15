// SPDX-License-Identifier: GPL-2.0-only
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

void WrathIOSRuntimeStage(const char *stage, const char *detail);
__attribute__((noreturn)) void WrathIOSRuntimeAbort(const char *message);

#ifdef WRATH_IOS_GLES3
void WrathIOSStartupMemoryCheckpoint(const char *event, const char *detail,
                                     long long a, long long b, long long c, long long d);
void WrathIOSStartupMemoryFinish(void);
#endif

#ifdef __cplusplus
}
#endif
