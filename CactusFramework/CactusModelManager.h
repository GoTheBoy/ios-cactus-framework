//
//  CactusModelManager.h
//  CactusFramework
//
//  Thread-safe model lifecycle management
//

#import <Foundation/Foundation.h>
#import "CactusModelConfiguration.h"
#import "CactusBackgroundProcessor.h"

NS_ASSUME_NONNULL_BEGIN

// Forward declarations
@class CactusModelManager;

// Model states
typedef NS_ENUM(NSInteger, CactusModelState) {
    CactusModelStateUnloaded = 0,
    CactusModelStateLoading = 1,
    CactusModelStateLoaded = 2,
    CactusModelStateError = 3
};

// MARK: - Model Manager Delegate

@protocol CactusModelManagerDelegate <NSObject>
@optional
- (void)modelManager:(CactusModelManager *)manager didChangeState:(CactusModelState)state;
- (void)modelManager:(CactusModelManager *)manager didLoadModelWithInfo:(NSDictionary *)info;
- (void)modelManager:(CactusModelManager *)manager didFailToLoadWithError:(NSError *)error;
- (void)modelManager:(CactusModelManager *)manager didUpdateLoadingProgress:(float)progress;
- (void)modelManagerDidUnloadModel:(CactusModelManager *)manager;
@end

// MARK: - Model Manager

@interface CactusModelManager : NSObject

@property (nonatomic, weak, nullable) id<CactusModelManagerDelegate> delegate;
@property (nonatomic, readonly) CactusModelState state;
@property (nonatomic, readonly, nullable) CactusModelConfiguration *currentConfiguration;
@property (nonatomic, readonly, nullable) NSDictionary *modelInfo;
@property (nonatomic, readonly, nullable) NSError *lastError;
@property (nonatomic, readonly) BOOL isLoaded;
@property (nonatomic, readonly) BOOL isLoading;

// Singleton access
+ (instancetype)sharedManager;

// Model lifecycle
- (void)loadModelWithConfiguration:(CactusModelConfiguration *)configuration
                   completionHandler:(nullable void(^)(BOOL success, NSError * _Nullable error))completionHandler;

- (void)loadModelWithConfiguration:(CactusModelConfiguration *)configuration
                   progressHandler:(nullable CactusTaskProgressHandler)progressHandler
                 completionHandler:(nullable void(^)(BOOL success, NSError * _Nullable error))completionHandler;

- (void)unloadModelWithCompletionHandler:(nullable void(^)(void))completionHandler;

- (void)reloadModelWithCompletionHandler:(nullable void(^)(BOOL success, NSError * _Nullable error))completionHandler;

// Model information
- (nullable NSDictionary *)getModelInfoForPath:(NSString *)modelPath;
- (nullable NSDictionary *)getCurrentModelInfo;

// Model validation
- (BOOL)validateConfiguration:(CactusModelConfiguration *)configuration error:(NSError **)error;

// Multimodal support
- (BOOL)initializeMultimodalWithConfiguration:(CactusMultimodalConfiguration *)configuration
                                        error:(NSError **)error;
- (void)releaseMultimodal;
- (BOOL)isMultimodalEnabled;
- (BOOL)isVisionSupported;
- (BOOL)isAudioSupported;

// LoRA support
- (BOOL)applyLoRAConfiguration:(CactusLoRAConfiguration *)configuration
                         error:(NSError **)error;
- (void)removeAllLoRAAdapters;
- (NSArray<CactusLoRAAdapter *> *)loadedLoRAAdapters;

// Context management
- (void)clearContext;
- (void)resetSampling;

// Internal context access (for other framework components)
- (nullable void *)internalContext;

@end

// MARK: - Model Manager Extensions

@interface CactusModelManager (Utilities)

// Quick model info without loading
+ (nullable NSDictionary *)quickModelInfoForPath:(NSString *)modelPath;

// Device capabilities
+ (NSDictionary *)deviceCapabilities;

// Memory management
+ (void)freeUnusedMemory;

@end

// MARK: - Model Manager Notifications

extern NSNotificationName const CactusModelManagerDidChangeStateNotification;
extern NSNotificationName const CactusModelManagerDidLoadModelNotification;
extern NSNotificationName const CactusModelManagerDidUnloadModelNotification;
extern NSNotificationName const CactusModelManagerDidFailToLoadNotification;

// Notification userInfo keys
extern NSString * const CactusModelManagerStateKey;
extern NSString * const CactusModelManagerModelInfoKey;
extern NSString * const CactusModelManagerErrorKey;
extern NSString * const CactusModelManagerProgressKey;

NS_ASSUME_NONNULL_END
