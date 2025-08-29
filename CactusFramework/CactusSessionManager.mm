//
//  CactusSessionManager.mm
//  CactusFramework
//

#import "CactusSessionManager.h"
#import "CactusModelManager.h"
#import "CactusLLMError.h"
#import "cactus/cactus.h"
#import "cactus/common.h"
#import <mutex>

// Notification names
NSNotificationName const CactusSessionDidChangeStateNotification = @"CactusSessionDidChangeStateNotification";
NSNotificationName const CactusSessionDidGenerateTokenNotification = @"CactusSessionDidGenerateTokenNotification";
NSNotificationName const CactusSessionDidCompleteGenerationNotification = @"CactusSessionDidCompleteGenerationNotification";
NSNotificationName const CactusSessionDidFailGenerationNotification = @"CactusSessionDidFailGenerationNotification";

// Notification keys
NSString * const CactusSessionIdKey = @"sessionId";
NSString * const CactusSessionStateKey = @"state";
NSString * const CactusSessionTokenKey = @"token";
NSString * const CactusSessionResultKey = @"result";
NSString * const CactusSessionErrorKey = @"error";
NSString * const CactusSessionProgressKey = @"progress";

#pragma mark - Generation Result Implementation

@implementation CactusGenerationResult

- (instancetype)initWithText:(NSString *)text
             tokensGenerated:(NSInteger)tokensGenerated
                promptTokens:(NSInteger)promptTokens
                    duration:(NSTimeInterval)duration
                    metadata:(NSDictionary *)metadata {
    if (self = [super init]) {
        _text = [text copy];
        _tokensGenerated = tokensGenerated;
        _promptTokens = promptTokens;
        _duration = duration;
        _metadata = [metadata copy];
        _tokensPerSecond = duration > 0 ? (float)tokensGenerated / duration : 0.0f;
    }
    return self;
}

+ (instancetype)resultWithText:(NSString *)text
               tokensGenerated:(NSInteger)tokensGenerated
                  promptTokens:(NSInteger)promptTokens
                      duration:(NSTimeInterval)duration
                      metadata:(NSDictionary *)metadata {
    return [[self alloc] initWithText:text
                      tokensGenerated:tokensGenerated
                         promptTokens:promptTokens
                             duration:duration
                             metadata:metadata];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<CactusGenerationResult: tokens=%ld, duration=%.2fs, speed=%.1f t/s>",
            (long)self.tokensGenerated, self.duration, self.tokensPerSecond];
}

@end

#pragma mark - Session Implementation

@interface CactusSession ()
@property (nonatomic, readwrite) CactusSessionState state;
@property (nonatomic, readwrite) NSDate *lastActiveAt;
@property (nonatomic, strong) NSMutableArray<CactusLLMMessage *> *mutableMessages;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, CactusTask *> *activeTasks;
@property (nonatomic, strong) dispatch_queue_t synchronizationQueue;
@property (nonatomic, readwrite) NSInteger totalTokensGenerated;
@property (nonatomic, readwrite) NSInteger totalPromptTokens;
@property (nonatomic, readwrite) NSTimeInterval totalGenerationTime;

@end

@implementation CactusSession

- (instancetype)initWithType:(CactusSessionType)type sessionId:(NSUUID *)sessionId {
    if (self = [super init]) {
        _sessionId = sessionId ?: [NSUUID UUID];
        _type = type;
        _state = CactusSessionStateIdle;
        _createdAt = [NSDate date];
        _mutableMessages = [NSMutableArray array];
        _activeTasks = [NSMutableDictionary dictionary];
        _synchronizationQueue = dispatch_queue_create("com.cactus.session", DISPATCH_QUEUE_CONCURRENT);
        
        // Initialize context manager
        _contextManager = [CactusContextManager sharedManager];
        _enableSmartContextManagement = YES;
        _maxContextTokens = 4096; // Default 4K context
    }
    return self;
}

+ (instancetype)chatSessionWithId:(NSUUID *)sessionId {
    return [[self alloc] initWithType:CactusSessionTypeChat sessionId:sessionId];
}

+ (instancetype)completionSessionWithId:(NSUUID *)sessionId {
    return [[self alloc] initWithType:CactusSessionTypeCompletion sessionId:sessionId];
}

+ (instancetype)embeddingSessionWithId:(NSUUID *)sessionId {
    return [[self alloc] initWithType:CactusSessionTypeEmbedding sessionId:sessionId];
}

+ (instancetype)multimodalSessionWithId:(NSUUID *)sessionId {
    return [[self alloc] initWithType:CactusSessionTypeMultimodal sessionId:sessionId];
}

