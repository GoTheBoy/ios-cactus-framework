//
//  CactusFrameworkModern.mm
//  CactusFramework
//

#import "CactusFrameworkModern.h"
#import "CactusLLMError.h"

@interface CactusFrameworkModern () <CactusModelManagerDelegate, CactusSessionManagerDelegate>
@property (nonatomic, readwrite) BOOL isInitialized;
@property (nonatomic, strong) CactusSession *defaultChatSession;
@end

@implementation CactusFrameworkModern

#pragma mark - Singleton & Initialization

+ (instancetype)shared {
    static CactusFrameworkModern *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _isInitialized = NO;
    }
    return self;
}

- (void)initializeWithDelegate:(id<CactusFrameworkDelegate>)delegate {
    if (self.isInitialized) return;
    
    self.delegate = delegate;
    
    // Set up delegates
    [CactusModelManager sharedManager].delegate = self;
    [CactusSessionManager sharedManager].delegate = self;
    
    // Configure logging
    [CactusLogger setLogHandler:^(CactusLogLevel level, NSString *message) {
        if ([self.delegate respondsToSelector:@selector(framework:didReceiveLogMessage:level:)]) {
            [self.delegate framework:self didReceiveLogMessage:message level:level];
        }
    }];
    
    self.isInitialized = YES;
    
    if ([self.delegate respondsToSelector:@selector(frameworkDidInitialize:)]) {
        [self.delegate frameworkDidInitialize:self];
    }
}

- (void)shutdown {
    if (!self.isInitialized) return;
    
    // Stop all sessions
    [[CactusSessionManager sharedManager] destroyAllSessions];
    
    // Unload model
    [[CactusModelManager sharedManager] unloadModelWithCompletionHandler:nil];
    
    // Stop background processor
    [[CactusBackgroundProcessor sharedProcessor] stop];
    
    self.isInitialized = NO;
    self.defaultChatSession = nil;
}

#pragma mark - Properties

- (BOOL)isModelLoaded {
    return [[CactusModelManager sharedManager] isLoaded];
}

- (NSDictionary *)currentModelInfo {
    return [[CactusModelManager sharedManager] getCurrentModelInfo];
}

#pragma mark - Model Management

- (void)loadModelAtPath:(NSString *)modelPath
      completionHandler:(void(^)(BOOL success, NSError * _Nullable error))completionHandler {
    CactusModelConfiguration *config = [CactusModelConfiguration configurationWithModelPath:modelPath];
    [self loadModelWithConfiguration:config completionHandler:completionHandler];
}

- (void)loadModelWithConfiguration:(CactusModelConfiguration *)configuration
                 completionHandler:(void(^)(BOOL success, NSError * _Nullable error))completionHandler {
    [self loadModelWithConfiguration:configuration
                     progressHandler:nil
                   completionHandler:completionHandler];
}

- (void)loadModelWithConfiguration:(CactusModelConfiguration *)configuration
                   progressHandler:(CactusTaskProgressHandler)progressHandler
                 completionHandler:(void(^)(BOOL success, NSError * _Nullable error))completionHandler {
    if (!self.isInitialized) {
        [self initializeWithDelegate:nil];
    }
    
    [[CactusModelManager sharedManager] loadModelWithConfiguration:configuration
                                                   progressHandler:progressHandler
                                                 completionHandler:completionHandler];
}

- (void)unloadModel {
    [[CactusModelManager sharedManager] unloadModelWithCompletionHandler:nil];
    self.defaultChatSession = nil;
}

#pragma mark - Quick Chat Methods

- (void)chatWithMessage:(NSString *)message
      completionHandler:(void(^)(NSString * _Nullable response, NSError * _Nullable error))completionHandler {
    [self chatWithMessage:message
          progressHandler:nil
        completionHandler:completionHandler];
}

- (void)chatWithMessage:(NSString *)message
        progressHandler:(void(^)(NSString *partialResponse))progressHandler
      completionHandler:(void(^)(NSString * _Nullable response, NSError * _Nullable error))completionHandler {
    
    CactusLLMMessage *userMessage = [CactusLLMMessage messageWithRole:CactusLLMRoleUser content:message];
    [self chatWithMessages:@[userMessage]
           progressHandler:progressHandler
         completionHandler:completionHandler];
}

