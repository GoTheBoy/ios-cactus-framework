//
//  CactusUtilities.mm
//  CactusFramework
//

#import "CactusUtilities.h"
#import "CactusModelManager.h"
#import "CactusBackgroundProcessor.h"
#import "CactusLLMError.h"
#import "cactus/cactus.h"
#import "cactus/common.h"
#import "cactus/llama-vocab.h"
#import <mach/mach.h>
#import <sys/sysctl.h>

// MARK: - Tokenizer Implementation

@implementation CactusTokenizer

+ (NSArray<NSNumber *> *)tokenizeText:(NSString *)text error:(NSError **)error {
    return [self tokenizeText:text mediaPaths:nil error:error];
}

+ (NSArray<NSNumber *> *)tokenizeText:(NSString *)text
                           mediaPaths:(NSArray<NSString *> *)mediaPaths
                                error:(NSError **)error {
    cactus::cactus_context *context = (cactus::cactus_context *)[[CactusModelManager sharedManager] internalContext];
    
    if (!context) {
        if (error) {
            *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                         code:CactusLLMErrorModelNotLoaded
                                     userInfo:@{NSLocalizedDescriptionKey: @"Model not loaded"}];
        }
        return nil;
    }
    
    @try {
        std::vector<llama_token> tokens;
        
        if (mediaPaths && mediaPaths.count > 0) {
            // Convert NSArray to std::vector
            std::vector<std::string> media_paths;
            for (NSString *path in mediaPaths) {
                media_paths.push_back(path.UTF8String);
            }
            tokens = context->tokenize(text.UTF8String, media_paths).tokens;
        } else {
            tokens = context->tokenize(text.UTF8String, std::vector<std::string>()).tokens;
        }
        
        NSMutableArray<NSNumber *> *result = [NSMutableArray arrayWithCapacity:tokens.size()];
        for (const auto& token : tokens) {
            [result addObject:@(token)];
        }
        
        return [result copy];
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                         code:CactusLLMErrorTokenizationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Tokenization failed"}];
        }
        return nil;
    }
}

+ (NSString *)detokenizeTokens:(NSArray<NSNumber *> *)tokens error:(NSError **)error {
    cactus::cactus_context *context = (cactus::cactus_context *)[[CactusModelManager sharedManager] internalContext];
    
    if (!context) {
        if (error) {
            *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                         code:CactusLLMErrorModelNotLoaded
                                     userInfo:@{NSLocalizedDescriptionKey: @"Model not loaded"}];
        }
        return nil;
    }
    
    @try {
        std::vector<llama_token> token_vector;
        for (NSNumber *token in tokens) {
            token_vector.push_back([token intValue]);
        }
        
        std::string result = common_detokenize(context->ctx, token_vector);
        return @(result.c_str());
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                         code:CactusLLMErrorDetokenizationFailed
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Detokenization failed"}];
        }
        return nil;
    }
}

+ (NSInteger)countTokensInText:(NSString *)text {
    NSArray<NSNumber *> *tokens = [self tokenizeText:text error:nil];
    return tokens ? tokens.count : 0;
}

+ (NSInteger)countTokensInMessages:(NSArray<NSDictionary *> *)messages {
    NSInteger totalTokens = 0;
    
    for (NSDictionary *message in messages) {
        NSString *content = message[@"content"];
        if (content) {
            totalTokens += [self countTokensInText:content];
        }
    }
    
    return totalTokens;
}

+ (NSInteger)vocabularySize {
   
    cactus::cactus_context *context = (cactus::cactus_context *)[[CactusModelManager sharedManager] internalContext];
    if (!context) return 0;
    
    const llama_vocab * vocab = llama_model_get_vocab(context->model);
    return vocab->n_tokens();
}

+ (NSString *)tokenToString:(NSInteger)tokenId {
    cactus::cactus_context *context = (cactus::cactus_context *)[[CactusModelManager sharedManager] internalContext];
    
    if (!context) return nil;
    
    @try {
        std::vector<llama_token> tokens = {(llama_token)tokenId};
        std::string result = common_detokenize(context->ctx, tokens);
        return @(result.c_str());
    } @catch (...) {
        return nil;
    }
}

