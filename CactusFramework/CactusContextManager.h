//
//  CactusContextManager.h
//  CactusFramework
//
//  Smart context management to prevent memory overflow
//

#import <Foundation/Foundation.h>
#import "CactusLLMMessage.h"

NS_ASSUME_NONNULL_BEGIN

// Context retention strategies
typedef NS_ENUM(NSInteger, CactusContextRetentionStrategy) {
    CactusContextRetentionStrategyKeepAll = 0,           // Keep all messages (default)
    CactusContextRetentionStrategySlidingWindow = 1,     // Keep last N messages
    CactusContextRetentionStrategySmartCompression = 2,  // Compress old messages
    CactusContextRetentionStrategySummaryBased = 3,      // Replace old with summary
    CactusContextRetentionStrategyTokenBased = 4         // Keep within token limit
};

// Context compression levels
typedef NS_ENUM(NSInteger, CactusContextCompressionLevel) {
    CactusContextCompressionLevelNone = 0,      // No compression
    CactusContextCompressionLevelLight = 1,     // Light compression (keep key points)
    CactusContextCompressionLevelMedium = 2,    // Medium compression (summarize)
    CactusContextCompressionLevelHeavy = 3      // Heavy compression (essential only)
};

// Context statistics
@interface CactusContextStats : NSObject
@property (nonatomic, readonly) NSInteger totalMessages;
@property (nonatomic, readonly) NSInteger totalTokens;
@property (nonatomic, readonly) NSInteger userMessages;
@property (nonatomic, readonly) NSInteger assistantMessages;
@property (nonatomic, readonly) NSInteger systemMessages;
@property (nonatomic, readonly) float compressionRatio;
@property (nonatomic, readonly) NSTimeInterval lastCompressionTime;
@end

// Context management delegate
@protocol CactusContextManagerDelegate <NSObject>
@optional
- (void)contextManager:(id)manager didCompressMessages:(NSArray<CactusLLMMessage *> *)messages;
- (void)contextManager:(id)manager didRemoveMessages:(NSArray<CactusLLMMessage *> *)messages;
- (void)contextManager:(id)manager didUpdateContextStats:(CactusContextStats *)stats;
- (void)contextManager:(id)manager didExceedTokenLimit:(NSInteger)currentTokens limit:(NSInteger)limit;
@end

// Main context manager interface
@interface CactusContextManager : NSObject

@property (nonatomic, weak, nullable) id<CactusContextManagerDelegate> delegate;
@property (nonatomic, assign) CactusContextRetentionStrategy retentionStrategy;
@property (nonatomic, assign) CactusContextCompressionLevel compressionLevel;
@property (nonatomic, assign) NSInteger maxContextTokens;
@property (nonatomic, assign) NSInteger maxMessages;
@property (nonatomic, assign) BOOL enableSmartCompression;
@property (nonatomic, assign) BOOL enableTokenCounting;
@property (nonatomic, assign) BOOL enableAutoCleanup;

// Singleton
+ (instancetype)sharedManager;

// Configuration
- (void)setMaxContextTokens:(NSInteger)maxTokens;
- (void)setMaxMessages:(NSInteger)maxMessages;
- (void)setRetentionStrategy:(CactusContextRetentionStrategy)strategy;
- (void)setCompressionLevel:(CactusContextCompressionLevel)level;

// Context management
- (NSArray<CactusLLMMessage *> *)getOptimizedContextForMessages:(NSArray<CactusLLMMessage *> *)messages;
- (NSArray<CactusLLMMessage *> *)compressMessages:(NSArray<CactusLLMMessage *> *)messages;
- (void)cleanupOldMessages:(NSMutableArray<CactusLLMMessage *> *)messages;
- (NSArray<CactusLLMMessage *> *)createSummaryFromMessages:(NSArray<CactusLLMMessage *> *)messages;

// Token management
- (NSInteger)estimateTokenCountForMessages:(NSArray<CactusLLMMessage *> *)messages;
- (NSInteger)estimateTokenCountForText:(NSString *)text;
- (BOOL)wouldExceedTokenLimit:(NSArray<CactusLLMMessage *> *)messages;

// Statistics and monitoring
- (CactusContextStats *)getContextStatsForMessages:(NSArray<CactusLLMMessage *> *)messages;
- (void)resetStatistics;

// Utility methods
- (NSArray<CactusLLMMessage *> *)prioritizeMessages:(NSArray<CactusLLMMessage *> *)messages;
- (NSArray<CactusLLMMessage *> *)filterMessagesByImportance:(NSArray<CactusLLMMessage *> *)messages;
- (BOOL)isMessageImportant:(CactusLLMMessage *)message;

@end

NS_ASSUME_NONNULL_END
