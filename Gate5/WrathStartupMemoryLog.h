// SPDX-License-Identifier: GPL-2.0-only
#pragma once
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// Fixed-size records keep startup evidence bounded even if initialization loops.
// Unwritten slots are absent/zero; readers sort valid records by sequence.
enum { WrathStartupRecordBytes = 512, WrathStartupRecordSlots = 256 };
struct WrathStartupMemorySample {
    uint64_t sequence, elapsedMS, footprint, available, thread;
    bool valid;
    long long a, b, c, d;
};

inline void WrathStartupSafeLabel(char (&out)[49], const char *input) {
    size_t n = 0;
    if (input) {
        // Callsite detail may be __FILE__; retain only its basename.
        const char *base = input;
        for (const char *p = input; *p; ++p)
            if (*p == '/' || *p == '\\') base = p + 1;
        for (; base[n] && n < sizeof(out) - 1; ++n) {
            unsigned char c = (unsigned char)base[n];
            out[n] = ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                      (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.') ? (char)c : '_';
        }
    }
    out[n] = 0;
}

inline bool WrathStartupEncodeRecord(char (&out)[WrathStartupRecordBytes],
                                    const WrathStartupMemorySample &sample,
                                    const char *event, const char *detail) {
    char safeEvent[49], safeDetail[49];
    WrathStartupSafeLabel(safeEvent, event);
    WrathStartupSafeLabel(safeDetail, detail);
    int n = snprintf(out, sizeof(out),
        "{\"seq\":%llu,\"elapsed_ms\":%llu,\"valid\":%s,\"footprint\":%llu,\"available\":%llu,"
        "\"thread\":%llu,\"event\":\"%s\",\"detail\":\"%s\",\"a\":%lld,\"b\":%lld,\"c\":%lld,\"d\":%lld}",
        (unsigned long long)sample.sequence, (unsigned long long)sample.elapsedMS,
        sample.valid ? "true" : "false", (unsigned long long)sample.footprint,
        (unsigned long long)sample.available, (unsigned long long)sample.thread, safeEvent, safeDetail,
        sample.a, sample.b, sample.c, sample.d);
    if (n <= 0 || (size_t)n >= sizeof(out)) return false;
    memset(out + n, ' ', sizeof(out) - (size_t)n);
    out[sizeof(out) - 1] = '\n';
    return true;
}

inline uint64_t WrathStartupRecordOffset(uint64_t sequence) {
    return (sequence % WrathStartupRecordSlots) * WrathStartupRecordBytes;
}
