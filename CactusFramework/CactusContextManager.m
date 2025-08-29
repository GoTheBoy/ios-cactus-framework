//
//  CactusContextManager.m
//  CactusFramework
//
//  Smart context management implementation
//

#import "CactusContextManager.h"
#import "CactusLLMMessage.h"

@interface CactusContextManager ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *tokenCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *lastCompressionCache;
@property (nonatomic, strong) dispatch_queue_t processingQueue;
@end

@implementation CactusContextStats

- (instancetype)initWithMessages:(NSArray<CactusLLMMessage *> *)messages {
    if (self = [super init]) {
        _totalMessages = messages.count;
        _userMessages = 0;
        _assistantMessages = 0;
        _systemMessages = 0;
        _totalTokens = 0;
        _compressionRatio = 1.0f;
        _lastCompressionTime = 0;
        
        for (CactusLLMMessage *message in messages) {
            if ([message.role isEqualToString:CactusLLMRoleUser]) {
                _userMessages++;
            } else if ([message.role isEqualToString:CactusLLMRoleAssistant]) {
                _assistantMessages++;
            } else if ([message.role isEqualToString:CactusLLMRoleSystem]) {
                _systemMessages++;
            }
            
            // Estimate token count (rough approximation: 1 token ≈ 4 characters)
            _totalTokens += (message.content.length / 4) + 1;
        }
    }
    return self;
}

@end

@implementation CactusContextManager

+ (instancetype)sharedManager {
    static CactusContextManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _retentionStrategy = CactusContextRetentionStrategySmartCompression;
        _compressionLevel = CactusContextCompressionLevelMedium;
        _maxContextTokens = 4096;  // Default 4K context
        _maxMessages = 100;        // Default 100 messages
        _enableSmartCompression = YES;
        _enableTokenCounting = YES;
        _enableAutoCleanup = YES;
        
        _tokenCache = [NSMutableDictionary dictionary];
        _lastCompressionCache = [NSMutableDictionary dictionary];
        _processingQueue = dispatch_queue_create("com.cactus.context.processing", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Configuration

- (void)setMaxContextTokens:(NSInteger)maxTokens {
    _maxContextTokens = MAX(512, maxTokens); // Minimum 512 tokens
}

- (void)setMaxMessages:(NSInteger)maxMessages {
    _maxMessages = MAX(10, maxMessages); // Minimum 10 messages
}

#pragma mark - Context Management

- (NSArray<CactusLLMMessage *> *)getOptimizedContextForMessages:(NSArray<CactusLLMMessage *> *)messages {
    if (!messages || messages.count == 0) {
        return @[];
    }
    
    // Check if optimization is needed
    if (![self wouldExceedTokenLimit:messages] && messages.count <= self.maxMessages) {
        return messages; // No optimization needed
    }
    
    NSMutableArray<CactusLLMMessage *> *optimizedMessages = [NSMutableArray array];
    
    // Always keep system prompt if exists
    for (CactusLLMMessage *message in messages) {
        if ([message.role isEqualToString:CactusLLMRoleSystem]) {
            [optimizedMessages addObject:message];
            break;
        }
    }
    
    // Apply retention strategy
    switch (self.retentionStrategy) {
        case CactusContextRetentionStrategyKeepAll:
            optimizedMessages = [messages mutableCopy];
            break;
            
        case CactusContextRetentionStrategySlidingWindow:
            optimizedMessages = [self applySlidingWindowStrategy:messages];
            break;
            
        case CactusContextRetentionStrategySmartCompression:
            optimizedMessages = [self applySmartCompressionStrategy:messages];
            break;
            
        case CactusContextRetentionStrategySummaryBased:
            optimizedMessages = [self applySummaryBasedStrategy:messages];
            break;
            
        case CactusContextRetentionStrategyTokenBased:
            optimizedMessages = [self applyTokenBasedStrategy:messages];
            break;
    }
    
    // Final cleanup if still exceeds limits
    if (self.enableAutoCleanup) {
        [self cleanupOldMessages:optimizedMessages];
    }
    
    // Log optimization results
    NSInteger originalTokens = [self estimateTokenCountForMessages:messages];
    NSInteger optimizedTokens = [self estimateTokenCountForMessages:optimizedMessages];
    float compressionRatio = (float)optimizedTokens / (float)originalTokens;
    
    NSLog(@"Context optimization: %ld → %ld tokens (%.1f%% compression)",
          (long)originalTokens, (long)optimizedTokens, compressionRatio * 100);
    
    return [optimizedMessages copy];
}

- (NSMutableArray<CactusLLMMessage *> *)applySlidingWindowStrategy:(NSArray<CactusLLMMessage *> *)messages {
    NSMutableArray<CactusLLMMessage *> *result = [NSMutableArray array];
    
    // Keep last N messages
    NSInteger startIndex = MAX(0, messages.count - self.maxMessages);
    for (NSInteger i = startIndex; i < messages.count; i++) {
        [result addObject:messages[i]];
    }
    
    return result;
}

- (NSMutableArray<CactusLLMMessage *> *)applySmartCompressionStrategy:(NSArray<CactusLLMMessage *> *)messages {
    NSMutableArray<CactusLLMMessage *> *result = [NSMutableArray array];
    
    // Keep system messages
    for (CactusLLMMessage *message in messages) {
        if ([message.role isEqualToString:CactusLLMRoleSystem]) {
            [result addObject:message];
            break;
        }
    }
    
    // Keep recent messages (last 20)
    NSInteger recentCount = MIN(20, messages.count);
    NSInteger startIndex = MAX(0, messages.count - recentCount);
    
    for (NSInteger i = startIndex; i < messages.count; i++) {
        CactusLLMMessage *message = messages[i];
        if (![message.role isEqualToString:CactusLLMRoleSystem]) {
            [result addObject:message];
        }
    }
    
    // Compress older messages if needed
    if (startIndex > 0) {
        NSArray<CactusLLMMessage *> *olderMessages = [messages subarrayWithRange:NSMakeRange(0, startIndex)];
        NSArray<CactusLLMMessage *> *compressedOlder = [self compressMessages:olderMessages];
        [result insertObjects:compressedOlder atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, compressedOlder.count)]];
    }
    
    return result;
}