+ (NSInteger)stringToToken:(NSString *)string {
    NSArray<NSNumber *> *tokens = [self tokenizeText:string error:nil];
    return (tokens && tokens.count > 0) ? tokens.firstObject.integerValue : -1;
}

@end

// MARK: - Benchmark Result Implementation

@implementation CactusBenchmarkResult

- (instancetype)initWithPromptTokens:(NSInteger)promptTokens
                    generationTokens:(NSInteger)generationTokens
                     parallelSequences:(NSInteger)parallel
                         repetitions:(NSInteger)repetitions
                  promptProcessingSpeed:(double)ppSpeed
                    textGenerationSpeed:(double)tgSpeed
                           totalTime:(double)totalTime
                     detailedResults:(NSDictionary *)detailedResults {
    if (self = [super init]) {
        _promptProcessingTokens = promptTokens;
        _textGenerationTokens = generationTokens;
        _parallelSequences = parallel;
        _repetitions = repetitions;
        _promptProcessingSpeed = ppSpeed;
        _textGenerationSpeed = tgSpeed;
        _totalTime = totalTime;
        _detailedResults = [detailedResults copy];
        _timestamp = [NSDate date];
    }
    return self;
}

+ (instancetype)resultWithPromptTokens:(NSInteger)promptTokens
                      generationTokens:(NSInteger)generationTokens
                       parallelSequences:(NSInteger)parallel
                           repetitions:(NSInteger)repetitions
                    promptProcessingSpeed:(double)ppSpeed
                      textGenerationSpeed:(double)tgSpeed
                             totalTime:(double)totalTime
                       detailedResults:(NSDictionary *)detailedResults {
    return [[self alloc] initWithPromptTokens:promptTokens
                             generationTokens:generationTokens
                              parallelSequences:parallel
                                  repetitions:repetitions
                           promptProcessingSpeed:ppSpeed
                             textGenerationSpeed:tgSpeed
                                    totalTime:totalTime
                              detailedResults:detailedResults];
}

- (NSString *)summaryString {
    return [NSString stringWithFormat:@"Benchmark Results:\n"
            @"  Prompt Processing: %.1f tokens/sec (%ld tokens)\n"
            @"  Text Generation: %.1f tokens/sec (%ld tokens)\n"
            @"  Total Time: %.2f seconds\n"
            @"  Parallel Sequences: %ld, Repetitions: %ld",
            self.promptProcessingSpeed, (long)self.promptProcessingTokens,
            self.textGenerationSpeed, (long)self.textGenerationTokens,
            self.totalTime,
            (long)self.parallelSequences, (long)self.repetitions];
}

- (NSDictionary *)toDictionary {
    return @{
        @"promptProcessingTokens": @(self.promptProcessingTokens),
        @"textGenerationTokens": @(self.textGenerationTokens),
        @"parallelSequences": @(self.parallelSequences),
        @"repetitions": @(self.repetitions),
        @"promptProcessingSpeed": @(self.promptProcessingSpeed),
        @"textGenerationSpeed": @(self.textGenerationSpeed),
        @"totalTime": @(self.totalTime),
        @"timestamp": self.timestamp,
        @"detailedResults": self.detailedResults ?: @{}
    };
}

@end

// MARK: - Benchmark Implementation

@implementation CactusBenchmark

+ (void)runBenchmarkWithCompletionHandler:(void(^)(CactusBenchmarkResult * _Nullable result, NSError * _Nullable error))completionHandler {
    [self runBenchmarkWithPromptTokens:512
                       generationTokens:128
                        parallelSequences:1
                            repetitions:3
                      completionHandler:completionHandler];
}

+ (void)runBenchmarkWithPromptTokens:(NSInteger)promptTokens
                    generationTokens:(NSInteger)generationTokens
                     parallelSequences:(NSInteger)parallel
                         repetitions:(NSInteger)repetitions
                   completionHandler:(void(^)(CactusBenchmarkResult * _Nullable result, NSError * _Nullable error))completionHandler {
    
    [self runProgressiveBenchmarkWithPromptTokens:promptTokens
                                 generationTokens:generationTokens
                                  parallelSequences:parallel
                                      repetitions:repetitions
                                  progressHandler:nil
                                completionHandler:completionHandler];
}

