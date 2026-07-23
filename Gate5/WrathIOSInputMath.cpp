// SPDX-License-Identifier: GPL-2.0-only
#include "WrathIOSInputMath.hpp"

#include <algorithm>

namespace wrathios::input {

Point normalizedToLogical(float normalizedX, float normalizedY, int logicalWidth, int logicalHeight) {
    const float maximumX = static_cast<float>(std::max(0, logicalWidth - 1));
    const float maximumY = static_cast<float>(std::max(0, logicalHeight - 1));
    return {
        std::clamp(normalizedX, 0.0f, 1.0f) * maximumX,
        std::clamp(normalizedY, 0.0f, 1.0f) * maximumY,
    };
}

Point logicalToVirtual(Point logical,
                       int logicalWidth,
                       int logicalHeight,
                       int virtualWidth,
                       int virtualHeight) {
    if (logicalWidth <= 0 || logicalHeight <= 0) {
        return {0.0f, 0.0f};
    }
    return {
        logical.x * static_cast<float>(virtualWidth) / static_cast<float>(logicalWidth),
        logical.y * static_cast<float>(virtualHeight) / static_cast<float>(logicalHeight),
    };
}

bool isGameplayLookZone(float normalizedX) {
    return normalizedX >= kGameplayLookZoneStart && normalizedX <= 1.0f;
}

Point swipeDelta(float previousX,
                 float previousY,
                 float currentX,
                 float currentY,
                 int logicalWidth,
                 int logicalHeight) {
    return {
        (currentX - previousX) * static_cast<float>(logicalWidth) * kSwipeSensitivityX,
        (currentY - previousY) * static_cast<float>(logicalHeight) * kSwipeSensitivityY,
    };
}

Point mapGyroRotationRate(LandscapeOrientation orientation, float deviceRateX, float deviceRateY) {
    switch (orientation) {
        case LandscapeOrientation::left:
            return {deviceRateX, -deviceRateY};
        case LandscapeOrientation::right:
            return {-deviceRateX, deviceRateY};
        case LandscapeOrientation::unknown:
            return {0.0f, 0.0f};
    }
}

void resetGestureState(GestureState &state) {
    state = {};
}

} // namespace wrathios::input