- (NSMutableArray<CactusLLMMessage *> *)applySummaryBasedStrategy:(NSArray<CactusLLMMessage *> *)messages {
    NSMutableArray<CactusLLMMessage *> *result = [NSMutableArray array];
    
    // Keep system messages
    for (CactusLLMMessage *message in messages) {
        if ([message.role isEqualToString:CactusLLMRoleSystem]) {
            [result addObject:message];
            break;
        }
    }
    
    // Keep recent messages (last 10)
    NSInteger recentCount = MIN(10, messages.count);
    NSInteger startIndex = MAX(0, messages.count - recentCount);
    
    for (NSInteger i = startIndex; i < messages.count; i++) {
        CactusLLMMessage *message = messages[i];
        if (![message.role isEqualToString:CactusLLMRoleSystem]) {
            [result addObject:message];
        }
    }
    
    // Replace older messages with summary
    if (startIndex > 0) {
        NSArray<CactusLLMMessage *> *olderMessages = [messages subarrayWithRange:NSMakeRange(0, startIndex)];
        NSArray<CactusLLMMessage *> *summary = [self createSummaryFromMessages:olderMessages];
        [result insertObjects:summary atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, summary.count)]];
    }
    
    return result;
}

- (NSMutableArray<CactusLLMMessage *> *)applyTokenBasedStrategy:(NSArray<CactusLLMMessage *> *)messages {
    NSMutableArray<CactusLLMMessage *> *result = [NSMutableArray array];
    NSInteger currentTokens = 0;
    
    // Keep system messages first
    for (CactusLLMMessage *message in messages) {
        if ([message.role isEqualToString:CactusLLMRoleSystem]) {
            [result addObject:message];
            currentTokens += [self estimateTokenCountForText:message.content];
            break;
        }
    }
    
    // Add messages from newest to oldest until token limit
    for (NSInteger i = messages.count - 1; i >= 0; i--) {
        CactusLLMMessage *message = messages[i];
        if ([message.role isEqualToString:CactusLLMRoleSystem]) {
            continue; // Already added
        }
        
        NSInteger messageTokens = [self estimateTokenCountForText:message.content];
        if (currentTokens + messageTokens <= self.maxContextTokens) {
            [result insertObject:message atIndex:1]; // Insert after system message
            currentTokens += messageTokens;
        } else {
            break; // Token limit reached
        }
    }
    
    return result;
}