+ (NSUUID *)runProgressiveBenchmarkWithPromptTokens:(NSInteger)promptTokens
                                   generationTokens:(NSInteger)generationTokens
                                    parallelSequences:(NSInteger)parallel
                                        repetitions:(NSInteger)repetitions
                                    progressHandler:(void(^)(float progress, NSString *status))progressHandler
                                  completionHandler:(void(^)(CactusBenchmarkResult * _Nullable result, NSError * _Nullable error))completionHandler {
    
    CactusTask *benchmarkTask = [CactusTask taskWithType:CactusTaskTypeBenchmark
                                                priority:CactusTaskPriorityLow
                                             description:@"Running performance benchmark"
                                          executionBlock:^id(CactusTask *task, CactusTaskProgressHandler progress) {
        
        cactus::cactus_context *context = (cactus::cactus_context *)[[CactusModelManager sharedManager] internalContext];
        
        if (!context) {
            @throw [NSException exceptionWithName:@"ModelNotLoaded"
                                           reason:@"Model not loaded for benchmark"
                                         userInfo:nil];
        }
        
        progress(0.1f);
        
        // Run benchmark using cactus context
        std::string benchResult = context->bench((int)promptTokens, (int)generationTokens, (int)parallel, (int)repetitions);
        
        progress(0.9f);
        
        // Parse JSON result
        NSData *jsonData = [NSData dataWithBytes:benchResult.c_str() length:benchResult.length()];
        NSError *jsonError = nil;
        id jsonResult = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
        
        if (jsonError) {
            @throw [NSException exceptionWithName:@"BenchmarkParseError"
                                           reason:jsonError.localizedDescription
                                         userInfo:@{@"error": jsonError}];
        }
        
        progress(1.0f);
        
        // Create result object
        NSDictionary *resultDict = (NSDictionary *)jsonResult;
        
        double ppSpeed = [resultDict[@"prompt_processing_speed"] doubleValue];
        double tgSpeed = [resultDict[@"text_generation_speed"] doubleValue];
        double totalTime = [resultDict[@"total_time"] doubleValue];
        
        CactusBenchmarkResult *result = [CactusBenchmarkResult resultWithPromptTokens:promptTokens
                                                                     generationTokens:generationTokens
                                                                      parallelSequences:parallel
                                                                          repetitions:repetitions
                                                                   promptProcessingSpeed:ppSpeed
                                                                     textGenerationSpeed:tgSpeed
                                                                            totalTime:totalTime
                                                                      detailedResults:resultDict];
        
        return result;
    }];
    
    benchmarkTask.progressHandler = ^(float progress) {
        if (progressHandler) {
            NSString *status = @"Running benchmark...";
            if (progress < 0.2f) status = @"Initializing benchmark...";
            else if (progress < 0.5f) status = @"Testing prompt processing...";
            else if (progress < 0.8f) status = @"Testing text generation...";
            else if (progress < 1.0f) status = @"Finalizing results...";
            else status = @"Benchmark completed";
            
            progressHandler(progress, status);
        }
    };
    
    benchmarkTask.completionHandler = ^(id result, NSError *error) {
        if (completionHandler) {
            completionHandler((CactusBenchmarkResult *)result, error);
        }
    };
    
    [[CactusBackgroundProcessor sharedProcessor] submitTask:benchmarkTask];
    
    return benchmarkTask.taskId;
}

+ (void)cancelBenchmark:(NSUUID *)benchmarkId {
    [[CactusBackgroundProcessor sharedProcessor] cancelTask:benchmarkId];
}

+ (NSDictionary *)systemPerformanceInfo {
    NSProcessInfo *processInfo = [NSProcessInfo processInfo];
    
    // Get CPU info
    size_t size = sizeof(int);
    int cpuCount;
    sysctlbyname("hw.ncpu", &cpuCount, &size, NULL, 0);
    
    // Get memory info
    int64_t memSize;
    size = sizeof(memSize);
    sysctlbyname("hw.memsize", &memSize, &size, NULL, 0);
    
    return @{
        @"processorCount": @(processInfo.processorCount),
        @"activeProcessorCount": @(processInfo.activeProcessorCount),
        @"physicalMemory": @(processInfo.physicalMemory),
        @"cpuCount": @(cpuCount),
        @"totalMemory": @(memSize),
        @"systemUptime": @(processInfo.systemUptime)
    };
}