- (NSArray<CactusLLMMessage *> *)messages {
    __block NSArray<CactusLLMMessage *> *messages = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        messages = [self.mutableMessages copy];
    });
    return messages;
}

- (void)setState:(CactusSessionState)state {
    dispatch_barrier_async(self.synchronizationQueue, ^{
        if (self->_state != state) {
            self->_state = state;
            self.lastActiveAt = [NSDate date];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(session:didChangeState:)]) {
                    [self.delegate session:self didChangeState:state];
                }
                
                [[NSNotificationCenter defaultCenter] postNotificationName:CactusSessionDidChangeStateNotification
                                                                    object:self
                                                                  userInfo:@{
                                                                      CactusSessionIdKey: self.sessionId,
                                                                      CactusSessionStateKey: @(state)
                                                                  }];
            });
        }
    });
}

- (void)reset {
    dispatch_barrier_async(self.synchronizationQueue, ^{
        [self cancelAllGenerations];
        [self.mutableMessages removeAllObjects];
        self.totalTokensGenerated = 0;
        self.totalPromptTokens = 0;
        self.totalGenerationTime = 0;
        self.state = CactusSessionStateIdle;
    });
}

- (void)pause {
    if (self.state == CactusSessionStateGenerating) {
        self.state = CactusSessionStatePaused;
        // Pause active tasks
        dispatch_sync(self.synchronizationQueue, ^{
            for (CactusTask *task in self.activeTasks.allValues) {
                // Tasks don't have pause functionality, but we can mark the session as paused
            }
        });
    }
}

- (void)resume {
    if (self.state == CactusSessionStatePaused) {
        self.state = CactusSessionStateGenerating;
        // Resume would need to be implemented based on task state
    }
}

- (void)stop {
    [self cancelAllGenerations];
    self.state = CactusSessionStateStopped;
}

- (void)addMessage:(CactusLLMMessage *)message {
    dispatch_barrier_async(self.synchronizationQueue, ^{
        [self.mutableMessages addObject:message];
        self.lastActiveAt = [NSDate date];
    });
}

- (void)addMessages:(NSArray<CactusLLMMessage *> *)messages {
    dispatch_barrier_async(self.synchronizationQueue, ^{
        [self.mutableMessages addObjectsFromArray:messages];
        self.lastActiveAt = [NSDate date];
    });
}

- (void)clearHistory {
    dispatch_barrier_async(self.synchronizationQueue, ^{
        [self.mutableMessages removeAllObjects];
        self.lastActiveAt = [NSDate date];
    });
}

- (void)removeLastMessage {
    dispatch_barrier_async(self.synchronizationQueue, ^{
        if (self.mutableMessages.count > 0) {
            [self.mutableMessages removeLastObject];
            self.lastActiveAt = [NSDate date];
        }
    });
}

- (void)removeMessageAtIndex:(NSUInteger)index {
    dispatch_barrier_async(self.synchronizationQueue, ^{
        if (index < self.mutableMessages.count) {
            [self.mutableMessages removeObjectAtIndex:index];
            self.lastActiveAt = [NSDate date];
        }
    });
}

- (NSUUID *)generateResponseWithCompletionHandler:(void(^)(CactusGenerationResult * _Nullable result, NSError * _Nullable error))completionHandler {
    return [self generateResponseWithProgressHandler:nil
                                         tokenHandler:nil
                                    completionHandler:completionHandler];
}

