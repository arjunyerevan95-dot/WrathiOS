// SPDX-License-Identifier: GPL-2.0-only
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

void WrathIOSRuntimeStage(const char *stage, const char *detail);
__attribute__((noreturn)) void WrathIOSRuntimeAbort(const char *message);

#ifdef __cplusplus
}
#endif
