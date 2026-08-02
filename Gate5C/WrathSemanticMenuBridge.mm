#import "WrathSemanticMenuBridge.h"

#import <UIKit/UIKit.h>

#include "WrathSemanticMenuModel.hpp"

#include <mutex>

namespace {

namespace SemanticMenu = wrathios::menu;

constexpr double kSemanticHitSlop = 4.0;
constexpr NSInteger kTouchSurfaceTag = 0x57524335;

struct BridgeState {
    std::mutex mutex;
    SemanticMenu::Snapshot building;
    SemanticMenu::Snapshot published;
    SemanticMenu::ActivationMachine activation;
    int hoverIdentifier = 0;
    bool menuActive = false;
    unsigned long long hits = 0;
    unsigned long long misses = 0;
    SemanticMenu::Point lastTouch;
    SemanticMenu::Rect lastHitBounds;
    int lastHitIdentifier = 0;
    bool pointerAcknowledged = false;
};

BridgeState &State() {
    static BridgeState state;
    return state;
}

NSString *DiagnosticText() {
    BridgeState &state = State();
    std::scoped_lock lock(state.mutex);
    return [NSString stringWithFormat:
        @"Gate 5C semantic adapter\nmenu=%d entries=%lu touch=(%.0f,%.0f)\n"
         "hit=%d [%.0f,%.0f %.0fx%.0f] ack=%@ hover=%d\n"
         "click=%s hit/miss=%llu/%llu",
        state.published.menuIdentifier,
        static_cast<unsigned long>(state.published.entries.size()),
        state.lastTouch.x,
        state.lastTouch.y,
        state.lastHitIdentifier,
        state.lastHitBounds.x,
        state.lastHitBounds.y,
        state.lastHitBounds.width,
        state.lastHitBounds.height,
        state.pointerAcknowledged ? @"yes" : @"no",
        state.hoverIdentifier,
        SemanticMenu::ClickStageName(state.activation.Stage()),
        state.hits,
        state.misses];
}

} // namespace

@interface WrathSemanticTouchSurface : UIView
@property(nonatomic, strong) UILabel *diagnosticLabel;
@end

@implementation WrathSemanticTouchSurface

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) {
        return nil;
    }
    self.backgroundColor = UIColor.clearColor;
    self.multipleTouchEnabled = NO;
    self.exclusiveTouch = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, 330, 86)];
    label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.58];
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    label.numberOfLines = 4;
    label.userInteractionEnabled = NO;
    label.layer.cornerRadius = 5;
    label.layer.masksToBounds = YES;
    label.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self addSubview:label];
    self.diagnosticLabel = label;
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(runtimeBecameInactive:)
                                               name:UIApplicationWillResignActiveNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(runtimeBecameInactive:)
                                               name:UIApplicationDidEnterBackgroundNotification
                                             object:nil];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)runtimeBecameInactive:(NSNotification *)notification {
    (void)notification;
    WrathIOSGate5CSetMenuActive(0);
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (touches.count != 1) {
        return;
    }
    UITouch *touch = touches.anyObject;
    CGPoint uiPoint = [touch locationInView:self];

    wrathios::menu::Snapshot snapshot;
    {
        BridgeState &state = State();
        std::scoped_lock lock(state.mutex);
        if (!state.menuActive) {
            return;
        }
        snapshot = state.published;
    }

    wrathios::menu::Point menuPoint = wrathios::menu::ConvertUIKitPoint(
        {uiPoint.x, uiPoint.y},
        {self.bounds.size.width, self.bounds.size.height},
        snapshot.menuSize);
    std::optional<wrathios::menu::Entry> hit =
        wrathios::menu::HitTest(snapshot, menuPoint, kSemanticHitSlop);

    {
        BridgeState &state = State();
        std::scoped_lock lock(state.mutex);
        state.lastTouch = menuPoint;
        if (hit) {
            state.lastHitIdentifier = hit->identifier;
            state.lastHitBounds = hit->bounds;
            state.pointerAcknowledged = false;
            state.activation.Begin(snapshot.menuIdentifier, hit->identifier, menuPoint);
            ++state.hits;
        } else {
            state.lastHitIdentifier = 0;
            state.lastHitBounds = {};
            ++state.misses;
        }
    }
    self.diagnosticLabel.text = DiagnosticText();
}

@end