- (NSUUID *)generateResponseWithProgressHandler:(void(^)(float progress))progressHandler
                                   tokenHandler:(void(^)(NSString *token))tokenHandler
                              completionHandler:(void(^)(CactusGenerationResult * _Nullable result, NSError * _Nullable error))completionHandler {
    
    if (self.state == CactusSessionStateGenerating) {
        NSError *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                             code:CactusLLMErrorInvalidState
                                         userInfo:@{NSLocalizedDescriptionKey: @"Session is already generating"}];
        if (completionHandler) {
            completionHandler(nil, error);
        }
        return [NSUUID UUID]; // Return dummy UUID
    }
    
    // Check if model is loaded
    if (![[CactusModelManager sharedManager] isLoaded]) {
        NSError *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                             code:CactusLLMErrorModelNotLoaded
                                         userInfo:@{NSLocalizedDescriptionKey: @"Model not loaded"}];
        if (completionHandler) {
            completionHandler(nil, error);
        }
        return [NSUUID UUID]; // Return dummy UUID
    }
    
    self.state = CactusSessionStateGenerating;
    
    __weak typeof(self) weakSelf = self;
    CactusTask *generationTask = [CactusTask taskWithType:CactusTaskTypeGeneration
                                                 priority:CactusTaskPriorityNormal
                                              description:@"Generating chat response"
                                           executionBlock:^id(CactusTask *task, CactusTaskProgressHandler progress) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;
        
        NSDate *startTime = [NSDate date];
        
        // Get context from model manager
        cactus::cactus_context *context = (cactus::cactus_context *)[[CactusModelManager sharedManager] internalContext];
        if (!context) {
            @throw [NSException exceptionWithName:@"ContextNotAvailable"
                                           reason:@"Model context not available"
                                         userInfo:nil];
        }
        
        // Use optimized conversation history instead of full history
        NSArray<CactusLLMMessage *> *optimizedMessages = strongSelf.enableSmartContextManagement ? 
            [strongSelf getOptimizedConversationHistory] : [strongSelf getConversationHistory];
        
        // Convert optimized messages to chat format
        NSMutableArray *messagesArray = [NSMutableArray array];
        
        // Add system prompt if available
        if (strongSelf.systemPrompt) {
            [messagesArray addObject:@{
                @"role": @"system",
                @"content": strongSelf.systemPrompt
            }];
        }
        
        // Add optimized conversation history
        for (CactusLLMMessage *message in optimizedMessages) {
            if (message.role != CactusLLMRoleSystem) {
                [messagesArray addObject:@{
                    @"role": message.role,
                    @"content": message.content
                }];
            }
            else {
                [messagesArray addObject:@{
                    @"role": message.role,
                    @"content": message.content,
//                    @"tools": message.tools
                }];
            }
        }
        
        // Log optimization results
        if (strongSelf.enableSmartContextManagement) {
            NSInteger originalCount = [strongSelf getConversationHistory].count;
            NSInteger optimizedCount = optimizedMessages.count;
            if (originalCount != optimizedCount) {
                NSLog(@"Context optimization: %ld → %ld messages (%.1f%% reduction)", 
                      (long)originalCount, (long)optimizedCount, 
                      (float)(originalCount - optimizedCount) / (float)originalCount * 100);
            }
        }
        
        // Convert to JSON
        NSError *jsonError = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:messagesArray
                                                           options:0
                                                             error:&jsonError];
        if (jsonError) {
            @throw [NSException exceptionWithName:@"JSONSerializationError"
                                           reason:jsonError.localizedDescription
                                         userInfo:@{@"error": jsonError}];
        }
        
        NSString *messagesJSON = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        
        // Format chat using context
        std::string formattedPrompt = context->getFormattedChat(messagesJSON.UTF8String, "");
        
        // Apply generation configuration
        if (strongSelf.generationConfig) {
            context->params.sampling.seed = (int32_t)strongSelf.generationConfig.seed;
            context->params.sampling.temp = strongSelf.generationConfig.temperature;
            context->params.sampling.top_k = (int32_t)strongSelf.generationConfig.topK;
            context->params.sampling.top_p = strongSelf.generationConfig.topP;
            context->params.sampling.min_p = strongSelf.generationConfig.minP;
//            context->params.sampling.typical_p = strongSelf.generationConfig.typicalP;
            context->params.sampling.penalty_last_n = (int32_t)strongSelf.generationConfig.penaltyLastN;
            context->params.sampling.penalty_repeat = strongSelf.generationConfig.penaltyRepeat;
            context->params.sampling.penalty_freq = strongSelf.generationConfig.penaltyFreq;
            context->params.sampling.penalty_present = strongSelf.generationConfig.penaltyPresent;
            context->params.sampling.mirostat = (int32_t)strongSelf.generationConfig.mirostat;
            context->params.sampling.mirostat_tau = strongSelf.generationConfig.mirostatTau;
            context->params.sampling.mirostat_eta = strongSelf.generationConfig.mirostatEta;
            
            if (strongSelf.generationConfig.maxTokens > 0) {
                context->params.n_predict = (int32_t)strongSelf.generationConfig.maxTokens;
            }
            
            // Set stop sequences (filtered to remove empty/invalid ones)
            context->params.antiprompt.clear();
            NSArray<NSString *> *filteredStopSeqs = [strongSelf.generationConfig filteredStopSequences];
            for (NSString *stopSeq in filteredStopSeqs) {
                context->params.antiprompt.push_back(stopSeq.UTF8String);
                NSLog(@"Added stop sequence: '%@'", stopSeq);
            }
            
            // Set grammar if provided
            if (strongSelf.generationConfig.grammar) {
                context->params.sampling.grammar = strongSelf.generationConfig.grammar.UTF8String;
            }
        }
        
        // Set prompt and initialize
        context->params.prompt = formattedPrompt;
        
        if (!context->initSampling()) {
            @throw [NSException exceptionWithName:@"SamplingInitError"
                                           reason:@"Failed to initialize sampling"
                                         userInfo:nil];
        }
        
        context->rewind();
        context->beginCompletion();
        context->loadPrompt();
        
        progress(0.1f);
        
        // Generate tokens
        NSMutableString *generatedText = [NSMutableString string];
        NSInteger tokensGenerated = 0;
        NSInteger promptTokens = context->num_prompt_tokens;
        
        while (context->has_next_token && !context->is_interrupted && !task.isCancelled) {
            auto token_data = context->doCompletion();
            
            if (token_data.tok == -1) {
                break;
            }
            
            tokensGenerated++;
            
            // Get new text
            if (context->generated_text.length() > generatedText.length) {
                NSString *newText = @(context->generated_text.c_str());
                NSString *newToken = [newText substringFromIndex:generatedText.length];
                [generatedText appendString:newToken];
                
                // Check for stop sequences using utility method
                if ([strongSelf.generationConfig containsStopSequence:generatedText]) {
                    NSString *detectedStopSeq = [strongSelf.generationConfig detectedStopSequence:generatedText];
                    NSLog(@"Stop sequence detected: '%@'", detectedStopSeq);
                    NSLog(@"Generation stopped due to stop sequence");
                    break;
                }
                
                // Notify token handler
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (tokenHandler) {
                        tokenHandler(newToken);
                    }
                    
                    if ([strongSelf.delegate respondsToSelector:@selector(session:didGenerateToken:)]) {
                        [strongSelf.delegate session:strongSelf didGenerateToken:newToken];
                    }
                    
                    [[NSNotificationCenter defaultCenter] postNotificationName:CactusSessionDidGenerateTokenNotification
                                                                        object:strongSelf
                                                                      userInfo:@{
                                                                          CactusSessionIdKey: strongSelf.sessionId,
                                                                          CactusSessionTokenKey: newToken
                                                                      }];
                });
            }
            
            // Update progress
            if (strongSelf.generationConfig && strongSelf.generationConfig.maxTokens > 0) {
                float progressValue = 0.1f + 0.8f * ((float)tokensGenerated / strongSelf.generationConfig.maxTokens);
                progress(MIN(progressValue, 0.9f));
            }
        }
        
        progress(1.0f);
        
        NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:startTime];
        
        // Create result
        CactusGenerationResult *result = [CactusGenerationResult resultWithText:[generatedText copy]
                                                                tokensGenerated:tokensGenerated
                                                                   promptTokens:promptTokens
                                                                       duration:duration
                                                                       metadata:@{
                                                                           @"sessionId": strongSelf.sessionId.UUIDString,
                                                                           @"sessionType": @(strongSelf.type)
                                                                       }];
        
        return result;
    }];
    
    // Set task callbacks
    generationTask.progressHandler = ^(float progress) {
        if (progressHandler) {
            progressHandler(progress);
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([weakSelf.delegate respondsToSelector:@selector(session:didUpdateProgress:)]) {
                [weakSelf.delegate session:weakSelf didUpdateProgress:progress];
            }
        });
    };
    
    NSUUID *taskId = generationTask.taskId;
    generationTask.completionHandler = ^(id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        dispatch_barrier_async(strongSelf.synchronizationQueue, ^{
            [strongSelf.activeTasks removeObjectForKey:taskId];
        });
        
        if (error) {
            strongSelf.state = CactusSessionStateError;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([strongSelf.delegate respondsToSelector:@selector(session:didFailWithError:)]) {
                    [strongSelf.delegate session:strongSelf didFailWithError:error];
                }
                
                [[NSNotificationCenter defaultCenter] postNotificationName:CactusSessionDidFailGenerationNotification
                                                                    object:strongSelf
                                                                  userInfo:@{
                                                                      CactusSessionIdKey: strongSelf.sessionId,
                                                                      CactusSessionErrorKey: error
                                                                  }];
            });
            
            if (completionHandler) {
                completionHandler(nil, error);
            }
        } else {
            CactusGenerationResult *generationResult = (CactusGenerationResult *)result;
            
            // Update statistics
            strongSelf.totalTokensGenerated += generationResult.tokensGenerated;
            strongSelf.totalPromptTokens += generationResult.promptTokens;
            strongSelf.totalGenerationTime += generationResult.duration;
            
            // Add assistant message to history
            if (strongSelf.type == CactusSessionTypeChat) {
                CactusLLMMessage *assistantMessage = [CactusLLMMessage messageWithRole:CactusLLMRoleAssistant content:generationResult.text];
                [strongSelf addMessage:assistantMessage];
            }
            
            strongSelf.state = CactusSessionStateIdle;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([strongSelf.delegate respondsToSelector:@selector(session:didCompleteWithResult:)]) {
                    [strongSelf.delegate session:strongSelf didCompleteWithResult:generationResult];
                }
                
                [[NSNotificationCenter defaultCenter] postNotificationName:CactusSessionDidCompleteGenerationNotification
                                                                    object:strongSelf
                                                                  userInfo:@{
                                                                      CactusSessionIdKey: strongSelf.sessionId,
                                                                      CactusSessionResultKey: generationResult
                                                                  }];
            });
            
            if (completionHandler) {
                completionHandler(generationResult, nil);
            }
        }
    };
    
    // Store and submit task
    dispatch_barrier_async(self.synchronizationQueue, ^{
        self.activeTasks[generationTask.taskId] = generationTask;
    });
    
    [[CactusBackgroundProcessor sharedProcessor] submitTask:generationTask];
    
    return generationTask.taskId;
}

