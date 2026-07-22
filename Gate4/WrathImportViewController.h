// SPDX-License-Identifier: GPL-2.0-only
#import <UIKit/UIKit.h>

@class WrathImportReport;

@interface WrathImportViewController : UIViewController
@property(nonatomic, copy, nullable) void (^runtimeLaunchHandler)(WrathImportReport *report);
- (void)showRuntimeStage:(NSString *)stage detail:(NSString *)detail transcript:(NSString *)transcript;
- (void)showRuntimeFailureAtStage:(NSString *)stage error:(NSString *)message transcript:(NSString *)transcript;
@end
