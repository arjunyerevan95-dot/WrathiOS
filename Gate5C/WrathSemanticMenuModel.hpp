#pragma once

#include <optional>
#include <string>
#include <vector>

namespace wrathios::menu {

struct Point {
    double x = 0;
    double y = 0;
};

struct Size {
    double width = 0;
    double height = 0;
};

struct Rect {
    double x = 0;
    double y = 0;
    double width = 0;
    double height = 0;
};

struct Entry {
    int identifier = 0;
    Rect bounds;
    bool visible = true;
    bool enabled = true;
    int order = 0;
};

struct Snapshot {
    int menuIdentifier = 0;
    Size menuSize;
    std::vector<Entry> entries;
    unsigned long long generation = 0;
};

Point ConvertUIKitPoint(Point point, Size viewSize, Size menuSize);
std::optional<Entry> HitTest(const Snapshot &snapshot, Point menuPoint, double hitSlop);

enum class ClickStage {
    idle,
    positionWait,
    downSent,
    upSent,
};

enum class ButtonEvent {
    none,
    down,
    up,
};

class ActivationMachine {
public:
    void Begin(int menuIdentifier, int entryIdentifier, Point pointer);
    ButtonEvent Advance(int menuIdentifier, int hoverIdentifier);
    void Reset();

    ClickStage Stage() const;
    Point Pointer() const;
    int EntryIdentifier() const;
    bool HasPointer() const;

private:
    int menuIdentifier_ = 0;
    int entryIdentifier_ = 0;
    Point pointer_;
    ClickStage stage_ = ClickStage::idle;
    bool hasPointer_ = false;
};

const char *ClickStageName(ClickStage stage);

} // namespace wrathios::menu
