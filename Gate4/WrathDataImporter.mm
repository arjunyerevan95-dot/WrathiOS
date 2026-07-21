// SPDX-License-Identifier: GPL-2.0-only
#import "WrathDataImporter.h"

#import <Foundation/Foundation.h>

#include "WrathDataContract.hpp"

static NSString * const WrathImportErrorDomain = @"com.arjukstudios.wrathios.import";

@interface WrathImportReport ()
@property(nonatomic, readwrite) BOOL compatible;
@property(nonatomic, copy, readwrite) NSString *summary;
@property(nonatomic, copy, readwrite) NSString *details;
@property(nonatomic, readwrite) NSUInteger fileCount;
@property(nonatomic, readwrite) NSUInteger packageCount;
@property(nonatomic, readwrite) unsigned long long totalBytes;
@end

@implementation WrathImportReport
@end

@interface WrathDataImporter ()
@property(nonatomic) dispatch_queue_t workerQueue;
@end

@implementation WrathDataImporter

+ (instancetype)sharedImporter {
    static WrathDataImporter *importer;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        importer = [[WrathDataImporter alloc] initPrivate];
    });
    return importer;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _workerQueue = dispatch_queue_create("com.arjukstudios.wrathios.gate4-import", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (instancetype)init {
    return [WrathDataImporter sharedImporter];
}

+ (NSURL *)applicationSupportRootURL {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *support = [manager URLsForDirectory:NSApplicationSupportDirectory
                                      inDomains:NSUserDomainMask].firstObject;
    return [support URLByAppendingPathComponent:@"WrathiOS" isDirectory:YES];
}

+ (NSURL *)gameDataRootURL {
    return [[self applicationSupportRootURL] URLByAppendingPathComponent:@"GameData" isDirectory:YES];
}

+ (NSURL *)installedKP1URL {
    return [[self gameDataRootURL] URLByAppendingPathComponent:@"kp1" isDirectory:YES];
}

+ (NSURL *)manifestURL {
    return [[self gameDataRootURL] URLByAppendingPathComponent:@"import-manifest.json" isDirectory:NO];
}

static std::filesystem::path WrathPathFromURL(NSURL *url) {
    const char *representation = url.fileSystemRepresentation;
    return representation != nullptr ? std::filesystem::path(representation) : std::filesystem::path();
}

static NSString *WrathString(const std::string &value) {
    NSString *string = [[NSString alloc] initWithBytes:value.data()
                                                length:value.size()
                                              encoding:NSUTF8StringEncoding];
    return string ?: @"";
}

static WrathImportReport *WrathReport(const wrath::importer::ValidationResult &validation) {
    WrathImportReport *report = [[WrathImportReport alloc] init];
    report.compatible = validation.compatible;
    report.summary = WrathString(wrath::importer::HumanReadableSummary(validation));
    report.fileCount = validation.regularFileCount;
    report.packageCount = validation.packageCount;
    report.totalBytes = validation.totalBytes;

    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (const auto &error : validation.errors) {
        [lines addObject:[@"Error: " stringByAppendingString:WrathString(error)]];
    }
    for (const auto &warning : validation.warnings) {
        [lines addObject:[@"Warning: " stringByAppendingString:WrathString(warning)]];
    }
    if (validation.compatible) {
        [lines addObject:@"Validated progs.dat, csprogs.dat, and menu.dat in loose files or package indexes."];
    }
    report.details = lines.count > 0 ? [lines componentsJoinedByString:@"\n"] : @"No validation details.";
    return report;
}

static NSError *WrathNSError(NSInteger code, NSString *description, NSString * _Nullable reason) {
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:description
                                                                    forKey:NSLocalizedDescriptionKey];
    if (reason.length > 0) {
        info[NSLocalizedFailureReasonErrorKey] = reason;
    }
    return [NSError errorWithDomain:WrathImportErrorDomain code:code userInfo:info];
}

static void WrathComplete(WrathImportCompletion completion,
                          WrathImportReport * _Nullable report,
                          NSError * _Nullable error) {
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(report, error);
    });
}

