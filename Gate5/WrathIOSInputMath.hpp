// SPDX-License-Identifier: GPL-2.0-only
#pragma once

#include <cstdint>

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

enum class MenuButtonPhase {
    idle = 0,
    waitingForPosition = 1,
    down = 2,
};

struct MenuCursorState {
    bool valid;
    Point logical;
    std::uint64_t frame;
    std::uint64_t positionGeneration;
    std::uint64_t appliedGeneration;
    std::uint64_t clickGeneration;
    std::uint64_t earliestDownFrame;
    std::uint64_t downFrame;
    MenuButtonPhase buttonPhase;
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
Point mapGyroRotationRate(LandscapeOrientation orientation,
                          float deviceRateX,
                          float deviceRateY,
                          float deviceRateZ);
void beginMenuFrame(MenuCursorState &state);
void updateMenuCursor(MenuCursorState &state, Point logical);
bool getMenuCursor(const MenuCursorState &state, Point &logical);
void markMenuCursorApplied(MenuCursorState &state);
bool queueMenuTap(MenuCursorState &state);
int consumeMenuButtonPhase(MenuCursorState &state);
void resetMenuCursor(MenuCursorState &state);
void resetGestureState(GestureState &state);

} // namespace wrathios::input
