//
//  CactusSessionManager.h
//  CactusFramework
//
//  Advanced session management with streaming and background processing
//

#import <Foundation/Foundation.h>
#import "CactusModelConfiguration.h"
#import "CactusBackgroundProcessor.h"
#import "CactusLLMMessage.h"
#import "CactusLLMTools.h"
#import "CactusContextManager.h"

NS_ASSUME_NONNULL_BEGIN

// Forward declarations
@class CactusSessionManager;
@class CactusSession;

// Session types
typedef NS_ENUM(NSInteger, CactusSessionType) {
    CactusSessionTypeChat = 0,
    CactusSessionTypeCompletion = 1,
    CactusSessionTypeEmbedding = 2,
    CactusSessionTypeMultimodal = 3
};

// Session states
typedef NS_ENUM(NSInteger, CactusSessionState) {
    CactusSessionStateIdle = 0,
    CactusSessionStateGenerating = 1,
    CactusSessionStatePaused = 2,
    CactusSessionStateStopped = 3,
    CactusSessionStateError = 4
};

// Generation events
typedef NS_ENUM(NSInteger, CactusGenerationEvent) {
    CactusGenerationEventStarted = 0,
    CactusGenerationEventToken = 1,
    CactusGenerationEventProgress = 2,
    CactusGenerationEventCompleted = 3,
    CactusGenerationEventStopped = 4,
    CactusGenerationEventError = 5
};

// MARK: - Generation Result

@interface CactusGenerationResult : NSObject

@property (nonatomic, readonly) NSString *text;
@property (nonatomic, readonly) NSInteger tokensGenerated;
@property (nonatomic, readonly) NSInteger promptTokens;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) float tokensPerSecond;
@property (nonatomic, readonly, nullable) NSDictionary *metadata;
@property (nonatomic, readonly, nullable) NSArray<NSDictionary *> *tokenProbabilities;

+ (instancetype)resultWithText:(NSString *)text
               tokensGenerated:(NSInteger)tokensGenerated
                  promptTokens:(NSInteger)promptTokens
                      duration:(NSTimeInterval)duration
                      metadata:(nullable NSDictionary *)metadata;

@end

// MARK: - Session Delegate

@protocol CactusSessionDelegate <NSObject>
@optional
- (void)session:(CactusSession *)session didChangeState:(CactusSessionState)state;
- (void)session:(CactusSession *)session didReceiveEvent:(CactusGenerationEvent)event data:(nullable id)data;
- (void)session:(CactusSession *)session didGenerateToken:(NSString *)token;
- (void)session:(CactusSession *)session didUpdateProgress:(float)progress;
- (void)session:(CactusSession *)session didCompleteWithResult:(CactusGenerationResult *)result;
- (void)session:(CactusSession *)session didFailWithError:(NSError *)error;
- (void)session:(CactusSession *)session didDetectToolCall:(NSDictionary *)toolCall;
@end

// MARK: - Session

@interface CactusSession : NSObject

@property (nonatomic, readonly) NSUUID *sessionId;
@property (nonatomic, readonly) CactusSessionType type;
@property (nonatomic, readonly) CactusSessionState state;
@property (nonatomic, readonly) NSDate *createdAt;
@property (nonatomic, readonly, nullable) NSDate *lastActiveAt;
@property (nonatomic, weak, nullable) id<CactusSessionDelegate> delegate;

// Configuration
@property (nonatomic, strong, nullable) CactusGenerationConfiguration *generationConfig;
@property (nonatomic, copy, nullable) NSString *systemPrompt;
@property (nonatomic, copy, nullable) NSArray<CactusLLMTools *> *tools;

// Chat history (for chat sessions)
@property (nonatomic, readonly) NSArray<CactusLLMMessage *> *messages;

// Smart context management
@property (nonatomic, strong, nullable) CactusContextManager *contextManager;
@property (nonatomic, assign) BOOL enableSmartContextManagement;
@property (nonatomic, assign) NSInteger maxContextTokens;

// Statistics
@property (nonatomic, readonly) NSInteger totalTokensGenerated;
@property (nonatomic, readonly) NSInteger totalPromptTokens;
@property (nonatomic, readonly) NSTimeInterval totalGenerationTime;

// Factory methods
+ (instancetype)chatSessionWithId:(nullable NSUUID *)sessionId;
+ (instancetype)completionSessionWithId:(nullable NSUUID *)sessionId;
+ (instancetype)embeddingSessionWithId:(nullable NSUUID *)sessionId;
+ (instancetype)multimodalSessionWithId:(nullable NSUUID *)sessionId;

// Session control
- (void)reset;
- (void)pause;
- (void)resume;
- (void)stop;

// Chat methods
- (void)addMessage:(CactusLLMMessage *)message;
- (void)addMessages:(NSArray<CactusLLMMessage *> *)messages;
- (void)clearHistory;
- (void)removeLastMessage;
- (void)removeMessageAtIndex:(NSUInteger)index;