- (NSUUID *)generateCompletionForPrompt:(NSString *)prompt
                      completionHandler:(void(^)(CactusGenerationResult * _Nullable result, NSError * _Nullable error))completionHandler {
    // Add user message for completion
    CactusLLMMessage *userMessage = [CactusLLMMessage messageWithRole:CactusLLMRoleUser content:prompt];
    [self addMessage:userMessage];
    
    return [self generateResponseWithCompletionHandler:completionHandler];
}

- (NSUUID *)generateEmbeddingForText:(NSString *)text
                   completionHandler:(void(^)(NSArray<NSNumber *> * _Nullable embedding, NSError * _Nullable error))completionHandler {
    // Implementation would use the embedding functionality
    // This is a placeholder
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completionHandler) {
                completionHandler(@[], nil);
            }
        });
    });
    
    return [NSUUID UUID];
}

- (NSUUID *)generateMultimodalResponseWithPrompt:(NSString *)prompt
                                      mediaPaths:(NSArray<NSString *> *)mediaPaths
                               completionHandler:(void(^)(CactusGenerationResult * _Nullable result, NSError * _Nullable error))completionHandler {
    // Implementation would use the multimodal functionality
    // This is a placeholder
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completionHandler) {
                CactusGenerationResult *result = [CactusGenerationResult resultWithText:@"Multimodal response placeholder"
                                                                        tokensGenerated:10
                                                                           promptTokens:5
                                                                               duration:1.0
                                                                               metadata:@{}];
                completionHandler(result, nil);
            }
        });
    });
    
    return [NSUUID UUID];
}

