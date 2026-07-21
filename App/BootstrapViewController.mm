// SPDX-License-Identifier: GPL-2.0-only

#import "BootstrapViewController.h"
#import "WrathEngineBridge.h"

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
    status.text = WrathEngineStatusText();
    status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    status.textAlignment = NSTextAlignmentCenter;
    status.numberOfLines = 0;

    UILabel *boundary = [[UILabel alloc] init];
    boundary.translatesAutoresizingMaskIntoConstraints = NO;
    boundary.text = @"Commercial WRATH data is not bundled. A later milestone will import files from the user's own licensed installation.";
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

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

@end