- (void)chatWithMessages:(NSArray<CactusLLMMessage *> *)messages
       completionHandler:(void(^)(NSString * _Nullable response, NSError * _Nullable error))completionHandler {
    [self chatWithMessages:messages
           progressHandler:nil
         completionHandler:completionHandler];
}

- (void)chatWithMessages:(NSArray<CactusLLMMessage *> *)messages
         progressHandler:(void(^)(NSString *partialResponse))progressHandler
       completionHandler:(void(^)(NSString * _Nullable response, NSError * _Nullable error))completionHandler {
    
    if (!self.isModelLoaded) {
        NSError *error = [NSError cactusErrorWithCode:CactusLLMErrorModelNotLoaded
                                          description:@"Model not loaded"];
        if (completionHandler) {
            completionHandler(nil, error);
        }
        return;
    }
    
    // Create or get default chat session
    if (!self.defaultChatSession) {
        self.defaultChatSession = [[CactusSessionManager sharedManager] createChatSessionWithSystemPrompt:nil
                                                                                         generationConfig:[CactusGenerationConfiguration defaultConfiguration]];
        self.defaultChatSession.delegate = nil;
    }
    
    // Add messages to session
    [self.defaultChatSession addMessages:messages];
    
    // Generate response
    [self.defaultChatSession generateResponseWithProgressHandler:^(float progress) {
        // Progress updates are handled by token handler
    } tokenHandler:^(NSString *token) {
        if (progressHandler) {
            progressHandler(token);
        }
    } completionHandler:^(CactusGenerationResult * _Nullable result, NSError * _Nullable error) {
        if (completionHandler) {
            completionHandler(result ? result.text : nil, error);
        }
    }];
}

#pragma mark - Advanced Session Management

- (CactusSession *)createChatSession {
    return [[CactusSessionManager sharedManager] createChatSessionWithSystemPrompt:nil
                                                                   generationConfig:[CactusGenerationConfiguration defaultConfiguration]];
}

- (CactusSession *)createChatSessionWithSystemPrompt:(NSString *)systemPrompt {
    return [[CactusSessionManager sharedManager] createChatSessionWithSystemPrompt:systemPrompt
                                                                   generationConfig:[CactusGenerationConfiguration defaultConfiguration]];
}

- (CactusSession *)createChatSessionWithSystemPrompt:(NSString *)systemPrompt
                                   withConfiguration:(CactusGenerationConfiguration *)config {
    return [[CactusSessionManager sharedManager] createChatSessionWithSystemPrompt:systemPrompt
                                                                   generationConfig:config];
}

- (CactusSession *)getSession:(NSUUID *)sessionId {
    return [[CactusSessionManager sharedManager] sessionWithId:sessionId];
}

- (void)destroySession:(NSUUID *)sessionId {
    [[CactusSessionManager sharedManager] destroySession:sessionId];
    
    // Clear default session if it was destroyed
    if ([self.defaultChatSession.sessionId isEqual:sessionId]) {
        self.defaultChatSession = nil;
    }
}

- (NSArray<CactusSession *> *)allSessions {
    return [[CactusSessionManager sharedManager] activeSessions];
}

#pragma mark - Completion Methods

- (void)completeText:(NSString *)prompt
   completionHandler:(void(^)(NSString * _Nullable completion, NSError * _Nullable error))completionHandler {
    [self completeText:prompt
         configuration:nil
     completionHandler:completionHandler];
}

- (void)completeText:(NSString *)prompt
       configuration:(CactusGenerationConfiguration *)config
   completionHandler:(void(^)(NSString * _Nullable completion, NSError * _Nullable error))completionHandler {
    
    if (!self.isModelLoaded) {
        NSError *error = [NSError cactusErrorWithCode:CactusLLMErrorModelNotLoaded
                                          description:@"Model not loaded"];
        if (completionHandler) {
            completionHandler(nil, error);
        }
        return;
    }
    
    CactusSession *session = [[CactusSessionManager sharedManager] createCompletionSessionWithGenerationConfig:config ?: [CactusGenerationConfiguration defaultConfiguration]];
    
    [session generateCompletionForPrompt:prompt completionHandler:^(CactusGenerationResult * _Nullable result, NSError * _Nullable error) {
        [[CactusSessionManager sharedManager] destroySession:session.sessionId];
        
        if (completionHandler) {
            completionHandler(result ? result.text : nil, error);
        }
    }];
}

