#include "WrathSemanticMenuModel.hpp"

#include <algorithm>

namespace wrathios::menu {

Point ConvertUIKitPoint(Point point, Size viewSize, Size menuSize) {
    if (viewSize.width <= 0 || viewSize.height <= 0 || menuSize.width <= 0 || menuSize.height <= 0) {
        return {};
    }
    return {
        std::clamp(point.x / viewSize.width * menuSize.width, 0.0, menuSize.width),
        std::clamp(point.y / viewSize.height * menuSize.height, 0.0, menuSize.height),
    };
}

std::optional<Entry> HitTest(const Snapshot &snapshot, Point point, double hitSlop) {
    for (auto iterator = snapshot.entries.rbegin(); iterator != snapshot.entries.rend(); ++iterator) {
        const Entry &entry = *iterator;
        if (!entry.visible || !entry.enabled) {
            continue;
        }
        const double minimumX = entry.bounds.x - hitSlop;
        const double minimumY = entry.bounds.y - hitSlop;
        const double maximumX = entry.bounds.x + entry.bounds.width + hitSlop;
        const double maximumY = entry.bounds.y + entry.bounds.height + hitSlop;
        if (point.x >= minimumX && point.x <= maximumX && point.y >= minimumY && point.y <= maximumY) {
            return entry;
        }
    }
    return std::nullopt;
}

void ActivationMachine::Begin(int menuIdentifier, int entryIdentifier, Point pointer) {
    menuIdentifier_ = menuIdentifier;
    entryIdentifier_ = entryIdentifier;
    pointer_ = pointer;
    stage_ = ClickStage::positionWait;
    hasPointer_ = true;
}

ButtonEvent ActivationMachine::Advance(int menuIdentifier, int hoverIdentifier) {
    if (stage_ == ClickStage::positionWait) {
        if (menuIdentifier != menuIdentifier_ || hoverIdentifier != entryIdentifier_) {
            return ButtonEvent::none;
        }
        stage_ = ClickStage::downSent;
        return ButtonEvent::down;
    }
    if (stage_ == ClickStage::downSent) {
        stage_ = ClickStage::upSent;
        return ButtonEvent::up;
    }
    if (stage_ == ClickStage::upSent) {
        stage_ = ClickStage::idle;
    }
    return ButtonEvent::none;
}

void ActivationMachine::Reset() {
    menuIdentifier_ = 0;
    entryIdentifier_ = 0;
    stage_ = ClickStage::idle;
    hasPointer_ = false;
}

ClickStage ActivationMachine::Stage() const { return stage_; }
Point ActivationMachine::Pointer() const { return pointer_; }
int ActivationMachine::EntryIdentifier() const { return entryIdentifier_; }
bool ActivationMachine::HasPointer() const { return hasPointer_; }

const char *ClickStageName(ClickStage stage) {
    switch (stage) {
        case ClickStage::idle: return "none";
        case ClickStage::positionWait: return "position wait";
        case ClickStage::downSent: return "down";
        case ClickStage::upSent: return "up";
    }
    return "unknown";
}

} // namespace wrathios::menu
