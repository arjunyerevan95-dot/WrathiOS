// SPDX-License-Identifier: GPL-2.0-only

#import "BootstrapViewController.h"
#import "WrathEngineBridge.h"
#import "WrathGraphicsDiagnostic.h"

@interface BootstrapViewController ()
@property(nonatomic, assign) BOOL gate3LaunchRequested;
@end

@implementation BootstrapViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"WrathiOS";
    title.font = [UIFont systemFontOfSize:34.0 weight:UIFontWeightBold];
    title.textAlignment = NSTextAlignmentCenter;

    UILabel *status = [[UILabel alloc] init];
    status.translatesAutoresizingMaskIntoConstraints = NO;
#if WRATH_GATE3_DIAGNOSTIC
    status.text = @"Preparing the Gate 3 SDL2/OpenGL ES diagnostic…";
#else
    status.text = WrathEngineStatusText();
#endif
    status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    status.textAlignment = NSTextAlignmentCenter;
    status.numberOfLines = 0;

    UILabel *boundary = [[UILabel alloc] init];
    boundary.translatesAutoresizingMaskIntoConstraints = NO;
#if WRATH_GATE3_DIAGNOSTIC
    boundary.text = @"No commercial WRATH data is loaded. Engine startup remains disabled.";
#else
    boundary.text = @"Commercial WRATH data is not bundled. A later milestone will import files from the user's own licensed installation.";
#endif
    boundary.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    boundary.textAlignment = NSTextAlignmentCenter;
    boundary.numberOfLines = 0;
    boundary.textColor = UIColor.secondaryLabelColor;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, status, boundary]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 18.0;

    [self.view addSubview:stack];
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:guide.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:guide.centerYAnchor],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:guide.leadingAnchor constant:32.0],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:guide.trailingAnchor constant:-32.0],
        [stack.widthAnchor constraintLessThanOrEqualToConstant:700.0]
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
#if WRATH_GATE3_DIAGNOSTIC
    if (self.gate3LaunchRequested) {
        return;
    }
    self.gate3LaunchRequested = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        (void)WrathGraphicsDiagnosticStart();
    });
#endif
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

@end