- (void)cancelGeneration:(NSUUID *)generationId {
    __block CactusTask *taskToCancel = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        taskToCancel = self.activeTasks[generationId];
    });
    
    if (taskToCancel) {
        [[CactusBackgroundProcessor sharedProcessor] cancelTask:generationId];
        dispatch_barrier_async(self.synchronizationQueue, ^{
            [self.activeTasks removeObjectForKey:generationId];
        });
        
        if (self.state == CactusSessionStateGenerating) {
            self.state = CactusSessionStateIdle;
        }
    }
}

- (void)cancelAllGenerations {
    __block NSArray<NSUUID *> *taskIds = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        taskIds = [self.activeTasks.allKeys copy];
    });
    
    for (NSUUID *taskId in taskIds) {
        [[CactusBackgroundProcessor sharedProcessor] cancelTask:taskId];
    }
    
    dispatch_barrier_async(self.synchronizationQueue, ^{
        [self.activeTasks removeAllObjects];
    });
    
    if (self.state == CactusSessionStateGenerating) {
        self.state = CactusSessionStateIdle;
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<CactusSession: %@ type=%ld state=%ld messages=%ld>",
            self.sessionId.UUIDString, (long)self.type, (long)self.state, (long)self.messages.count];
}

#pragma mark - Conversation Management

- (NSArray<CactusLLMMessage *> *)getConversationHistory {
    __block NSArray<CactusLLMMessage *> *history = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        history = [self.mutableMessages copy];
    });
    return history;
}

- (NSArray<CactusLLMMessage *> *)getUserMessages {
    __block NSMutableArray<CactusLLMMessage *> *userMessages = [NSMutableArray array];
    dispatch_sync(self.synchronizationQueue, ^{
        for (CactusLLMMessage *message in self.mutableMessages) {
            if ([message.role isEqualToString:CactusLLMRoleUser]) {
                [userMessages addObject:message];
            }
        }
    });
    return [userMessages copy];
}

