//
//  CactusUtilities.h
//  CactusFramework
//
//  Utility classes for tokenization, benchmarking, and other operations
//

#import <Foundation/Foundation.h>
#import "CactusModelConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

// MARK: - Tokenizer

@interface CactusTokenizer : NSObject

// Tokenization
+ (nullable NSArray<NSNumber *> *)tokenizeText:(NSString *)text error:(NSError **)error;
+ (nullable NSArray<NSNumber *> *)tokenizeText:(NSString *)text
                                    mediaPaths:(nullable NSArray<NSString *> *)mediaPaths
                                         error:(NSError **)error;

// Detokenization
+ (nullable NSString *)detokenizeTokens:(NSArray<NSNumber *> *)tokens error:(NSError **)error;

// Token counting
+ (NSInteger)countTokensInText:(NSString *)text;
+ (NSInteger)countTokensInMessages:(NSArray<NSDictionary *> *)messages;

// Vocabulary info
+ (NSInteger)vocabularySize;
+ (nullable NSString *)tokenToString:(NSInteger)tokenId;
+ (NSInteger)stringToToken:(NSString *)string;

@end

// MARK: - Benchmark

@interface CactusBenchmarkResult : NSObject

@property (nonatomic, readonly) NSInteger promptProcessingTokens;
@property (nonatomic, readonly) NSInteger textGenerationTokens;
@property (nonatomic, readonly) NSInteger parallelSequences;
@property (nonatomic, readonly) NSInteger repetitions;

@property (nonatomic, readonly) double promptProcessingSpeed; // tokens/second
@property (nonatomic, readonly) double textGenerationSpeed;  // tokens/second
@property (nonatomic, readonly) double totalTime;           // seconds

@property (nonatomic, readonly) NSDictionary *detailedResults;
@property (nonatomic, readonly) NSDate *timestamp;

+ (instancetype)resultWithPromptTokens:(NSInteger)promptTokens
                      generationTokens:(NSInteger)generationTokens
                       parallelSequences:(NSInteger)parallel
                           repetitions:(NSInteger)repetitions
                    promptProcessingSpeed:(double)ppSpeed
                      textGenerationSpeed:(double)tgSpeed
                             totalTime:(double)totalTime
                       detailedResults:(NSDictionary *)detailedResults;

- (NSString *)summaryString;
- (NSDictionary *)toDictionary;

@end

@interface CactusBenchmark : NSObject

// Simple benchmark
+ (void)runBenchmarkWithCompletionHandler:(void(^)(CactusBenchmarkResult * _Nullable result, NSError * _Nullable error))completionHandler;

// Detailed benchmark
+ (void)runBenchmarkWithPromptTokens:(NSInteger)promptTokens
                    generationTokens:(NSInteger)generationTokens
                     parallelSequences:(NSInteger)parallel
                         repetitions:(NSInteger)repetitions
                   completionHandler:(void(^)(CactusBenchmarkResult * _Nullable result, NSError * _Nullable error))completionHandler;

// Progressive benchmark with updates
+ (NSUUID *)runProgressiveBenchmarkWithPromptTokens:(NSInteger)promptTokens
                                   generationTokens:(NSInteger)generationTokens
                                    parallelSequences:(NSInteger)parallel
                                        repetitions:(NSInteger)repetitions
                                    progressHandler:(nullable void(^)(float progress, NSString *status))progressHandler
                                  completionHandler:(void(^)(CactusBenchmarkResult * _Nullable result, NSError * _Nullable error))completionHandler;

// Cancel benchmark
+ (void)cancelBenchmark:(NSUUID *)benchmarkId;

// System benchmarks
+ (NSDictionary *)systemPerformanceInfo;
+ (NSDictionary *)memoryUsageInfo;

@end

// MARK: - LoRA Manager

@interface CactusLoRAManager : NSObject

// LoRA operations
+ (BOOL)validateLoRAAdapter:(CactusLoRAAdapter *)adapter error:(NSError **)error;
+ (BOOL)validateLoRAConfiguration:(CactusLoRAConfiguration *)configuration error:(NSError **)error;

// LoRA info
+ (nullable NSDictionary *)getLoRAInfo:(NSString *)loraPath error:(NSError **)error;
+ (NSArray<NSString *> *)supportedLoRAFormats;

