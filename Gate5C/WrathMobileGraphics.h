#pragma once
#include <math.h>
/* Fractions apply independently to native drawable width and height.
 * A missing key is a mobile default, never a persistent settings migration. */
static inline double WrathMobileRenderScale(int hasSaved, double value) {
    if (!hasSaved) return 0.5;
    if (fabs(value - 0.67) < 0.001) return 0.67;
    if (fabs(value - 0.5) < 0.001) return 0.5;
    if (fabs(value - 0.33) < 0.001) return 0.33;
    return 1.0; /* Retain legacy behavior for saved Native/unknown values. */
}
static inline int WrathMobileRenderScaleIndex(double value) {
    return value == 0.67 ? 1 : value == 0.5 ? 2 : value == 0.33 ? 3 : 0;
}
static inline int WrathMobileMSAASamples(int hasSaved, int value, int configured) {
    if (hasSaved && (value == 1 || value == 2 || value == 4)) return value;
    return configured; /* Saved engine settings and driver fallback stay valid. */
}