// Conversation management
- (NSArray<CactusLLMMessage *> *)getConversationHistory;
- (NSArray<CactusLLMMessage *> *)getUserMessages;
- (NSArray<CactusLLMMessage *> *)getAssistantMessages;
- (void)validateConversationIntegrity;
- (BOOL)hasValidConversationFlow;

// Smart context management methods
- (void)setMaxContextTokens:(NSInteger)maxTokens;
- (void)enableSmartContextManagement:(BOOL)enable;
- (void)setContextRetentionStrategy:(CactusContextRetentionStrategy)strategy;
- (void)setContextCompressionLevel:(CactusContextCompressionLevel)level;
- (NSArray<CactusLLMMessage *> *)getOptimizedConversationHistory;
- (void)compressConversationHistory;
- (void)clearOldMessages:(NSInteger)keepLastCount;
- (CactusContextStats *)getContextStatistics;

// Generation methods
- (NSUUID *)generateResponseWithCompletionHandler:(void(^)(CactusGenerationResult * _Nullable result, NSError * _Nullable error))completionHandler;

- (NSUUID *)generateResponseWithProgressHandler:(nullable void(^)(float progress))progressHandler
                                   tokenHandler:(nullable void(^)(NSString *token))tokenHandler
                              completionHandler:(void(^)(CactusGenerationResult * _Nullable result, NSError * _Nullable error))completionHandler;

- (NSUUID *)generateCompletionForPrompt:(NSString *)prompt
                      completionHandler:(void(^)(CactusGenerationResult * _Nullable result, NSError * _Nullable error))completionHandler;

- (NSUUID *)generateEmbeddingForText:(NSString *)text
                   completionHandler:(void(^)(NSArray<NSNumber *> * _Nullable embedding, NSError * _Nullable error))completionHandler;

- (NSUUID *)generateMultimodalResponseWithPrompt:(NSString *)prompt
                                      mediaPaths:(NSArray<NSString *> *)mediaPaths
                               completionHandler:(void(^)(CactusGenerationResult * _Nullable result, NSError * _Nullable error))completionHandler;

// Task control
- (void)cancelGeneration:(NSUUID *)generationId;
- (void)cancelAllGenerations;

@end

// MARK: - Session Manager

@protocol CactusSessionManagerDelegate <NSObject>
@optional
- (void)sessionManager:(CactusSessionManager *)manager didCreateSession:(CactusSession *)session;
- (void)sessionManager:(CactusSessionManager *)manager didDestroySession:(CactusSession *)session;
- (void)sessionManager:(CactusSessionManager *)manager session:(CactusSession *)session didChangeState:(CactusSessionState)state;
@end

@interface CactusSessionManager : NSObject

@property (nonatomic, weak, nullable) id<CactusSessionManagerDelegate> delegate;
@property (nonatomic, readonly) NSArray<CactusSession *> *activeSessions;
@property (nonatomic, readonly) NSInteger maxConcurrentSessions;

// Singleton
+ (instancetype)sharedManager;

// Configuration
- (void)setMaxConcurrentSessions:(NSInteger)maxSessions;

// Session management
- (CactusSession *)createSessionWithType:(CactusSessionType)type;
- (CactusSession *)createSessionWithType:(CactusSessionType)type sessionId:(NSUUID *)sessionId;
- (nullable CactusSession *)sessionWithId:(NSUUID *)sessionId;
- (void)destroySession:(NSUUID *)sessionId;
- (void)destroyAllSessions;

// Session queries
- (NSArray<CactusSession *> *)sessionsWithType:(CactusSessionType)type;
- (NSArray<CactusSession *> *)sessionsWithState:(CactusSessionState)state;
- (NSArray<CactusSession *> *)activeChatSessions;

// Bulk operations
- (void)pauseAllSessions;
- (void)resumeAllSessions;
- (void)stopAllSessions;

// Statistics
- (NSDictionary *)sessionStatistics;

@end

// MARK: - Session Manager Extensions

@interface CactusSessionManager (Convenience)

// Quick session creation with configuration
- (CactusSession *)createChatSessionWithSystemPrompt:(nullable NSString *)systemPrompt
                                    generationConfig:(nullable CactusGenerationConfiguration *)config;

- (CactusSession *)createCompletionSessionWithGenerationConfig:(nullable CactusGenerationConfiguration *)config;

// Session templates
- (CactusSession *)createQuickChatSession;
- (CactusSession *)createCreativeChatSession;
- (CactusSession *)createPreciseChatSession;

@end

// MARK: - Notifications

extern NSNotificationName const CactusSessionDidChangeStateNotification;
extern NSNotificationName const CactusSessionDidGenerateTokenNotification;
extern NSNotificationName const CactusSessionDidCompleteGenerationNotification;
extern NSNotificationName const CactusSessionDidFailGenerationNotification;

// Notification userInfo keys
extern NSString * const CactusSessionIdKey;
extern NSString * const CactusSessionStateKey;
extern NSString * const CactusSessionTokenKey;
extern NSString * const CactusSessionResultKey;
extern NSString * const CactusSessionErrorKey;
extern NSString * const CactusSessionProgressKey;

NS_ASSUME_NONNULL_END