#pragma mark - Multimodal Methods

- (void)processMultimodalInput:(NSString *)prompt
                    mediaPaths:(NSArray<NSString *> *)mediaPaths
             completionHandler:(void(^)(NSString * _Nullable response, NSError * _Nullable error))completionHandler {
    
    if (!self.isModelLoaded) {
        NSError *error = [NSError cactusErrorWithCode:CactusLLMErrorModelNotLoaded
                                          description:@"Model not loaded"];
        if (completionHandler) {
            completionHandler(nil, error);
        }
        return;
    }
    
    if (![[CactusModelManager sharedManager] isMultimodalEnabled]) {
        NSError *error = [NSError cactusErrorWithCode:CactusLLMErrorMultimodalNotEnabled
                                          description:@"Multimodal not enabled"];
        if (completionHandler) {
            completionHandler(nil, error);
        }
        return;
    }
    
    CactusSession *session = [CactusSession multimodalSessionWithId:nil];
    session.generationConfig = [CactusGenerationConfiguration defaultConfiguration];
    
    [session generateMultimodalResponseWithPrompt:prompt
                                       mediaPaths:mediaPaths
                                completionHandler:^(CactusGenerationResult * _Nullable result, NSError * _Nullable error) {
        if (completionHandler) {
            completionHandler(result ? result.text : nil, error);
        }
    }];
}

- (BOOL)initializeMultimodalWithProjectionPath:(NSString *)projectionPath error:(NSError **)error {
    CactusMultimodalConfiguration *config = [CactusMultimodalConfiguration defaultConfiguration];
    config.mmprojPath = projectionPath;
    
    return [[CactusModelManager sharedManager] initializeMultimodalWithConfiguration:config error:error];
}

- (void)releaseMultimodal {
    [[CactusModelManager sharedManager] releaseMultimodal];
}

#pragma mark - Embedding Methods

- (void)generateEmbeddingForText:(NSString *)text
               completionHandler:(void(^)(NSArray<NSNumber *> * _Nullable embedding, NSError * _Nullable error))completionHandler {
    
    if (!self.isModelLoaded) {
        NSError *error = [NSError cactusErrorWithCode:CactusLLMErrorModelNotLoaded
                                          description:@"Model not loaded"];
        if (completionHandler) {
            completionHandler(nil, error);
        }
        return;
    }
    
    CactusSession *session = [CactusSession embeddingSessionWithId:nil];
    
    [session generateEmbeddingForText:text completionHandler:^(NSArray<NSNumber *> * _Nullable embedding, NSError * _Nullable error) {
        if (completionHandler) {
            completionHandler(embedding, error);
        }
    }];
}

#pragma mark - Tokenization Methods

- (NSArray<NSNumber *> *)tokenizeText:(NSString *)text {
    return [CactusTokenizer tokenizeText:text error:nil];
}

- (NSString *)detokenizeTokens:(NSArray<NSNumber *> *)tokens {
    return [CactusTokenizer detokenizeTokens:tokens error:nil];
}

- (NSInteger)countTokensInText:(NSString *)text {
    return [CactusTokenizer countTokensInText:text];
}

#pragma mark - LoRA Methods

- (BOOL)applyLoRAAdapter:(NSString *)adapterPath error:(NSError **)error {
    return [self applyLoRAAdapter:adapterPath scale:1.0f error:error];
}

- (BOOL)applyLoRAAdapter:(NSString *)adapterPath scale:(float)scale error:(NSError **)error {
    CactusLoRAAdapter *adapter = [CactusLoRAAdapter adapterWithPath:adapterPath scale:scale];
    return [self applyLoRAAdapters:@[adapter] error:error];
}