- (NSArray<CactusLLMMessage *> *)getAssistantMessages {
    __block NSMutableArray<CactusLLMMessage *> *assistantMessages = [NSMutableArray array];
    dispatch_sync(self.synchronizationQueue, ^{
        for (CactusLLMMessage *message in self.mutableMessages) {
            if ([message.role isEqualToString:CactusLLMRoleAssistant]) {
                [assistantMessages addObject:message];
            }
        }
    });
    return [assistantMessages copy];
}

- (void)validateConversationIntegrity {
    __block NSMutableArray<NSString *> *issues = [NSMutableArray array];
    
    dispatch_sync(self.synchronizationQueue, ^{
        NSInteger userCount = 0;
        NSInteger assistantCount = 0;
        
        for (CactusLLMMessage *message in self.mutableMessages) {
            if ([message.role isEqualToString:CactusLLMRoleUser]) {
                userCount++;
            } else if ([message.role isEqualToString:CactusLLMRoleAssistant]) {
                assistantCount++;
            }
        }
        
        // Check for basic conversation flow
        if (userCount == 0) {
            [issues addObject:@"No user messages found"];
        }
        
        if (assistantCount == 0) {
            [issues addObject:@"No assistant responses found"];
        }
        
        // Check for conversation balance (user should have at least one more message than assistant)
        if (userCount <= assistantCount) {
            [issues addObject:[NSString stringWithFormat:@"Conversation imbalance: %ld user vs %ld assistant", (long)userCount, (long)assistantCount]];
        }
        
        // Check for empty content
        for (CactusLLMMessage *message in self.mutableMessages) {
            if (!message.content || message.content.length == 0) {
                [issues addObject:[NSString stringWithFormat:@"Empty content in %@ message", message.role]];
            }
        }
    });
    
    if (issues.count > 0) {
        NSLog(@"Conversation integrity issues found:");
        for (NSString *issue in issues) {
            NSLog(@"  - %@", issue);
        }
    } else {
        NSLog(@"Conversation integrity validated successfully");
    }
}

- (BOOL)hasValidConversationFlow {
    __block BOOL isValid = YES;
    
    dispatch_sync(self.synchronizationQueue, ^{
        if (self.mutableMessages.count == 0) {
            isValid = NO;
            return;
        }
        
        // Check if conversation starts with user message
        CactusLLMMessage *firstMessage = self.mutableMessages.firstObject;
        if (![firstMessage.role isEqualToString:CactusLLMRoleUser] && ![firstMessage.role isEqualToString:CactusLLMRoleSystem]) {
            isValid = NO;
            return;
        }
        
        // Check for alternating pattern (user -> assistant -> user -> assistant...)
        for (NSInteger i = 0; i < self.mutableMessages.count - 1; i++) {
            CactusLLMMessage *current = self.mutableMessages[i];
            CactusLLMMessage *next = self.mutableMessages[i + 1];
            
            // Skip system messages
            if ([current.role isEqualToString:CactusLLMRoleSystem] || [next.role isEqualToString:CactusLLMRoleSystem]) {
                continue;
            }
            
            // Check for proper alternation
            if ([current.role isEqualToString:next.role]) {
                isValid = NO;
                return;
            }
        }
    });
    
    return isValid;
}

#pragma mark - Smart Context Management

- (void)setMaxContextTokens:(NSInteger)maxTokens {
    _maxContextTokens = maxTokens;
    if (self.contextManager) {
        [self.contextManager setMaxContextTokens:maxTokens];
    }
}

- (void)enableSmartContextManagement:(BOOL)enable {
    _enableSmartContextManagement = enable;
}

- (void)setContextRetentionStrategy:(CactusContextRetentionStrategy)strategy {
    if (self.contextManager) {
        self.contextManager.retentionStrategy = strategy;
    }
}

- (void)setContextCompressionLevel:(CactusContextCompressionLevel)level {
    if (self.contextManager) {
        self.contextManager.compressionLevel = level;
    }
}

- (NSArray<CactusLLMMessage *> *)getOptimizedConversationHistory {
    if (!self.enableSmartContextManagement || !self.contextManager) {
        return [self getConversationHistory];
    }
    
    NSArray<CactusLLMMessage *> *allMessages = [self getConversationHistory];
    return [self.contextManager getOptimizedContextForMessages:allMessages];
}