#pragma mark - Compression

- (NSArray<CactusLLMMessage *> *)compressMessages:(NSArray<CactusLLMMessage *> *)messages {
    if (self.compressionLevel == CactusContextCompressionLevelNone) {
        return messages;
    }
    
    NSMutableArray<CactusLLMMessage *> *compressed = [NSMutableArray array];
    
    // Group messages by role and compress
    NSMutableArray<CactusLLMMessage *> *userMessages = [NSMutableArray array];
    NSMutableArray<CactusLLMMessage *> *assistantMessages = [NSMutableArray array];
    
    for (CactusLLMMessage *message in messages) {
        if ([message.role isEqualToString:CactusLLMRoleUser]) {
            [userMessages addObject:message];
        } else if ([message.role isEqualToString:CactusLLMRoleAssistant]) {
            [assistantMessages addObject:message];
        }
    }
    
    // Compress user messages
    if (userMessages.count > 0) {
        NSString *compressedUserContent = [self compressUserMessages:userMessages];
        CactusLLMMessage *compressedUser = [CactusLLMMessage messageWithRole:CactusLLMRoleUser
                                                                     content:compressedUserContent];
        [compressed addObject:compressedUser];
    }
    
    // Compress assistant messages
    if (assistantMessages.count > 0) {
        NSString *compressedAssistantContent = [self compressAssistantMessages:assistantMessages];
        CactusLLMMessage *compressedAssistant = [CactusLLMMessage messageWithRole:CactusLLMRoleAssistant
                                                                          content:compressedAssistantContent];
        [compressed addObject:compressedAssistant];
    }
    
    return [compressed copy];
}

- (NSString *)compressUserMessages:(NSArray<CactusLLMMessage *> *)messages {
    if (messages.count == 1) {
        return messages.firstObject.content;
    }
    
    NSMutableString *compressed = [NSMutableString string];
    
    switch (self.compressionLevel) {
        case CactusContextCompressionLevelLight:
            // Keep key points, remove redundant content
            for (CactusLLMMessage *message in messages) {
                NSString *content = message.content;
                if (content.length > 100) {
                    content = [content substringToIndex:100];
                    content = [content stringByAppendingString:@"..."];
                }
                [compressed appendFormat:@"%@\n", content];
            }
            break;
            
        case CactusContextCompressionLevelMedium:
            // Summarize main points
            [compressed appendString:@"Previous user inputs:\n"];
            for (NSInteger i = 0; i < messages.count; i++) {
                CactusLLMMessage *message = messages[i];
                NSString *content = message.content;
                if (content.length > 50) {
                    content = [content substringToIndex:50];
                    content = [content stringByAppendingString:@"..."];
                }
                [compressed appendFormat:@"%ld. %@\n", (long)(i + 1), content];
            }
            break;
            
        case CactusContextCompressionLevelHeavy:
            // Keep only essential information
            [compressed appendString:@"User asked multiple questions about: "];
            NSMutableArray<NSString *> *topics = [NSMutableArray array];
            for (CactusLLMMessage *message in messages) {
                NSString *content = message.content;
                if (content.length > 20) {
                    content = [content substringToIndex:20];
                    [topics addObject:content];
                }
            }
            [compressed appendString:[topics componentsJoinedByString:@", "]];
            break;
//            
//        default:
//            break;
    }
    
    return [compressed copy];
}