static void WrathProgress(WrathImportProgress progress, NSString *message) {
    if (progress == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        progress(message);
    });
}

- (void)inspectInstalledDataWithCompletion:(WrathImportCompletion)completion {
    dispatch_async(self.workerQueue, ^{
        NSURL *installed = WrathDataImporter.installedKP1URL;
        if (![NSFileManager.defaultManager fileExistsAtPath:installed.path]) {
            WrathComplete(completion, nil, WrathNSError(10, @"No licensed WRATH data is installed.", nil));
            return;
        }
        const auto validation = wrath::importer::ValidateInstallation(WrathPathFromURL(installed));
        WrathImportReport *report = WrathReport(validation);
        if (!validation.compatible) {
            WrathComplete(completion, report,
                          WrathNSError(11, @"Installed WRATH data failed validation.", report.details));
            return;
        }
        WrathComplete(completion, report, nil);
    });
}

- (void)importFromSelectedDirectory:(NSURL *)selectedURL
                           progress:(WrathImportProgress)progress
                         completion:(WrathImportCompletion)completion {
    dispatch_async(self.workerQueue, ^{
        BOOL securityScoped = [selectedURL startAccessingSecurityScopedResource];
        @try {
            WrathProgress(progress, @"Inspecting the selected WRATH folder…");
            const auto sourceValidation = wrath::importer::ValidateInstallation(WrathPathFromURL(selectedURL));
            WrathImportReport *sourceReport = WrathReport(sourceValidation);
            if (!sourceValidation.compatible) {
                WrathComplete(completion, sourceReport,
                              WrathNSError(20, @"The selected folder is not a compatible WRATH installation.",
                                           sourceReport.details));
                return;
            }

            NSURL *sourceKP1 = [NSURL fileURLWithFileSystemRepresentation:sourceValidation.kp1Root.c_str()
                                                              isDirectory:YES
                                                            relativeToURL:nil];
            NSFileManager *manager = NSFileManager.defaultManager;
            NSURL *gameDataRoot = WrathDataImporter.gameDataRootURL;
            NSError *fileError = nil;
            if (![manager createDirectoryAtURL:gameDataRoot
                   withIntermediateDirectories:YES
                                    attributes:nil
                                         error:&fileError]) {
                WrathComplete(completion, nil,
                              WrathNSError(21, @"Could not create the app's game-data directory.",
                                           fileError.localizedDescription));
                return;
            }

            NSString *identifier = NSUUID.UUID.UUIDString;
            NSURL *stagingRoot = [gameDataRoot URLByAppendingPathComponent:
                                  [@".incoming-" stringByAppendingString:identifier] isDirectory:YES];
            NSURL *stagingKP1 = [stagingRoot URLByAppendingPathComponent:@"kp1" isDirectory:YES];
            NSURL *backup = [gameDataRoot URLByAppendingPathComponent:
                             [@".backup-" stringByAppendingString:identifier] isDirectory:YES];
            [manager removeItemAtURL:stagingRoot error:nil];
            [manager removeItemAtURL:backup error:nil];
            if (![manager createDirectoryAtURL:stagingRoot
                   withIntermediateDirectories:YES
                                    attributes:nil
                                         error:&fileError]) {
                WrathComplete(completion, nil,
                              WrathNSError(22, @"Could not create the import staging directory.",
                                           fileError.localizedDescription));
                return;
            }

            WrathProgress(progress, @"Copying licensed files into the app sandbox…");
            __block NSError *copyError = nil;
            NSError *coordinationError = nil;
            NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
            [coordinator coordinateReadingItemAtURL:sourceKP1
                                            options:NSFileCoordinatorReadingWithoutChanges
                                              error:&coordinationError
                                         byAccessor:^(NSURL *newURL) {
                [manager copyItemAtURL:newURL toURL:stagingKP1 error:&copyError];
            }];
            NSError *effectiveCopyError = copyError ?: coordinationError;
            if (effectiveCopyError != nil || ![manager fileExistsAtPath:stagingKP1.path]) {
                [manager removeItemAtURL:stagingRoot error:nil];
                WrathComplete(completion, nil,
                              WrathNSError(23, @"WRATH files could not be copied.",
                                           effectiveCopyError.localizedDescription));
                return;
            }

            WrathProgress(progress, @"Validating the sandboxed copy…");
            const auto stagedValidation = wrath::importer::ValidateInstallation(WrathPathFromURL(stagingKP1));
            WrathImportReport *stagedReport = WrathReport(stagedValidation);
            if (!stagedValidation.compatible) {
                [manager removeItemAtURL:stagingRoot error:nil];
                WrathComplete(completion, stagedReport,
                              WrathNSError(24, @"The copied WRATH data failed post-copy validation.",
                                           stagedReport.details));
                return;
            }

            NSURL *destination = WrathDataImporter.installedKP1URL;
            BOOL hadExisting = [manager fileExistsAtPath:destination.path];
            if (hadExisting && ![manager moveItemAtURL:destination toURL:backup error:&fileError]) {
                [manager removeItemAtURL:stagingRoot error:nil];
                WrathComplete(completion, nil,
                              WrathNSError(25, @"Existing WRATH data could not be prepared for replacement.",
                                           fileError.localizedDescription));
                return;
            }
            if (![manager moveItemAtURL:stagingKP1 toURL:destination error:&fileError]) {
                if (hadExisting) {
                    [manager moveItemAtURL:backup toURL:destination error:nil];
                }
                [manager removeItemAtURL:stagingRoot error:nil];
                WrathComplete(completion, nil,
                              WrathNSError(26, @"Validated WRATH data could not be installed.",
                                           fileError.localizedDescription));
                return;
            }

            NSMutableArray<NSString *> *packages = [NSMutableArray array];
            for (const auto &package : stagedValidation.packageNames) {
                [packages addObject:WrathString(package)];
            }
            NSString *importedAt = [[NSISO8601DateFormatter new] stringFromDate:NSDate.date] ?: @"";
            NSDictionary *manifest = @{
                @"schemaVersion": @1,
                @"compatibilityProfile": @(wrath::importer::kCompatibilityProfile),
                @"engineRevision": @(wrath::importer::kEngineRevision),
                @"qcRevision": @(wrath::importer::kQCRevision),
                @"importedAt": importedAt,
                @"fileCount": @(stagedValidation.regularFileCount),
                @"packageCount": @(stagedValidation.packageCount),
                @"totalBytes": @(stagedValidation.totalBytes),
                @"packages": packages,
                @"sentinels": @[@"progs.dat", @"csprogs.dat", @"menu.dat"]
            };
            NSData *manifestData = [NSJSONSerialization dataWithJSONObject:manifest
                                                                    options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                                      error:&fileError];
            if (manifestData == nil || ![manifestData writeToURL:WrathDataImporter.manifestURL
                                                         options:NSDataWritingAtomic
                                                           error:&fileError]) {
                [manager removeItemAtURL:destination error:nil];
                if (hadExisting) {
                    [manager moveItemAtURL:backup toURL:destination error:nil];
                }
                [manager removeItemAtURL:stagingRoot error:nil];
                WrathComplete(completion, nil,
                              WrathNSError(27, @"The import manifest could not be written.",
                                           fileError.localizedDescription));
                return;
            }

            [manager removeItemAtURL:stagingRoot error:nil];
            [manager removeItemAtURL:backup error:nil];
            WrathProgress(progress, @"Licensed WRATH data is ready for the next milestone.");
            WrathComplete(completion, stagedReport, nil);
        } @finally {
            if (securityScoped) {
                [selectedURL stopAccessingSecurityScopedResource];
            }
        }
    });
}

- (void)removeImportedDataWithCompletion:(void (^)(NSError * _Nullable error))completion {
    dispatch_async(self.workerQueue, ^{
        NSError *error = nil;
        NSURL *root = WrathDataImporter.gameDataRootURL;
        if ([NSFileManager.defaultManager fileExistsAtPath:root.path] &&
            ![NSFileManager.defaultManager removeItemAtURL:root error:&error]) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

@end
