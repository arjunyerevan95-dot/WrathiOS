// SPDX-License-Identifier: GPL-2.0-only
#include "WrathIOSInputMath.hpp"

#include <cassert>
#include <cmath>

namespace {

bool near(float actual, float expected, float tolerance = 0.001f) {
    return std::fabs(actual - expected) <= tolerance;
}

} // namespace

int main() {
    using namespace wrathios::input;

    Point center = normalizedToLogical(0.5f, 0.5f, 956, 440);
    assert(near(center.x, 477.5f));
    assert(near(center.y, 219.5f));

    Point virtualCenter = logicalToVirtual(center, 956, 440, 640, 480);
    assert(near(virtualCenter.x, 319.665f));
    assert(near(virtualCenter.y, 239.455f));

    assert(!isGameplayLookZone(0.3499f));
    assert(isGameplayLookZone(0.35f));
    assert(isGameplayLookZone(1.0f));

    Point swipe = swipeDelta(0.50f, 0.50f, 0.60f, 0.40f, 956, 440);
    assert(near(swipe.x, 191.2f));
    assert(near(swipe.y, -72.6f));

    Point left = mapGyroRotationRate(LandscapeOrientation::left, 2.0f, 3.0f);
    assert(near(left.x, 2.0f));
    assert(near(left.y, -3.0f));

    Point right = mapGyroRotationRate(LandscapeOrientation::right, 2.0f, 3.0f);
    assert(near(right.x, -2.0f));
    assert(near(right.y, 3.0f));

    Point unknown = mapGyroRotationRate(LandscapeOrientation::unknown, 2.0f, 3.0f);
    assert(near(unknown.x, 0.0f));
    assert(near(unknown.y, 0.0f));

    GestureState gesture = {true, 42, 0.2f, 0.3f, 12.0f, true, true, 9.0f, -4.0f};
    resetGestureState(gesture);
    assert(!gesture.active);
    assert(gesture.fingerID == 0);
    assert(near(gesture.previousX, 0.0f));
    assert(near(gesture.previousY, 0.0f));
    assert(near(gesture.movement, 0.0f));
    assert(!gesture.drag);
    assert(!gesture.movementReported);
    assert(near(gesture.swipeX, 0.0f));
    assert(near(gesture.swipeY, 0.0f));
    return 0;
}
