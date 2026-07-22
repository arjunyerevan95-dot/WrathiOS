// SPDX-License-Identifier: GPL-2.0-only
#import "WrathImportViewController.h"

#import "WrathDataImporter.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString * const WrathChooseFolderTitle = @"Choose WRATH Folder";
static NSString * const WrathRemoveDataTitle = @"Remove Imported Data";

static NSString * const WrathStatusNoData = @"No imported data";
static NSString * const WrathStatusInvalidFolder = @"Invalid folder rejected";
static NSString * const WrathStatusSourcePassed = @"Source data validation passed";
static NSString * const WrathStatusCopying = @"Copy in progress";
static NSString * const WrathStatusPostCopyPassed = @"Post-copy validation passed";
static NSString * const WrathStatusDetectedAtLaunch = @"Imported data available after relaunch";
static NSString * const WrathStatusRemoved = @"Imported data removed";

@interface WrathImportViewController () <UIDocumentPickerDelegate>
@property(nonatomic) UILabel *stateLabel;
@property(nonatomic) UILabel *detailLabel;
@property(nonatomic) UIButton *chooseButton;
@property(nonatomic) UIButton *removeButton;
@property(nonatomic) UIActivityIndicatorView *spinner;
@end

@implementation WrathImportViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.004 green:0.006 blue:0.018 alpha:1.0];

    UILabel *eyebrow = [self labelWithFont:[UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightSemibold]
                                      color:[UIColor colorWithRed:0.28 green:0.94 blue:0.88 alpha:1.0]];
    eyebrow.text = @"GATE 4 · LICENSED DATA IMPORT";

    UILabel *title = [self labelWithFont:[UIFont systemFontOfSize:34.0 weight:UIFontWeightBold]
                                   color:UIColor.whiteColor];
    title.text = @"Import your WRATH installation";

    UILabel *intro = [self labelWithFont:[UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular]
                                   color:[UIColor colorWithWhite:0.78 alpha:1.0]];
    intro.text = @"Choose the folder that contains kp1, or choose kp1 itself. WrathiOS validates package indexes and copies your licensed files into this app only. Nothing is uploaded or bundled into the IPA.";

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.94];
    card.layer.cornerRadius = 18.0;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;

    self.stateLabel = [self labelWithFont:[UIFont systemFontOfSize:22.0 weight:UIFontWeightSemibold]
                                    color:UIColor.whiteColor];
    self.detailLabel = [self labelWithFont:[UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightRegular]
                                     color:[UIColor colorWithWhite:0.75 alpha:1.0]];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.color = UIColor.whiteColor;
    self.spinner.hidesWhenStopped = YES;

    UIStackView *cardStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.stateLabel, self.detailLabel, self.spinner]];
    cardStack.translatesAutoresizingMaskIntoConstraints = NO;
    cardStack.axis = UILayoutConstraintAxisVertical;
    cardStack.alignment = UIStackViewAlignmentLeading;
    cardStack.spacing = 10.0;
    [card addSubview:cardStack];

    self.chooseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.chooseButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIButtonConfiguration *chooseConfiguration = [UIButtonConfiguration filledButtonConfiguration];
    chooseConfiguration.title = WrathChooseFolderTitle;
    chooseConfiguration.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    chooseConfiguration.baseForegroundColor = UIColor.whiteColor;
    chooseConfiguration.baseBackgroundColor = [UIColor colorWithRed:0.15 green:0.48 blue:0.96 alpha:1.0];
    self.chooseButton.configuration = chooseConfiguration;
    self.chooseButton.configurationUpdateHandler = ^(UIButton *button) {
        UIButtonConfiguration *configuration = button.configuration;
        configuration.title = WrathChooseFolderTitle;
        configuration.baseForegroundColor = button.enabled
            ? UIColor.whiteColor
            : [UIColor colorWithWhite:0.82 alpha:1.0];
        button.configuration = configuration;
    };
    [self.chooseButton addTarget:self action:@selector(chooseFolder) forControlEvents:UIControlEventTouchUpInside];

    self.removeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.removeButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIButtonConfiguration *removeConfiguration = [UIButtonConfiguration borderedButtonConfiguration];
    removeConfiguration.title = WrathRemoveDataTitle;
    removeConfiguration.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    removeConfiguration.baseForegroundColor = [UIColor colorWithRed:1.0 green:0.42 blue:0.42 alpha:1.0];
    self.removeButton.configuration = removeConfiguration;
    self.removeButton.configurationUpdateHandler = ^(UIButton *button) {
        UIButtonConfiguration *configuration = button.configuration;
        configuration.title = WrathRemoveDataTitle;
        configuration.baseForegroundColor = button.enabled
            ? [UIColor colorWithRed:1.0 green:0.42 blue:0.42 alpha:1.0]
            : [UIColor colorWithWhite:0.72 alpha:1.0];
        button.configuration = configuration;
    };
    [self.removeButton addTarget:self action:@selector(confirmRemoval) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[self.chooseButton, self.removeButton]];
    buttons.translatesAutoresizingMaskIntoConstraints = NO;
    buttons.axis = UILayoutConstraintAxisHorizontal;
    buttons.spacing = 12.0;
    buttons.distribution = UIStackViewDistributionFillEqually;

    UILabel *boundary = [self labelWithFont:[UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular]
                                      color:[UIColor colorWithWhite:0.5 alpha:1.0]];
    boundary.text = @"Gate 4 validates and copies data only. The WRATH engine, filesystem, menu, audio, and gameplay remain disabled in this build.";

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[eyebrow, title, intro, card, buttons, boundary]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16.0;
    [self.view addSubview:stack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:28.0],
        [stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-28.0],
        [stack.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [stack.widthAnchor constraintLessThanOrEqualToConstant:920.0],
        [cardStack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20.0],
        [cardStack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20.0],
        [cardStack.topAnchor constraintEqualToAnchor:card.topAnchor constant:18.0],
        [cardStack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18.0],
        [self.chooseButton.heightAnchor constraintEqualToConstant:52.0],
        [self.removeButton.heightAnchor constraintEqualToConstant:52.0]
    ]];

    [self refreshInstalledState];
}