- (NSString *)compressAssistantMessages:(NSArray<CactusLLMMessage *> *)messages {
    if (messages.count == 1) {
        return messages.firstObject.content;
    }
    
    NSMutableString *compressed = [NSMutableString string];
    
    switch (self.compressionLevel) {
        case CactusContextCompressionLevelLight:
            // Keep key responses
            for (CactusLLMMessage *message in messages) {
                NSString *content = message.content;
                if (content.length > 150) {
                    content = [content substringToIndex:150];
                    content = [content stringByAppendingString:@"..."];
                }
                [compressed appendFormat:@"%@\n", content];
            }
            break;
            
        case CactusContextCompressionLevelMedium:
            // Summarize responses
            [compressed appendString:@"Previous assistant responses covered:\n"];
            for (NSInteger i = 0; i < messages.count; i++) {
                CactusLLMMessage *message = messages[i];
                NSString *content = message.content;
                if (content.length > 80) {
                    content = [content substringToIndex:80];
                    content = [content stringByAppendingString:@"..."];
                }
                [compressed appendFormat:@"%ld. %@\n", (long)(i + 1), content];
            }
            break;
            
        case CactusContextCompressionLevelHeavy:
            // Keep only main topics
            [compressed appendString:@"Assistant provided information about: "];
            NSMutableArray<NSString *> *topics = [NSMutableArray array];
            for (CactusLLMMessage *message in messages) {
                NSString *content = message.content;
                if (content.length > 30) {
                    content = [content substringToIndex:30];
                    [topics addObject:content];
                }
            }
            [compressed appendString:[topics componentsJoinedByString:@", "]];
            break;
            
//        default:
//            break;
    }
    
    return [compressed copy];
}

#pragma mark - Summary Creation

- (NSArray<CactusLLMMessage *> *)createSummaryFromMessages:(NSArray<CactusLLMMessage *> *)messages {
    if (messages.count == 0) {
        return @[];
    }
    
    // Create a summary message
    NSString *summaryContent = [NSString stringWithFormat:@"[Previous conversation summary: %ld messages exchanged covering various topics. Context maintained for continuity.]", (long)messages.count];
    
    CactusLLMMessage *summaryMessage = [CactusLLMMessage messageWithRole:CactusLLMRoleSystem
                                                                 content:summaryContent];
    
    return @[summaryMessage];
}

#pragma mark - Token Management

- (NSInteger)estimateTokenCountForMessages:(NSArray<CactusLLMMessage *> *)messages {
    NSInteger totalTokens = 0;
    
    for (CactusLLMMessage *message in messages) {
        totalTokens += [self estimateTokenCountForText:message.content];
        totalTokens += 4; // Account for role and formatting tokens
    }
    
    return totalTokens;
}

- (NSInteger)estimateTokenCountForText:(NSString *)text {
    if (!text || text.length == 0) {
        return 0;
    }
    
    // Check cache first
    NSString *cacheKey = [NSString stringWithFormat:@"%ld", (long)text.length];
    NSNumber *cachedTokens = self.tokenCache[cacheKey];
    if (cachedTokens) {
        return cachedTokens.integerValue;
    }
    
    // Rough estimation: 1 token ≈ 4 characters (English text)
    // This is a simplified approach; real tokenization would be more complex
    NSInteger estimatedTokens = (text.length / 4) + 1;
    
    // Cache the result
    self.tokenCache[cacheKey] = @(estimatedTokens);
    
    return estimatedTokens;
}

- (BOOL)wouldExceedTokenLimit:(NSArray<CactusLLMMessage *> *)messages {
    if (!self.enableTokenCounting) {
        return NO;
    }
    
    NSInteger estimatedTokens = [self estimateTokenCountForMessages:messages];
    return estimatedTokens > self.maxContextTokens;
}