// Batch operations
+ (BOOL)applyLoRAAdapters:(NSArray<CactusLoRAAdapter *> *)adapters error:(NSError **)error;
+ (void)removeAllLoRAAdapters;

// LoRA utilities
+ (NSArray<CactusLoRAAdapter *> *)loadedAdapters;
+ (BOOL)isLoRASupported;
+ (NSString *)loRAStatusDescription;

@end

// MARK: - Model Utilities

@interface CactusModelUtilities : NSObject

// Model information
+ (nullable NSDictionary *)getModelInfo:(NSString *)modelPath error:(NSError **)error;
+ (nullable NSDictionary *)getDetailedModelInfo:(NSString *)modelPath error:(NSError **)error;

// Model validation
+ (BOOL)validateModelFile:(NSString *)modelPath error:(NSError **)error;
+ (BOOL)isModelCompatible:(NSString *)modelPath error:(NSError **)error;

// Model format detection
+ (nullable NSString *)detectModelFormat:(NSString *)modelPath;
+ (NSArray<NSString *> *)supportedModelFormats;

// Model size estimation
+ (NSUInteger)estimateModelMemoryUsage:(NSString *)modelPath;
+ (NSUInteger)estimateContextMemoryUsage:(NSInteger)contextSize;

// Model recommendations
+ (CactusModelConfiguration *)recommendedConfigurationForModel:(NSString *)modelPath;
+ (CactusGenerationConfiguration *)recommendedGenerationConfigForTask:(NSString *)taskType;

@end

// MARK: - Performance Monitor

@interface CactusPerformanceMonitor : NSObject

// Monitoring
+ (void)startMonitoring;
+ (void)stopMonitoring;
+ (BOOL)isMonitoring;

// Current stats
+ (NSDictionary *)currentPerformanceStats;
+ (NSDictionary *)memoryStats;
+ (NSDictionary *)cpuStats;

// Historical data
+ (NSArray<NSDictionary *> *)performanceHistory;
+ (void)clearPerformanceHistory;

// Alerts
+ (void)setMemoryUsageThreshold:(NSUInteger)thresholdMB
                        handler:(void(^)(NSUInteger currentUsageMB))handler;
+ (void)setCPUUsageThreshold:(float)thresholdPercent
                     handler:(void(^)(float currentUsagePercent))handler;

@end

// MARK: - File Utilities

@interface CactusFileUtilities : NSObject

// File operations
+ (BOOL)fileExistsAtPath:(NSString *)path;
+ (NSUInteger)fileSizeAtPath:(NSString *)path;
+ (nullable NSDate *)fileModificationDateAtPath:(NSString *)path;

// Directory operations
+ (BOOL)createDirectoryAtPath:(NSString *)path error:(NSError **)error;
+ (nullable NSArray<NSString *> *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error;

// Model file operations
+ (nullable NSString *)findModelInDirectory:(NSString *)directory;
+ (NSArray<NSString *> *)findAllModelsInDirectory:(NSString *)directory;

// Cleanup operations
+ (void)cleanupTemporaryFiles;
+ (NSUInteger)estimateCleanupSpace;

@end

// MARK: - Logging

typedef NS_ENUM(NSInteger, CactusLogLevel) {
    CactusLogLevelVerbose = 0,
    CactusLogLevelDebug = 1,
    CactusLogLevelInfo = 2,
    CactusLogLevelWarning = 3,
    CactusLogLevelError = 4,
    CactusLogLevelNone = 5
};

@interface CactusLogger : NSObject

// Configuration
+ (void)setLogLevel:(CactusLogLevel)level;
+ (CactusLogLevel)logLevel;
+ (void)setLogHandler:(nullable void(^)(CactusLogLevel level, NSString *message))handler;

// Logging methods
+ (void)verbose:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
+ (void)debug:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
+ (void)info:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
+ (void)warning:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
+ (void)error:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

// Log file operations
+ (void)enableFileLogging:(NSString *)logFilePath;
+ (void)disableFileLogging;
+ (nullable NSString *)currentLogFilePath;
+ (void)rotateLogFile;

@end

NS_ASSUME_NONNULL_END