- (void)compressConversationHistory {
    if (!self.enableSmartContextManagement || !self.contextManager) {
        return;
    }
    
    NSArray<CactusLLMMessage *> *allMessages = [self getConversationHistory];
    NSArray<CactusLLMMessage *> *compressed = [self.contextManager compressMessages:allMessages];
    
    // Replace messages with compressed version
    dispatch_barrier_async(self.synchronizationQueue, ^{
        [self.mutableMessages removeAllObjects];
        [self.mutableMessages addObjectsFromArray:compressed];
    });
    
    NSLog(@"Conversation history compressed: %ld → %ld messages", 
          (long)allMessages.count, (long)compressed.count);
}

- (void)clearOldMessages:(NSInteger)keepLastCount {
    dispatch_barrier_async(self.synchronizationQueue, ^{
        if (self.mutableMessages.count > keepLastCount) {
            NSInteger removeCount = self.mutableMessages.count - keepLastCount;
            [self.mutableMessages removeObjectsInRange:NSMakeRange(0, removeCount)];
            NSLog(@"Removed %ld old messages, keeping last %ld", (long)removeCount, (long)keepLastCount);
        }
    });
}

- (CactusContextStats *)getContextStatistics {
    if (!self.contextManager) {
        return nil;
    }
    
    NSArray<CactusLLMMessage *> *allMessages = [self getConversationHistory];
    return [self.contextManager getContextStatsForMessages:allMessages];
}

@end

#pragma mark - Session Manager Implementation

@interface CactusSessionManager ()
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, CactusSession *> *sessions;
@property (nonatomic, strong) dispatch_queue_t synchronizationQueue;
@property (nonatomic, readwrite) NSInteger maxConcurrentSessions;
@end

@implementation CactusSessionManager

+ (instancetype)sharedManager {
    static CactusSessionManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _sessions = [NSMutableDictionary dictionary];
        _synchronizationQueue = dispatch_queue_create("com.cactus.session.manager", DISPATCH_QUEUE_CONCURRENT);
        _maxConcurrentSessions = 5; // Default limit
    }
    return self;
}

- (NSArray<CactusSession *> *)activeSessions {
    __block NSArray<CactusSession *> *sessions = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        sessions = [self.sessions.allValues copy];
    });
    return sessions;
}

- (void)setMaxConcurrentSessions:(NSInteger)maxSessions {
    _maxConcurrentSessions = MAX(1, maxSessions);
}

- (CactusSession *)createSessionWithType:(CactusSessionType)type {
    return [self createSessionWithType:type sessionId:nil];
}

- (CactusSession *)createSessionWithType:(CactusSessionType)type sessionId:(NSUUID *)sessionId {
    // Check session limit
    if (self.activeSessions.count >= self.maxConcurrentSessions) {
        return nil;
    }
    
    CactusSession *session = nil;
    
    switch (type) {
        case CactusSessionTypeChat:
            session = [CactusSession chatSessionWithId:sessionId];
            break;
        case CactusSessionTypeCompletion:
            session = [CactusSession completionSessionWithId:sessionId];
            break;
        case CactusSessionTypeEmbedding:
            session = [CactusSession embeddingSessionWithId:sessionId];
            break;
        case CactusSessionTypeMultimodal:
            session = [CactusSession multimodalSessionWithId:sessionId];
            break;
    }
    
    if (session) {
        dispatch_barrier_async(self.synchronizationQueue, ^{
            self.sessions[session.sessionId] = session;
        });
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(sessionManager:didCreateSession:)]) {
                [self.delegate sessionManager:self didCreateSession:session];
            }
        });
    }
    
    return session;
}

- (CactusSession *)sessionWithId:(NSUUID *)sessionId {
    __block CactusSession *session = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        session = self.sessions[sessionId];
    });
    return session;
}

- (void)destroySession:(NSUUID *)sessionId {
    __block CactusSession *session = nil;
    dispatch_barrier_async(self.synchronizationQueue, ^{
        session = self.sessions[sessionId];
        [self.sessions removeObjectForKey:sessionId];
    });
    
    if (session) {
        [session stop];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(sessionManager:didDestroySession:)]) {
                [self.delegate sessionManager:self didDestroySession:session];
            }
        });
    }
}

- (void)destroyAllSessions {
    __block NSArray<CactusSession *> *allSessions = nil;
    dispatch_barrier_async(self.synchronizationQueue, ^{
        allSessions = [self.sessions.allValues copy];
        [self.sessions removeAllObjects];
    });
    
    for (CactusSession *session in allSessions) {
        [session stop];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(sessionManager:didDestroySession:)]) {
                [self.delegate sessionManager:self didDestroySession:session];
            }
        });
    }
}

