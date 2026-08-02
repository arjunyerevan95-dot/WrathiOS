#include "WrathSemanticMenuModel.hpp"

#include <cassert>
#include <cmath>
#include <iostream>

using namespace wrathios::menu;

static bool Near(double left, double right) {
    return std::abs(left - right) < 0.001;
}

int main() {
    Point converted = ConvertUIKitPoint({478, 220}, {956, 440}, {640, 480});
    assert(Near(converted.x, 320));
    assert(Near(converted.y, 240));

    Snapshot snapshot;
    snapshot.menuIdentifier = 7;
    snapshot.menuSize = {640, 480};
    snapshot.entries = {
        {10, {100, 100, 120, 40}, true, true, 0},
        {11, {120, 110, 120, 40}, true, true, 1},
    };
    assert(HitTest(snapshot, {130, 120}, 0)->identifier == 11);
    assert(HitTest(snapshot, {98, 120}, 4)->identifier == 10);
    assert(!HitTest(snapshot, {20, 20}, 4));

    snapshot.entries.back().enabled = false;
    assert(HitTest(snapshot, {130, 120}, 0)->identifier == 10);
    snapshot.entries.front().visible = false;
    assert(!HitTest(snapshot, {130, 120}, 0));

    ActivationMachine activation;
    activation.Begin(7, 11, {130, 120});
    assert(activation.HasPointer());
    assert(activation.Advance(7, 10) == ButtonEvent::none);
    assert(activation.Stage() == ClickStage::positionWait);
    assert(activation.Advance(7, 11) == ButtonEvent::down);
    assert(activation.Advance(7, 11) == ButtonEvent::up);
    assert(activation.Advance(7, 11) == ButtonEvent::none);

    activation.Begin(7, 11, {130, 120});
    assert(activation.Advance(8, 11) == ButtonEvent::none);
    activation.Reset();
    assert(!activation.HasPointer());
    assert(activation.Stage() == ClickStage::idle);

    Snapshot replacement = snapshot;
    replacement.menuIdentifier = 8;
    replacement.entries = {{20, {200, 200, 80, 30}, true, true, 0}};
    assert(!HitTest(replacement, {130, 120}, 0));
    assert(HitTest(replacement, {220, 210}, 0)->identifier == 20);

    std::cout << "Gate 5C semantic menu model tests passed\n";
    return 0;
}