- (BOOL)applyLoRAAdapters:(NSArray<CactusLoRAAdapter *> *)adapters error:(NSError **)error {
    CactusLoRAConfiguration *config = [CactusLoRAConfiguration configurationWithAdapters:adapters];
    return [[CactusModelManager sharedManager] applyLoRAConfiguration:config error:error];
}

- (void)removeAllLoRAAdapters {
    [[CactusModelManager sharedManager] removeAllLoRAAdapters];
}

- (NSArray<CactusLoRAAdapter *> *)loadedLoRAAdapters {
    return [[CactusModelManager sharedManager] loadedLoRAAdapters];
}

#pragma mark - Benchmarking

- (void)runQuickBenchmarkWithCompletionHandler:(void(^)(CactusBenchmarkResult * _Nullable result, NSError * _Nullable error))completionHandler {
    [CactusBenchmark runBenchmarkWithCompletionHandler:completionHandler];
}

- (void)runBenchmarkWithConfiguration:(NSDictionary *)config
                    completionHandler:(void(^)(CactusBenchmarkResult * _Nullable result, NSError * _Nullable error))completionHandler {
    
    NSInteger promptTokens = [config[@"promptTokens"] integerValue] ?: 512;
    NSInteger generationTokens = [config[@"generationTokens"] integerValue] ?: 128;
    NSInteger parallel = [config[@"parallel"] integerValue] ?: 1;
    NSInteger repetitions = [config[@"repetitions"] integerValue] ?: 3;
    
    [CactusBenchmark runBenchmarkWithPromptTokens:promptTokens
                                 generationTokens:generationTokens
                                  parallelSequences:parallel
                                      repetitions:repetitions
                                completionHandler:completionHandler];
}

#pragma mark - Utilities

- (NSDictionary *)modelInfo {
    return self.currentModelInfo ?: @{};
}

- (NSDictionary *)systemInfo {
    return [CactusBenchmark systemPerformanceInfo];
}

- (NSDictionary *)performanceStats {
    return [CactusPerformanceMonitor currentPerformanceStats];
}

- (NSDictionary *)frameworkStatistics {
    NSDictionary *sessionStats = [[CactusSessionManager sharedManager] sessionStatistics];
    NSDictionary *processorStats = [[CactusBackgroundProcessor sharedProcessor] statistics];
    
    return @{
        @"sessions": sessionStats,
        @"backgroundProcessor": processorStats,
        @"modelLoaded": @(self.isModelLoaded),
        @"initialized": @(self.isInitialized)
    };
}

#pragma mark - Configuration

- (void)setLogLevel:(CactusLogLevel)level {
    [CactusLogger setLogLevel:level];
}

- (void)setMaxConcurrentSessions:(NSInteger)maxSessions {
    [[CactusSessionManager sharedManager] setMaxConcurrentSessions:maxSessions];
}

- (void)setMaxConcurrentTasks:(NSInteger)maxTasks {
    [[CactusBackgroundProcessor sharedProcessor] setMaxConcurrentTasks:maxTasks];
}

#pragma mark - Model Manager Delegate

- (void)modelManager:(CactusModelManager *)manager didChangeState:(CactusModelState)state {
    // Could notify delegate if needed
    NSLog(@"Model state changed to: %ld", (long)state);
}

- (void)modelManager:(CactusModelManager *)manager didLoadModelWithInfo:(NSDictionary *)info {
    if ([self.delegate respondsToSelector:@selector(framework:didLoadModel:)]) {
        [self.delegate framework:self didLoadModel:info];
    }
}

- (void)modelManager:(CactusModelManager *)manager didUpdateLoadingProgress:(float)progress {
    // Could notify delegate if needed
    NSLog(@"Model loading progress: %.1f%%", progress * 100);
}

- (void)modelManager:(CactusModelManager *)manager didFailToLoadWithError:(NSError *)error {
    if ([self.delegate respondsToSelector:@selector(framework:didFailToLoadModel:)]) {
        [self.delegate framework:self didFailToLoadModel:error];
    }
}

