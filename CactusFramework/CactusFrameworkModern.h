//
//  CactusFrameworkModern.h
//  CactusFramework
//
//  Modern, easy-to-use facade for CactusFramework
//

#import <Foundation/Foundation.h>
#import "CactusModelConfiguration.h"
#import "CactusModelManager.h"
#import "CactusSessionManager.h"
#import "CactusBackgroundProcessor.h"
#import "CactusUtilities.h"
#import "CactusLLMMessage.h"

NS_ASSUME_NONNULL_BEGIN

// MARK: - Framework Delegate

@protocol CactusFrameworkDelegate <NSObject>
@optional
- (void)frameworkDidInitialize:(id)framework;
- (void)framework:(id)framework didLoadModel:(NSDictionary *)modelInfo;
- (void)framework:(id)framework didFailToLoadModel:(NSError *)error;
- (void)framework:(id)framework didReceiveLogMessage:(NSString *)message level:(CactusLogLevel)level;
@end

// MARK: - Main Framework Class

@interface CactusFrameworkModern : NSObject

@property (nonatomic, weak, nullable) id<CactusFrameworkDelegate> delegate;
@property (nonatomic, readonly) BOOL isModelLoaded;
@property (nonatomic, readonly) BOOL isInitialized;
@property (nonatomic, readonly, nullable) NSDictionary *currentModelInfo;

// MARK: - Singleton & Initialization

+ (instancetype)shared;

- (void)initializeWithDelegate:(nullable id<CactusFrameworkDelegate>)delegate;
- (void)shutdown;

// MARK: - Model Management

- (void)loadModelAtPath:(NSString *)modelPath
      completionHandler:(void(^)(BOOL success, NSError * _Nullable error))completionHandler;

- (void)loadModelWithConfiguration:(CactusModelConfiguration *)configuration
                 completionHandler:(void(^)(BOOL success, NSError * _Nullable error))completionHandler;

- (void)loadModelWithConfiguration:(CactusModelConfiguration *)configuration
                   progressHandler:(nullable CactusTaskProgressHandler)progressHandler
                 completionHandler:(void(^)(BOOL success, NSError * _Nullable error))completionHandler;

- (void)unloadModel;

// MARK: - Quick Chat Methods

- (void)chatWithMessage:(NSString *)message
      completionHandler:(void(^)(NSString * _Nullable response, NSError * _Nullable error))completionHandler;

- (void)chatWithMessage:(NSString *)message
        progressHandler:(nullable void(^)(NSString *partialResponse))progressHandler
      completionHandler:(void(^)(NSString * _Nullable response, NSError * _Nullable error))completionHandler;

- (void)chatWithMessages:(NSArray<CactusLLMMessage *> *)messages
       completionHandler:(void(^)(NSString * _Nullable response, NSError * _Nullable error))completionHandler;

- (void)chatWithMessages:(NSArray<CactusLLMMessage *> *)messages
         progressHandler:(nullable void(^)(NSString *partialResponse))progressHandler
       completionHandler:(void(^)(NSString * _Nullable response, NSError * _Nullable error))completionHandler;

// MARK: - Advanced Session Management

- (CactusSession *)createChatSession;
- (CactusSession *)createChatSessionWithSystemPrompt:(NSString *)systemPrompt;
- (CactusSession *)createChatSessionWithSystemPrompt:(NSString *)systemPrompt
                                   withConfiguration:(CactusGenerationConfiguration *)config;

- (nullable CactusSession *)getSession:(NSUUID *)sessionId;
- (void)destroySession:(NSUUID *)sessionId;
- (NSArray<CactusSession *> *)allSessions;

// MARK: - Completion Methods

- (void)completeText:(NSString *)prompt
   completionHandler:(void(^)(NSString * _Nullable completion, NSError * _Nullable error))completionHandler;

- (void)completeText:(NSString *)prompt
      configuration:(nullable CactusGenerationConfiguration *)config
   completionHandler:(void(^)(NSString * _Nullable completion, NSError * _Nullable error))completionHandler;

// MARK: - Multimodal Methods

- (void)processMultimodalInput:(NSString *)prompt
                    mediaPaths:(NSArray<NSString *> *)mediaPaths
             completionHandler:(void(^)(NSString * _Nullable response, NSError * _Nullable error))completionHandler;

- (BOOL)initializeMultimodalWithProjectionPath:(NSString *)projectionPath error:(NSError **)error;
- (void)releaseMultimodal;

// MARK: - Embedding Methods

- (void)generateEmbeddingForText:(NSString *)text
               completionHandler:(void(^)(NSArray<NSNumber *> * _Nullable embedding, NSError * _Nullable error))completionHandler;