namespace {

UIWindow *ActiveWindow() {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows.reverseObjectEnumerator) {
            if (window.hidden || window.alpha <= 0) {
                continue;
            }
            if (window.isKeyWindow) {
                return window;
            }
        }
        for (UIWindow *window in windowScene.windows.reverseObjectEnumerator) {
            if (!window.hidden && window.alpha > 0) {
                return window;
            }
        }
    }
    return nil;
}

WrathSemanticTouchSurface *TouchSurface(BOOL create) {
    UIWindow *window = ActiveWindow();
    if (!window) {
        return nil;
    }
    WrathSemanticTouchSurface *surface = (WrathSemanticTouchSurface *)[window viewWithTag:kTouchSurfaceTag];
    if (!surface && create) {
        surface = [[WrathSemanticTouchSurface alloc] initWithFrame:window.bounds];
        surface.tag = kTouchSurfaceTag;
        [window addSubview:surface];
    }
    if (surface) {
        [window bringSubviewToFront:surface];
    }
    return surface;
}

void RefreshSurface() {
    BridgeState &state = State();
    bool active;
    {
        std::scoped_lock lock(state.mutex);
        active = state.menuActive;
    }
    WrathSemanticTouchSurface *surface = TouchSurface(active);
    surface.hidden = !active;
    surface.userInteractionEnabled = active;
    if (active) {
        surface.diagnosticLabel.text = DiagnosticText();
    }
}

} // namespace

const unsigned char *WrathIOSGate5CMenuProgramData(long long *size) {
    static NSData *program = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURL *url = [NSBundle.mainBundle URLForResource:@"wrathios-menu" withExtension:@"dat"];
        program = url ? [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil] : nil;
    });
    if (size) {
        *size = static_cast<long long>(program.length);
    }
    return static_cast<const unsigned char *>(program.bytes);
}

void WrathIOSGate5CSnapshotBegin(int menuIdentifier, float menuWidth, float menuHeight) {
    BridgeState &state = State();
    std::scoped_lock lock(state.mutex);
    if (state.building.menuIdentifier != menuIdentifier &&
        state.activation.Stage() == wrathios::menu::ClickStage::positionWait) {
        state.activation.Reset();
    }
    state.building = {};
    state.building.menuIdentifier = menuIdentifier;
    state.building.menuSize = {menuWidth, menuHeight};
    state.building.generation = state.published.generation + 1;
}

void WrathIOSGate5CSnapshotEntry(int entryIdentifier,
                                float x,
                                float y,
                                float width,
                                float height,
                                int flags,
                                int order) {
    (void)flags;
    BridgeState &state = State();
    std::scoped_lock lock(state.mutex);
    state.building.entries.push_back({
        entryIdentifier,
        {x, y, width, height},
        true,
        true,
        order,
    });
}

void WrathIOSGate5CSnapshotEnd(int hoverIdentifier) {
    {
        BridgeState &state = State();
        std::scoped_lock lock(state.mutex);
        state.published = state.building;
        state.hoverIdentifier = hoverIdentifier;
        state.pointerAcknowledged =
            state.activation.Stage() != wrathios::menu::ClickStage::idle &&
            hoverIdentifier == state.activation.EntryIdentifier();
        state.menuActive = true;
    }
    RefreshSurface();
}

int WrathIOSGate5CPointer(float *x, float *y) {
    BridgeState &state = State();
    std::scoped_lock lock(state.mutex);
    if (!state.menuActive || !state.activation.HasPointer()) {
        return 0;
    }
    wrathios::menu::Point pointer = state.activation.Pointer();
    if (x) *x = static_cast<float>(pointer.x);
    if (y) *y = static_cast<float>(pointer.y);
    return 1;
}

int WrathIOSGate5CNextButtonEvent(void) {
    BridgeState &state = State();
    std::scoped_lock lock(state.mutex);
    wrathios::menu::ButtonEvent event =
        state.activation.Advance(state.published.menuIdentifier, state.hoverIdentifier);
    if (event == wrathios::menu::ButtonEvent::down) return 1;
    if (event == wrathios::menu::ButtonEvent::up) return 2;
    return 0;
}

void WrathIOSGate5CSetMenuActive(int active) {
    {
        BridgeState &state = State();
        std::scoped_lock lock(state.mutex);
        state.menuActive = active != 0;
        if (!state.menuActive) {
            state.activation.Reset();
            state.building = {};
            state.published = {};
            state.hoverIdentifier = 0;
            state.pointerAcknowledged = false;
        }
    }
    RefreshSurface();
}