#pragma mark - Cleanup

- (void)cleanupOldMessages:(NSMutableArray<CactusLLMMessage *> *)messages {
    if (messages.count <= self.maxMessages) {
        return;
    }
    
    // Remove oldest messages while keeping system messages
    NSMutableArray<CactusLLMMessage *> *systemMessages = [NSMutableArray array];
    NSMutableArray<CactusLLMMessage *> *otherMessages = [NSMutableArray array];
    
    for (CactusLLMMessage *message in messages) {
        if ([message.role isEqualToString:CactusLLMRoleSystem]) {
            [systemMessages addObject:message];
        } else {
            [otherMessages addObject:message];
        }
    }
    
    // Keep only recent non-system messages
    if (otherMessages.count > self.maxMessages) {
        NSInteger removeCount = otherMessages.count - self.maxMessages;
        [otherMessages removeObjectsInRange:NSMakeRange(0, removeCount)];
    }
    
    // Reconstruct messages array
    [messages removeAllObjects];
    [messages addObjectsFromArray:systemMessages];
    [messages addObjectsFromArray:otherMessages];
}

#pragma mark - Statistics

- (CactusContextStats *)getContextStatsForMessages:(NSArray<CactusLLMMessage *> *)messages {
    return [[CactusContextStats alloc] initWithMessages:messages];
}

- (void)resetStatistics {
    [self.tokenCache removeAllObjects];
    [self.lastCompressionCache removeAllObjects];
}

#pragma mark - Utility Methods

- (NSArray<CactusLLMMessage *> *)prioritizeMessages:(NSArray<CactusLLMMessage *> *)messages {
    // Sort by importance: system > recent > user > assistant
    return [messages sortedArrayUsingComparator:^NSComparisonResult(CactusLLMMessage *msg1, CactusLLMMessage *msg2) {
        // System messages first
        if ([msg1.role isEqualToString:CactusLLMRoleSystem] && ![msg2.role isEqualToString:CactusLLMRoleSystem]) {
            return NSOrderedAscending;
        }
        if (![msg1.role isEqualToString:CactusLLMRoleSystem] && [msg2.role isEqualToString:CactusLLMRoleSystem]) {
            return NSOrderedDescending;
        }
        
        // User messages before assistant messages
        if ([msg1.role isEqualToString:CactusLLMRoleUser] && [msg2.role isEqualToString:CactusLLMRoleAssistant]) {
            return NSOrderedAscending;
        }
        if ([msg1.role isEqualToString:CactusLLMRoleAssistant] && [msg2.role isEqualToString:CactusLLMRoleUser]) {
            return NSOrderedDescending;
        }
        
        return NSOrderedSame;
    }];
}

- (NSArray<CactusLLMMessage *> *)filterMessagesByImportance:(NSArray<CactusLLMMessage *> *)messages {
    NSMutableArray<CactusLLMMessage *> *importantMessages = [NSMutableArray array];
    
    for (CactusLLMMessage *message in messages) {
        if ([self isMessageImportant:message]) {
            [importantMessages addObject:message];
        }
    }
    
    return [importantMessages copy];
}

- (BOOL)isMessageImportant:(CactusLLMMessage *)message {
    // System messages are always important
    if ([message.role isEqualToString:CactusLLMRoleSystem]) {
        return YES;
    }
    
    // Messages with specific keywords are important
    NSString *content = message.content.lowercaseString;
    NSArray<NSString *> *importantKeywords = @[@"important", @"key", @"critical", @"essential", @"remember", @"note"];
    
    for (NSString *keyword in importantKeywords) {
        if ([content containsString:keyword]) {
            return YES;
        }
    }
    
    // Long messages might contain important information
    if (message.content.length > 200) {
        return YES;
    }
    
    return NO;
}

@end