+ (NSDictionary *)memoryUsageInfo {
    struct mach_task_basic_info info;
    mach_msg_type_number_t size = MACH_TASK_BASIC_INFO_COUNT;
    
    kern_return_t kerr = task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &size);
    
    if (kerr == KERN_SUCCESS) {
        return @{
            @"residentSize": @(info.resident_size),
            @"virtualSize": @(info.virtual_size),
            @"residentSizeMB": @(info.resident_size / (1024 * 1024)),
            @"virtualSizeMB": @(info.virtual_size / (1024 * 1024))
        };
    }
    
    return @{};
}

@end

// MARK: - LoRA Manager Implementation

@implementation CactusLoRAManager

+ (BOOL)validateLoRAAdapter:(CactusLoRAAdapter *)adapter error:(NSError **)error {
    if (!adapter.path || adapter.path.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                         code:CactusLLMErrorInvalidArgument
                                     userInfo:@{NSLocalizedDescriptionKey: @"LoRA adapter path is required"}];
        }
        return NO;
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:adapter.path]) {
        if (error) {
            *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                         code:CactusLLMErrorFileNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"LoRA adapter file not found"}];
        }
        return NO;
    }
    
    if (adapter.scale <= 0) {
        if (error) {
            *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                         code:CactusLLMErrorInvalidArgument
                                     userInfo:@{NSLocalizedDescriptionKey: @"LoRA adapter scale must be positive"}];
        }
        return NO;
    }
    
    return YES;
}

+ (BOOL)validateLoRAConfiguration:(CactusLoRAConfiguration *)configuration error:(NSError **)error {
    if (!configuration.adapters || configuration.adapters.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                         code:CactusLLMErrorInvalidArgument
                                     userInfo:@{NSLocalizedDescriptionKey: @"LoRA configuration must have at least one adapter"}];
        }
        return NO;
    }
    
    for (CactusLoRAAdapter *adapter in configuration.adapters) {
        if (![self validateLoRAAdapter:adapter error:error]) {
            return NO;
        }
    }
    
    return YES;
}

+ (NSDictionary *)getLoRAInfo:(NSString *)loraPath error:(NSError **)error {
    if (![[NSFileManager defaultManager] fileExistsAtPath:loraPath]) {
        if (error) {
            *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                         code:CactusLLMErrorFileNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"LoRA file not found"}];
        }
        return nil;
    }
    
    NSError *fileError = nil;
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:loraPath error:&fileError];
    
    if (fileError) {
        if (error) *error = fileError;
        return nil;
    }
    
    return @{
        @"path": loraPath,
        @"filename": loraPath.lastPathComponent,
        @"size": fileAttributes[NSFileSize] ?: @0,
        @"modificationDate": fileAttributes[NSFileModificationDate] ?: [NSDate distantPast]
    };
}

+ (NSArray<NSString *> *)supportedLoRAFormats {
    return @[@"gguf", @"safetensors", @"bin"];
}

+ (BOOL)applyLoRAAdapters:(NSArray<CactusLoRAAdapter *> *)adapters error:(NSError **)error {
    CactusLoRAConfiguration *config = [CactusLoRAConfiguration configurationWithAdapters:adapters];
    return [[CactusModelManager sharedManager] applyLoRAConfiguration:config error:error];
}

+ (void)removeAllLoRAAdapters {
    [[CactusModelManager sharedManager] removeAllLoRAAdapters];
}

+ (NSArray<CactusLoRAAdapter *> *)loadedAdapters {
    return [[CactusModelManager sharedManager] loadedLoRAAdapters];
}

+ (BOOL)isLoRASupported {
    return [[CactusModelManager sharedManager] isLoaded];
}

+ (NSString *)loRAStatusDescription {
    NSArray<CactusLoRAAdapter *> *adapters = [self loadedAdapters];
    
    if (adapters.count == 0) {
        return @"No LoRA adapters loaded";
    }
    
    return [NSString stringWithFormat:@"%ld LoRA adapter%@ loaded", 
            (long)adapters.count, adapters.count == 1 ? @"" : @"s"];
}

@end

// MARK: - Model Utilities Implementation

@implementation CactusModelUtilities

+ (NSDictionary *)getModelInfo:(NSString *)modelPath error:(NSError **)error {
    return [CactusModelManager quickModelInfoForPath:modelPath];
}

