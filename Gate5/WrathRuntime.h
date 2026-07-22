// SPDX-License-Identifier: GPL-2.0-only
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const WrathRuntimeStageDidChangeNotification;
extern NSString * const WrathRuntimeStageNameKey;
extern NSString * const WrathRuntimeStageDetailKey;

typedef void (^WrathRuntimeCompletion)(NSString * _Nullable sanitizedError);

@interface WrathRuntime : NSObject
+ (instancetype)sharedRuntime;
@property(nonatomic, readonly, getter=isStartingOrActive) BOOL startingOrActive;
@property(nonatomic, copy, readonly) NSString *lastStage;
@property(nonatomic, copy, readonly) NSString *transcriptText;
+ (NSURL *)transcriptURL;
- (void)startWithCompletion:(WrathRuntimeCompletion)completion;
- (void)recordLifecycleEvent:(NSString *)event;
@end

NS_ASSUME_NONNULL_END