- (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)setBusy:(BOOL)busy message:(NSString *)message {
    self.chooseButton.enabled = !busy;
    self.removeButton.enabled = !busy;
    if (busy) {
        [self.spinner startAnimating];
        self.stateLabel.text = message;
    } else {
        [self.spinner stopAnimating];
    }
}

- (NSString *)successfulDetailsForReport:(WrathImportReport *)report origin:(NSString *)origin {
    double totalMiB = (double)report.totalBytes / (1024.0 * 1024.0);
    return [NSString stringWithFormat:
            @"%@ | Profile: wrath-1.1.2-qc-layout-v1\n%lu files | %lu packages | %.1f MiB\nRequired sentinels passed: progs.dat, csprogs.dat, menu.dat",
            origin,
            (unsigned long)report.fileCount,
            (unsigned long)report.packageCount,
            totalMiB];
}

- (void)refreshInstalledState {
    [self setBusy:YES message:@"Checking imported data…"];
    [[WrathDataImporter sharedImporter] inspectInstalledDataWithCompletion:^(WrathImportReport *report, NSError *error) {
        (void)error;
        [self setBusy:NO message:@""];
        if (report.compatible) {
            self.stateLabel.text = WrathStatusDetectedAtLaunch;
            self.stateLabel.textColor = [UIColor colorWithRed:0.3 green:0.95 blue:0.56 alpha:1.0];
            self.detailLabel.text = [self successfulDetailsForReport:report origin:@"Detected at launch"];
            self.removeButton.hidden = NO;
        } else if (report != nil) {
            self.stateLabel.text = @"Installed data failed validation";
            self.stateLabel.textColor = [UIColor colorWithRed:1.0 green:0.42 blue:0.42 alpha:1.0];
            self.detailLabel.text = report.details;
            self.removeButton.hidden = NO;
        } else {
            self.stateLabel.text = WrathStatusNoData;
            self.stateLabel.textColor = UIColor.whiteColor;
            self.detailLabel.text = @"Select a licensed WRATH installation. Required sentinels: progs.dat, csprogs.dat, and menu.dat.";
            self.removeButton.hidden = YES;
        }
    }];
}

- (void)chooseFolder {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeFolder] asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    picker.shouldShowFileExtensions = YES;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *selected = urls.firstObject;
    if (selected == nil) {
        return;
    }
    [self setBusy:YES message:@"Preparing import…"];
    self.detailLabel.text = @"The selected folder remains private on this device.";
    [[WrathDataImporter sharedImporter] importFromSelectedDirectory:selected
                                                           progress:^(NSString *message) {
        self.stateLabel.text = message;
        if ([message isEqualToString:WrathStatusSourcePassed]) {
            self.detailLabel.text = @"The selected kp1 structure passed validation. The original source path is not displayed or stored.";
        } else if ([message isEqualToString:WrathStatusCopying]) {
            self.detailLabel.text = @"Source data validation passed.\nCopying licensed kp1 files into the private app sandbox.";
        } else if ([message isEqualToString:WrathStatusPostCopyPassed]) {
            self.detailLabel.text = @"Source data validation passed.\nCopy complete; the sandboxed copy passed validation.";
        }
    } completion:^(WrathImportReport *report, NSError *error) {
        [self setBusy:NO message:@""];
        if (error != nil) {
            BOOL validationRejected = report != nil && !report.compatible;
            self.stateLabel.text = validationRejected ? WrathStatusInvalidFolder : @"Import failed";
            self.stateLabel.textColor = [UIColor colorWithRed:1.0 green:0.42 blue:0.42 alpha:1.0];
            self.detailLabel.text = validationRejected
                ? report.details
                : @"The import could not be completed. Private source and app-container paths are not displayed.";
            return;
        }
        self.stateLabel.text = WrathStatusPostCopyPassed;
        self.stateLabel.textColor = [UIColor colorWithRed:0.3 green:0.95 blue:0.56 alpha:1.0];
        self.detailLabel.text = [self successfulDetailsForReport:report origin:@"Imported during this session"];
        self.removeButton.hidden = NO;
    }];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
}

- (void)confirmRemoval {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Remove imported WRATH data?"
                                                                   message:@"This removes only the sandboxed copy. Your original installation is untouched."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [self setBusy:YES message:@"Removing imported data…"];
        [[WrathDataImporter sharedImporter] removeImportedDataWithCompletion:^(NSError *error) {
            [self setBusy:NO message:@""];
            if (error != nil) {
                self.stateLabel.text = @"Removal failed";
                self.detailLabel.text = @"The sandboxed import could not be removed. Private app-container paths are not displayed.";
                return;
            }
            self.stateLabel.text = WrathStatusRemoved;
            self.stateLabel.textColor = UIColor.whiteColor;
            self.detailLabel.text = @"No imported data remains. The sandboxed copy was removed. Relaunch to confirm this no-data state persists.";
            self.removeButton.hidden = YES;
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