- (void)modelManagerDidUnloadModel:(CactusModelManager *)manager {
    // Could notify delegate if needed
    NSLog(@"Model unloaded");
}

#pragma mark - Session Manager Delegate

- (void)sessionManager:(CactusSessionManager *)manager didCreateSession:(CactusSession *)session {
    // Could notify delegate if needed
}

- (void)sessionManager:(CactusSessionManager *)manager didDestroySession:(CactusSession *)session {
    // Could notify delegate if needed
}

- (void)sessionManager:(CactusSessionManager *)manager session:(CactusSession *)session didChangeState:(CactusSessionState)state {
    // Could notify delegate if needed
    NSLog(@"Session %@ state changed to: %ld", session.sessionId.UUIDString, (long)state);
}

@end

#pragma mark - Convenience Extensions

@implementation CactusFrameworkModern (QuickSetup)

+ (void)setupForChatWithModelPath:(NSString *)modelPath
                completionHandler:(void(^)(CactusFrameworkModern * _Nullable framework, NSError * _Nullable error))completionHandler {
    
    CactusFrameworkModern *framework = [self shared];
    [framework initializeWithDelegate:nil];
    
    CactusModelConfiguration *config = [self fastChatConfiguration:modelPath];
    
    [framework loadModelWithConfiguration:config completionHandler:^(BOOL success, NSError * _Nullable error) {
        if (completionHandler) {
            completionHandler(success ? framework : nil, error);
        }
    }];
}

+ (void)setupForCompletionWithModelPath:(NSString *)modelPath
                      completionHandler:(void(^)(CactusFrameworkModern * _Nullable framework, NSError * _Nullable error))completionHandler {
    
    CactusFrameworkModern *framework = [self shared];
    [framework initializeWithDelegate:nil];
    
    CactusModelConfiguration *config = [CactusModelConfiguration configurationWithModelPath:modelPath];
    
    [framework loadModelWithConfiguration:config completionHandler:^(BOOL success, NSError * _Nullable error) {
        if (completionHandler) {
            completionHandler(success ? framework : nil, error);
        }
    }];
}

+ (void)setupForMultimodalWithModelPath:(NSString *)modelPath
                         projectionPath:(NSString *)projectionPath
                      completionHandler:(void(^)(CactusFrameworkModern * _Nullable framework, NSError * _Nullable error))completionHandler {
    
    CactusFrameworkModern *framework = [self shared];
    [framework initializeWithDelegate:nil];
    
    CactusModelConfiguration *config = [self multimodalConfiguration:modelPath projectionPath:projectionPath];
    
    [framework loadModelWithConfiguration:config completionHandler:^(BOOL success, NSError * _Nullable error) {
        if (success) {
            NSError *multimodalError = nil;
            BOOL multimodalSuccess = [framework initializeMultimodalWithProjectionPath:projectionPath error:&multimodalError];
            
            if (completionHandler) {
                completionHandler(multimodalSuccess ? framework : nil, multimodalError);
            }
        } else {
            if (completionHandler) {
                completionHandler(nil, error);
            }
        }
    }];
}

@end

@implementation CactusFrameworkModern (PresetConfigurations)

+ (CactusModelConfiguration *)fastChatConfiguration:(NSString *)modelPath {
    CactusModelConfiguration *config = [CactusModelConfiguration configurationWithModelPath:modelPath];
    config.contextSize = 2048;
    config.batchSize = 256;
    config.flashAttention = YES;
    return config;
}

+ (CactusModelConfiguration *)highQualityChatConfiguration:(NSString *)modelPath {
    CactusModelConfiguration *config = [CactusModelConfiguration configurationWithModelPath:modelPath];
    config.contextSize = 8192;
    config.batchSize = 512;
    config.flashAttention = YES;
    return config;
}

+ (CactusModelConfiguration *)embeddingConfiguration:(NSString *)modelPath {
    CactusModelConfiguration *config = [CactusModelConfiguration configurationWithModelPath:modelPath];
    config.enableEmbedding = YES;
    config.contextSize = 1024;
    return config;
}