+ (NSDictionary *)getDetailedModelInfo:(NSString *)modelPath error:(NSError **)error {
    // This would use the actual model inspection functionality
    NSDictionary *basicInfo = [self getModelInfo:modelPath error:error];
    
    if (!basicInfo) return nil;
    
    NSMutableDictionary *detailedInfo = [basicInfo mutableCopy];
    
    // Add format detection
    NSString *format = [self detectModelFormat:modelPath];
    if (format) {
        detailedInfo[@"format"] = format;
    }
    
    // Add compatibility check
    detailedInfo[@"compatible"] = @([self isModelCompatible:modelPath error:nil]);
    
    return [detailedInfo copy];
}

+ (BOOL)validateModelFile:(NSString *)modelPath error:(NSError **)error {
    if (![[NSFileManager defaultManager] fileExistsAtPath:modelPath]) {
        if (error) {
            *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                         code:CactusLLMErrorFileNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Model file not found"}];
        }
        return NO;
    }
    
    // Check file size
    NSError *fileError = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:modelPath error:&fileError];
    
    if (fileError) {
        if (error) *error = fileError;
        return NO;
    }
    
    NSUInteger fileSize = [attributes[NSFileSize] unsignedIntegerValue];
    if (fileSize < 1024) { // Less than 1KB is probably not a valid model
        if (error) {
            *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                         code:CactusLLMErrorInvalidModel
                                     userInfo:@{NSLocalizedDescriptionKey: @"Model file is too small"}];
        }
        return NO;
    }
    
    return YES;
}

+ (BOOL)isModelCompatible:(NSString *)modelPath error:(NSError **)error {
    NSString *format = [self detectModelFormat:modelPath];
    NSArray<NSString *> *supportedFormats = [self supportedModelFormats];
    
    return [supportedFormats containsObject:format];
}

+ (NSString *)detectModelFormat:(NSString *)modelPath {
    NSString *extension = modelPath.pathExtension.lowercaseString;
    
    if ([extension isEqualToString:@"gguf"]) {
        return @"GGUF";
    } else if ([extension isEqualToString:@"bin"]) {
        return @"GGML";
    } else if ([extension isEqualToString:@"safetensors"]) {
        return @"SafeTensors";
    }
    
    return @"Unknown";
}

+ (NSArray<NSString *> *)supportedModelFormats {
    return @[@"GGUF", @"GGML"];
}

+ (NSUInteger)estimateModelMemoryUsage:(NSString *)modelPath {
    NSDictionary *info = [self getModelInfo:modelPath error:nil];
    NSUInteger fileSize = [info[@"size"] unsignedIntegerValue];
    
    // Rough estimation: model size + overhead
    return fileSize + (fileSize / 10); // 10% overhead
}

+ (NSUInteger)estimateContextMemoryUsage:(NSInteger)contextSize {
    // Rough estimation: context size * bytes per token * overhead
    return contextSize * 4 * 2; // 4 bytes per token, 2x overhead
}

+ (CactusModelConfiguration *)recommendedConfigurationForModel:(NSString *)modelPath {
    CactusModelConfiguration *config = [CactusModelConfiguration configurationWithModelPath:modelPath];
    
    NSUInteger fileSize = [self estimateModelMemoryUsage:modelPath];
    NSUInteger availableMemory = [NSProcessInfo processInfo].physicalMemory;
    
    // Adjust settings based on model size and available memory
    if (fileSize > availableMemory / 2) {
        // Large model - conservative settings
        config.contextSize = 2048;
        config.batchSize = 256;
        config.gpuLayers = 0; // Use CPU to save GPU memory
    } else {
        // Smaller model - default settings
        config.contextSize = 4096;
        config.batchSize = 512;
        config.gpuLayers = -1; // Auto-detect
    }
    
    return config;
}

+ (CactusGenerationConfiguration *)recommendedGenerationConfigForTask:(NSString *)taskType {
    if ([taskType isEqualToString:@"chat"]) {
        return [CactusGenerationConfiguration defaultConfiguration];
    } else if ([taskType isEqualToString:@"creative"]) {
        return [CactusGenerationConfiguration creativeConfiguration];
    } else if ([taskType isEqualToString:@"precise"]) {
        return [CactusGenerationConfiguration preciseConfiguration];
    } else if ([taskType isEqualToString:@"fast"]) {
        return [CactusGenerationConfiguration fastConfiguration];
    }
    
    return [CactusGenerationConfiguration defaultConfiguration];
}

