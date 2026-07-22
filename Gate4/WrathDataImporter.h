// SPDX-License-Identifier: GPL-2.0-only
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WrathImportReport : NSObject
@property(nonatomic, readonly) BOOL compatible;
@property(nonatomic, copy, readonly) NSString *summary;
@property(nonatomic, copy, readonly) NSString *details;
@property(nonatomic, readonly) NSUInteger fileCount;
@property(nonatomic, readonly) NSUInteger packageCount;
@property(nonatomic, readonly) unsigned long long totalBytes;
@end

typedef void (^WrathImportProgress)(NSString *message);
typedef void (^WrathImportCompletion)(WrathImportReport * _Nullable report, NSError * _Nullable error);

@interface WrathDataImporter : NSObject
+ (instancetype)sharedImporter;
- (void)inspectInstalledDataWithCompletion:(WrathImportCompletion)completion;
- (void)importFromSelectedDirectory:(NSURL *)selectedURL
                           progress:(nullable WrathImportProgress)progress
                         completion:(WrathImportCompletion)completion;
- (void)removeImportedDataWithCompletion:(void (^)(NSError * _Nullable error))completion;
+ (NSURL *)installedKP1URL;
+ (NSURL *)manifestURL;
@end

NS_ASSUME_NONNULL_END