- (NSArray<CactusSession *> *)sessionsWithType:(CactusSessionType)type {
    __block NSArray<CactusSession *> *filteredSessions = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        NSMutableArray<CactusSession *> *sessions = [NSMutableArray array];
        for (CactusSession *session in self.sessions.allValues) {
            if (session.type == type) {
                [sessions addObject:session];
            }
        }
        filteredSessions = [sessions copy];
    });
    return filteredSessions;
}

- (NSArray<CactusSession *> *)sessionsWithState:(CactusSessionState)state {
    __block NSArray<CactusSession *> *filteredSessions = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        NSMutableArray<CactusSession *> *sessions = [NSMutableArray array];
        for (CactusSession *session in self.sessions.allValues) {
            if (session.state == state) {
                [sessions addObject:session];
            }
        }
        filteredSessions = [sessions copy];
    });
    return filteredSessions;
}

- (NSArray<CactusSession *> *)activeChatSessions {
    return [self sessionsWithType:CactusSessionTypeChat];
}

- (void)pauseAllSessions {
    NSArray<CactusSession *> *allSessions = self.activeSessions;
    for (CactusSession *session in allSessions) {
        [session pause];
    }
}

- (void)resumeAllSessions {
    NSArray<CactusSession *> *allSessions = self.activeSessions;
    for (CactusSession *session in allSessions) {
        [session resume];
    }
}

- (void)stopAllSessions {
    NSArray<CactusSession *> *allSessions = self.activeSessions;
    for (CactusSession *session in allSessions) {
        [session stop];
    }
}

- (NSDictionary *)sessionStatistics {
    __block NSInteger totalSessions = 0;
    __block NSInteger chatSessions = 0;
    __block NSInteger completionSessions = 0;
    __block NSInteger embeddingSessions = 0;
    __block NSInteger multimodalSessions = 0;
    __block NSInteger idleSessions = 0;
    __block NSInteger generatingSessions = 0;
    
    dispatch_sync(self.synchronizationQueue, ^{
        totalSessions = self.sessions.count;
        
        for (CactusSession *session in self.sessions.allValues) {
            switch (session.type) {
                case CactusSessionTypeChat: chatSessions++; break;
                case CactusSessionTypeCompletion: completionSessions++; break;
                case CactusSessionTypeEmbedding: embeddingSessions++; break;
                case CactusSessionTypeMultimodal: multimodalSessions++; break;
            }
            
            switch (session.state) {
                case CactusSessionStateIdle: idleSessions++; break;
                case CactusSessionStateGenerating: generatingSessions++; break;
                default: break;
            }
        }
    });
    
    return @{
        @"totalSessions": @(totalSessions),
        @"chatSessions": @(chatSessions),
        @"completionSessions": @(completionSessions),
        @"embeddingSessions": @(embeddingSessions),
        @"multimodalSessions": @(multimodalSessions),
        @"idleSessions": @(idleSessions),
        @"generatingSessions": @(generatingSessions),
        @"maxConcurrentSessions": @(self.maxConcurrentSessions)
    };
}

@end

#pragma mark - Convenience Methods

@implementation CactusSessionManager (Convenience)

- (CactusSession *)createChatSessionWithSystemPrompt:(NSString *)systemPrompt
                                    generationConfig:(CactusGenerationConfiguration *)config {
    CactusSession *session = [self createSessionWithType:CactusSessionTypeChat];
    if (session) {
        session.systemPrompt = systemPrompt;
        session.generationConfig = config ?: [CactusGenerationConfiguration defaultConfiguration];
    }
    return session;
}

- (CactusSession *)createCompletionSessionWithGenerationConfig:(CactusGenerationConfiguration *)config {
    CactusSession *session = [self createSessionWithType:CactusSessionTypeCompletion];
    if (session) {
        session.generationConfig = config ?: [CactusGenerationConfiguration defaultConfiguration];
    }
    return session;
}

- (CactusSession *)createQuickChatSession {
    return [self createChatSessionWithSystemPrompt:nil
                                   generationConfig:[CactusGenerationConfiguration fastConfiguration]];
}

- (CactusSession *)createCreativeChatSession {
    return [self createChatSessionWithSystemPrompt:nil
                                   generationConfig:[CactusGenerationConfiguration creativeConfiguration]];
}

- (CactusSession *)createPreciseChatSession {
    return [self createChatSessionWithSystemPrompt:nil
                                   generationConfig:[CactusGenerationConfiguration preciseConfiguration]];
}

@end