@end

// MARK: - Performance Monitor Implementation

static NSMutableArray<NSDictionary *> *performanceHistory = nil;
static NSTimer *monitoringTimer = nil;
static BOOL isCurrentlyMonitoring = NO;

@implementation CactusPerformanceMonitor

+ (void)initialize {
    if (self == [CactusPerformanceMonitor class]) {
        performanceHistory = [NSMutableArray array];
    }
}

+ (void)startMonitoring {
    if (isCurrentlyMonitoring) return;
    
    isCurrentlyMonitoring = YES;
    
    monitoringTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        NSDictionary *stats = [self currentPerformanceStats];
        @synchronized(performanceHistory) {
            [performanceHistory addObject:stats];
            
            // Keep only last 100 entries
            if (performanceHistory.count > 100) {
                [performanceHistory removeObjectAtIndex:0];
            }
        }
    }];
}

+ (void)stopMonitoring {
    if (!isCurrentlyMonitoring) return;
    
    isCurrentlyMonitoring = NO;
    
    if (monitoringTimer) {
        [monitoringTimer invalidate];
        monitoringTimer = nil;
    }
}

+ (BOOL)isMonitoring {
    return isCurrentlyMonitoring;
}

+ (NSDictionary *)currentPerformanceStats {
    return @{
        @"timestamp": [NSDate date],
        @"memory": [self memoryStats],
        @"cpu": [self cpuStats]
    };
}

+ (NSDictionary *)memoryStats {
    return [CactusBenchmark memoryUsageInfo];
}

+ (NSDictionary *)cpuStats {
    // Basic CPU stats - could be enhanced with more detailed metrics
    return @{
        @"processorCount": @([NSProcessInfo processInfo].processorCount),
        @"activeProcessorCount": @([NSProcessInfo processInfo].activeProcessorCount)
    };
}

+ (NSArray<NSDictionary *> *)performanceHistory {
    @synchronized(performanceHistory) {
        return [performanceHistory copy];
    }
}

+ (void)clearPerformanceHistory {
    @synchronized(performanceHistory) {
        [performanceHistory removeAllObjects];
    }
}

+ (void)setMemoryUsageThreshold:(NSUInteger)thresholdMB
                        handler:(void(^)(NSUInteger currentUsageMB))handler {
    // Implementation would monitor memory usage and call handler when threshold is exceeded
    // This is a placeholder
}

+ (void)setCPUUsageThreshold:(float)thresholdPercent
                     handler:(void(^)(float currentUsagePercent))handler {
    // Implementation would monitor CPU usage and call handler when threshold is exceeded
    // This is a placeholder
}

@end

// MARK: - File Utilities Implementation

@implementation CactusFileUtilities

