// SPDX-License-Identifier: GPL-2.0-only
#pragma once

namespace wrathios::input {

constexpr float kMenuTapThresholdFraction = 0.012f;
constexpr float kGameplayLookZoneStart = 0.35f;
constexpr float kSwipeSensitivityX = 2.0f;
constexpr float kSwipeSensitivityY = 1.65f;
constexpr float kGyroDeadZoneRadiansPerSecond = 0.015f;
constexpr float kGyroMouseUnitsPerRadian = 900.0f;

enum class LandscapeOrientation {
    unknown = 0,
    left = 3,
    right = 4,
};

struct Point {
    float x;
    float y;
};

struct GestureState {
    bool active;
    long long fingerID;
    float previousX;
    float previousY;
    float movement;
    bool drag;
    bool movementReported;
    float swipeX;
    float swipeY;
};

Point normalizedToLogical(float normalizedX, float normalizedY, int logicalWidth, int logicalHeight);
Point logicalToVirtual(Point logical, int logicalWidth, int logicalHeight, int virtualWidth, int virtualHeight);
bool isGameplayLookZone(float normalizedX);
Point swipeDelta(float previousX,
                 float previousY,
                 float currentX,
                 float currentY,
                 int logicalWidth,
                 int logicalHeight);
Point mapGyroRotationRate(LandscapeOrientation orientation, float deviceRateX, float deviceRateY);
void resetGestureState(GestureState &state);

} // namespace wrathios::input