+ (CactusModelConfiguration *)multimodalConfiguration:(NSString *)modelPath projectionPath:(NSString *)projectionPath {
    CactusModelConfiguration *config = [self highQualityChatConfiguration:modelPath];
    // Multimodal models typically need more context
    config.contextSize = 4096;
    return config;
}

@end

@implementation CactusFrameworkModern (AsyncAwait)

#if __has_feature(objc_generics) && defined(__IPHONE_13_0)

// These would be implemented using modern async/await patterns
// Placeholder implementations for now

- (void)loadModelAtPathAsync:(NSString *)modelPath API_AVAILABLE(ios(13.0)) {
    // Implementation would use async/await
}

- (void)chatWithMessageAsync:(NSString *)message API_AVAILABLE(ios(13.0)) {
    // Implementation would use async/await
}

- (void)completeTextAsync:(NSString *)prompt API_AVAILABLE(ios(13.0)) {
    // Implementation would use async/await
}

#endif

@end

#pragma mark - Builder Pattern

@interface CactusFrameworkBuilder ()
@property (nonatomic, strong) NSString *modelPath;
@property (nonatomic, strong) CactusModelConfiguration *configuration;
@property (nonatomic, weak) id<CactusFrameworkDelegate> delegate;
@property (nonatomic, assign) CactusLogLevel logLevel;
@property (nonatomic, assign) NSInteger maxConcurrentSessions;
@end

@implementation CactusFrameworkBuilder

+ (instancetype)builder {
    return [[self alloc] init];
}

- (instancetype)init {
    if (self = [super init]) {
        _logLevel = CactusLogLevelInfo;
        _maxConcurrentSessions = 5;
    }
    return self;
}

- (instancetype)withModelPath:(NSString *)modelPath {
    self.modelPath = modelPath;
    return self;
}

- (instancetype)withConfiguration:(CactusModelConfiguration *)configuration {
    self.configuration = configuration;
    return self;
}

- (instancetype)withDelegate:(id<CactusFrameworkDelegate>)delegate {
    self.delegate = delegate;
    return self;
}

- (instancetype)withLogLevel:(CactusLogLevel)logLevel {
    self.logLevel = logLevel;
    return self;
}

- (instancetype)withMaxConcurrentSessions:(NSInteger)maxSessions {
    self.maxConcurrentSessions = maxSessions;
    return self;
}

- (void)buildAndInitializeWithCompletionHandler:(void(^)(CactusFrameworkModern * _Nullable framework, NSError * _Nullable error))completionHandler {
    
    CactusFrameworkModern *framework = [CactusFrameworkModern shared];
    
    // Apply configuration
    [framework setLogLevel:self.logLevel];
    [framework setMaxConcurrentSessions:self.maxConcurrentSessions];
    
    // Initialize
    [framework initializeWithDelegate:self.delegate];
    
    // Load model if specified
    if (self.configuration) {
        [framework loadModelWithConfiguration:self.configuration completionHandler:^(BOOL success, NSError * _Nullable error) {
            if (completionHandler) {
                completionHandler(success ? framework : nil, error);
            }
        }];
    } else if (self.modelPath) {
        [framework loadModelAtPath:self.modelPath completionHandler:^(BOOL success, NSError * _Nullable error) {
            if (completionHandler) {
                completionHandler(success ? framework : nil, error);
            }
        }];
    } else {
        // No model specified, just return initialized framework
        if (completionHandler) {
            completionHandler(framework, nil);
        }
    }
}

@end

#pragma mark - Error Extensions

@implementation NSError (CactusFramework)

+ (instancetype)cactusErrorWithCode:(NSInteger)code description:(NSString *)description {
    return [self cactusErrorWithCode:code description:description underlyingError:nil];
}

+ (instancetype)cactusErrorWithCode:(NSInteger)code description:(NSString *)description underlyingError:(NSError *)underlyingError {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    userInfo[NSLocalizedDescriptionKey] = description;
    
    if (underlyingError) {
        userInfo[NSUnderlyingErrorKey] = underlyingError;
    }
    
    return [NSError errorWithDomain:CactusLLMErrorDomain code:code userInfo:[userInfo copy]];
}

@end