// MARK: - Tokenization Methods

- (NSArray<NSNumber *> *)tokenizeText:(NSString *)text;
- (NSString *)detokenizeTokens:(NSArray<NSNumber *> *)tokens;
- (NSInteger)countTokensInText:(NSString *)text;

// MARK: - LoRA Methods

- (BOOL)applyLoRAAdapter:(NSString *)adapterPath error:(NSError **)error;
- (BOOL)applyLoRAAdapter:(NSString *)adapterPath scale:(float)scale error:(NSError **)error;
- (BOOL)applyLoRAAdapters:(NSArray<CactusLoRAAdapter *> *)adapters error:(NSError **)error;
- (void)removeAllLoRAAdapters;
- (NSArray<CactusLoRAAdapter *> *)loadedLoRAAdapters;

// MARK: - Benchmarking

- (void)runQuickBenchmarkWithCompletionHandler:(void(^)(CactusBenchmarkResult * _Nullable result, NSError * _Nullable error))completionHandler;

- (void)runBenchmarkWithConfiguration:(NSDictionary *)config
                    completionHandler:(void(^)(CactusBenchmarkResult * _Nullable result, NSError * _Nullable error))completionHandler;

// MARK: - Utilities

- (NSDictionary *)modelInfo;
- (NSDictionary *)systemInfo;
- (NSDictionary *)performanceStats;
- (NSDictionary *)frameworkStatistics;

// MARK: - Configuration

- (void)setLogLevel:(CactusLogLevel)level;
- (void)setMaxConcurrentSessions:(NSInteger)maxSessions;
- (void)setMaxConcurrentTasks:(NSInteger)maxTasks;

@end

// MARK: - Convenience Extensions

@interface CactusFrameworkModern (QuickSetup)

// Quick setup methods for common use cases
+ (void)setupForChatWithModelPath:(NSString *)modelPath
                completionHandler:(void(^)(CactusFrameworkModern * _Nullable framework, NSError * _Nullable error))completionHandler;

+ (void)setupForCompletionWithModelPath:(NSString *)modelPath
                      completionHandler:(void(^)(CactusFrameworkModern * _Nullable framework, NSError * _Nullable error))completionHandler;

+ (void)setupForMultimodalWithModelPath:(NSString *)modelPath
                         projectionPath:(NSString *)projectionPath
                      completionHandler:(void(^)(CactusFrameworkModern * _Nullable framework, NSError * _Nullable error))completionHandler;

@end

@interface CactusFrameworkModern (PresetConfigurations)

// Preset configurations for different use cases
+ (CactusModelConfiguration *)fastChatConfiguration:(NSString *)modelPath;
+ (CactusModelConfiguration *)highQualityChatConfiguration:(NSString *)modelPath;
+ (CactusModelConfiguration *)embeddingConfiguration:(NSString *)modelPath;
+ (CactusModelConfiguration *)multimodalConfiguration:(NSString *)modelPath projectionPath:(NSString *)projectionPath;

@end

@interface CactusFrameworkModern (AsyncAwait)

// Modern async/await style methods (iOS 13+)
#if __has_feature(objc_generics) && defined(__IPHONE_13_0)

- (void)loadModelAtPathAsync:(NSString *)modelPath API_AVAILABLE(ios(13.0));
- (void)chatWithMessageAsync:(NSString *)message API_AVAILABLE(ios(13.0));
- (void)completeTextAsync:(NSString *)prompt API_AVAILABLE(ios(13.0));

#endif

@end

// MARK: - Builder Pattern

@interface CactusFrameworkBuilder : NSObject

+ (instancetype)builder;

- (instancetype)withModelPath:(NSString *)modelPath;
- (instancetype)withConfiguration:(CactusModelConfiguration *)configuration;
- (instancetype)withDelegate:(id<CactusFrameworkDelegate>)delegate;
- (instancetype)withLogLevel:(CactusLogLevel)logLevel;
- (instancetype)withMaxConcurrentSessions:(NSInteger)maxSessions;

- (void)buildAndInitializeWithCompletionHandler:(void(^)(CactusFrameworkModern * _Nullable framework, NSError * _Nullable error))completionHandler;

@end

// MARK: - Error Extensions

@interface NSError (CactusFramework)

+ (instancetype)cactusErrorWithCode:(NSInteger)code description:(NSString *)description;
+ (instancetype)cactusErrorWithCode:(NSInteger)code description:(NSString *)description underlyingError:(nullable NSError *)underlyingError;

@end

NS_ASSUME_NONNULL_END
