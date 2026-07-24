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

Point mapGyroRotationRate(LandscapeOrientation orientation,
                          float deviceRateX,
                          float deviceRateY,
                          float deviceRateZ) {
    (void)deviceRateZ;
    switch (orientation) {
        case LandscapeOrientation::left:
            return {deviceRateX, -deviceRateY};
        case LandscapeOrientation::right:
            return {-deviceRateX, deviceRateY};
        case LandscapeOrientation::unknown:
            return {0.0f, 0.0f};
    }
}

void beginMenuFrame(MenuCursorState &state) {
    state.frame += 1;
}

void updateMenuCursor(MenuCursorState &state, Point logical) {
    state.valid = true;
    state.logical = logical;
    state.positionGeneration += 1;
}

bool getMenuCursor(const MenuCursorState &state, Point &logical) {
    if (!state.valid) {
        return false;
    }
    logical = state.logical;
    return true;
}

void markMenuCursorApplied(MenuCursorState &state) {
    if (state.valid) {
        state.appliedGeneration = state.positionGeneration;
    }
}

bool queueMenuTap(MenuCursorState &state) {
    if (!state.valid || state.buttonPhase != MenuButtonPhase::idle) {
        return false;
    }
    state.clickGeneration = state.positionGeneration;
    // Finger events are polled after the per-frame cursor application. Leave
    // one complete menu draw between applying the position and button down.
    state.earliestDownFrame = state.frame + 2;
    state.buttonPhase = MenuButtonPhase::waitingForPosition;
    return true;
}

int consumeMenuButtonPhase(MenuCursorState &state) {
    if (state.buttonPhase == MenuButtonPhase::waitingForPosition) {
        if (state.appliedGeneration < state.clickGeneration ||
            state.frame < state.earliestDownFrame) {
            return 0;
        }
        state.buttonPhase = MenuButtonPhase::down;
        state.downFrame = state.frame;
        return 1;
    }
    if (state.buttonPhase == MenuButtonPhase::down && state.frame > state.downFrame) {
        state.buttonPhase = MenuButtonPhase::idle;
        return -1;
    }
    return 0;
}

void resetMenuCursor(MenuCursorState &state) {
    state = {};
}

void resetGestureState(GestureState &state) {
    state = {};
}

} // namespace wrathios::input