+ (BOOL)fileExistsAtPath:(NSString *)path {
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

+ (NSUInteger)fileSizeAtPath:(NSString *)path {
    NSError *error = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
    
    if (error) return 0;
    
    return [attributes[NSFileSize] unsignedIntegerValue];
}

+ (NSDate *)fileModificationDateAtPath:(NSString *)path {
    NSError *error = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
    
    if (error) return nil;
    
    return attributes[NSFileModificationDate];
}

+ (BOOL)createDirectoryAtPath:(NSString *)path error:(NSError **)error {
    return [[NSFileManager defaultManager] createDirectoryAtPath:path
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:error];
}

+ (NSArray<NSString *> *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
    return [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:error];
}

+ (NSString *)findModelInDirectory:(NSString *)directory {
    NSArray<NSString *> *models = [self findAllModelsInDirectory:directory];
    return models.firstObject;
}

+ (NSArray<NSString *> *)findAllModelsInDirectory:(NSString *)directory {
    NSError *error = nil;
    NSArray<NSString *> *contents = [self contentsOfDirectoryAtPath:directory error:&error];
    
    if (error) return @[];
    
    NSMutableArray<NSString *> *models = [NSMutableArray array];
    NSArray<NSString *> *modelExtensions = @[@"gguf", @"bin", @"safetensors"];
    
    for (NSString *filename in contents) {
        NSString *extension = filename.pathExtension.lowercaseString;
        if ([modelExtensions containsObject:extension]) {
            [models addObject:[directory stringByAppendingPathComponent:filename]];
        }
    }
    
    return [models copy];
}

+ (void)cleanupTemporaryFiles {
    // Implementation would clean up temporary files
    // This is a placeholder
}

+ (NSUInteger)estimateCleanupSpace {
    // Implementation would estimate space that could be freed
    // This is a placeholder
    return 0;
}

@end

// MARK: - Logger Implementation

static CactusLogLevel currentLogLevel = CactusLogLevelInfo;
static void(^logHandler)(CactusLogLevel level, NSString *message) = nil;
static NSString *logFilePath = nil;

@implementation CactusLogger

+ (void)setLogLevel:(CactusLogLevel)level {
    currentLogLevel = level;
}

+ (CactusLogLevel)logLevel {
    return currentLogLevel;
}

+ (void)setLogHandler:(void(^)(CactusLogLevel level, NSString *message))handler {
    logHandler = [handler copy];
}

+ (void)logWithLevel:(CactusLogLevel)level format:(NSString *)format arguments:(va_list)arguments {
    if (level < currentLogLevel) return;
    
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    NSString *levelString = @"";
    
    switch (level) {
        case CactusLogLevelVerbose: levelString = @"VERBOSE"; break;
        case CactusLogLevelDebug: levelString = @"DEBUG"; break;
        case CactusLogLevelInfo: levelString = @"INFO"; break;
        case CactusLogLevelWarning: levelString = @"WARNING"; break;
        case CactusLogLevelError: levelString = @"ERROR"; break;
        case CactusLogLevelNone: return;
    }
    
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                         dateStyle:NSDateFormatterNoStyle
                                                         timeStyle:NSDateFormatterMediumStyle];
    
    NSString *logMessage = [NSString stringWithFormat:@"[%@] %@: %@", timestamp, levelString, message];
    
    // Console output
    NSLog(@"%@", logMessage);
    
    // Custom handler
    if (logHandler) {
        logHandler(level, logMessage);
    }
    
    // File logging
    if (logFilePath) {
        NSString *fileMessage = [logMessage stringByAppendingString:@"\n"];
        NSData *data = [fileMessage dataUsingEncoding:NSUTF8StringEncoding];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:logFilePath]) {
            [[NSFileManager defaultManager] createFileAtPath:logFilePath contents:nil attributes:nil];
        }
        
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logFilePath];
        if (fileHandle) {
            [fileHandle seekToEndOfFile];
            [fileHandle writeData:data];
            [fileHandle closeFile];
        }
    }
}

+ (void)verbose:(NSString *)format, ... {
    va_list arguments;
    va_start(arguments, format);
    [self logWithLevel:CactusLogLevelVerbose format:format arguments:arguments];
    va_end(arguments);
}

+ (void)debug:(NSString *)format, ... {
    va_list arguments;
    va_start(arguments, format);
    [self logWithLevel:CactusLogLevelDebug format:format arguments:arguments];
    va_end(arguments);
}

+ (void)info:(NSString *)format, ... {
    va_list arguments;
    va_start(arguments, format);
    [self logWithLevel:CactusLogLevelInfo format:format arguments:arguments];
    va_end(arguments);
}

+ (void)warning:(NSString *)format, ... {
    va_list arguments;
    va_start(arguments, format);
    [self logWithLevel:CactusLogLevelWarning format:format arguments:arguments];
    va_end(arguments);
}

+ (void)error:(NSString *)format, ... {
    va_list arguments;
    va_start(arguments, format);
    [self logWithLevel:CactusLogLevelError format:format arguments:arguments];
    va_end(arguments);
}

+ (void)enableFileLogging:(NSString *)filePath {
    logFilePath = [filePath copy];
}

+ (void)disableFileLogging {
    logFilePath = nil;
}

+ (NSString *)currentLogFilePath {
    return logFilePath;
}

+ (void)rotateLogFile {
    if (!logFilePath) return;
    
    NSString *backupPath = [logFilePath stringByAppendingString:@".bak"];
    
    NSError *error = nil;
    [[NSFileManager defaultManager] moveItemAtPath:logFilePath toPath:backupPath error:&error];
    
    if (error) {
        NSLog(@"Failed to rotate log file: %@", error.localizedDescription);
    }
}

@end
