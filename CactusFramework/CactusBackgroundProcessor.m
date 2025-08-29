//
//  CactusBackgroundProcessor.m
//  CactusFramework
//

#import "CactusBackgroundProcessor.h"
#import "CactusLLMError.h"
#import <os/lock.h>

// MARK: - Task Implementation

@interface CactusTask ()
@property (nonatomic, readwrite) CactusTaskState state;
@property (nonatomic, readwrite) NSDate *startedAt;
@property (nonatomic, readwrite) NSDate *completedAt;
@property (nonatomic, readwrite) float progress;
@property (nonatomic, readwrite) BOOL cancelled;
@end

@implementation CactusTask

- (instancetype)initWithType:(CactusTaskType)type
                    priority:(CactusTaskPriority)priority
                 description:(NSString *)description
              executionBlock:(id(^)(CactusTask *, CactusTaskProgressHandler))executionBlock {
    if (self = [super init]) {
        _taskId = [NSUUID UUID];
        _type = type;
        _priority = priority;
        _desc = description;
        _executionBlock = [executionBlock copy];
        _state = CactusTaskStatePending;
        _createdAt = [NSDate date];
        _progress = 0.0f;
        _cancelled = NO;
    }
    return self;
}

+ (instancetype)taskWithType:(CactusTaskType)type
                    priority:(CactusTaskPriority)priority
                 description:(NSString *)description
              executionBlock:(id(^)(CactusTask *, CactusTaskProgressHandler))executionBlock {
    return [[self alloc] initWithType:type
                             priority:priority
                          description:description
                       executionBlock:executionBlock];
}

- (void)cancel {
    @synchronized(self) {
        if (self.state == CactusTaskStatePending || self.state == CactusTaskStateRunning) {
            self.cancelled = YES;
            self.state = CactusTaskStateCancelled;
            if (self.cancellationHandler) {
                self.cancellationHandler();
            }
        }
    }
}

- (BOOL)isCancelled {
    @synchronized(self) {
        return self.cancelled;
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<CactusTask: %@ type=%ld priority=%ld state=%ld progress=%.2f>",
            self.taskId.UUIDString, (long)self.type, (long)self.priority, (long)self.state, self.progress];
}

@end

// MARK: - Background Processor Implementation

@interface CactusBackgroundProcessor ()
@property (nonatomic, strong) NSOperationQueue *operationQueue;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, CactusTask *> *tasks;
@property (nonatomic, strong) dispatch_queue_t synchronizationQueue;
@property (nonatomic, readwrite) BOOL isRunning;
@property (nonatomic, readwrite) NSInteger maxConcurrentTasks;
@end

@implementation CactusBackgroundProcessor

+ (instancetype)sharedProcessor {
    static CactusBackgroundProcessor *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _operationQueue = [[NSOperationQueue alloc] init];
        _operationQueue.name = @"com.cactus.background.processor";
        _operationQueue.qualityOfService = NSQualityOfServiceUserInitiated;
        _maxConcurrentTasks = 2; // Default to 2 concurrent tasks
        _operationQueue.maxConcurrentOperationCount = _maxConcurrentTasks;
        
        _tasks = [NSMutableDictionary dictionary];
        _synchronizationQueue = dispatch_queue_create("com.cactus.processor.sync", DISPATCH_QUEUE_CONCURRENT);
        _isRunning = YES;
    }
    return self;
}

- (void)setMaxConcurrentTasks:(NSInteger)maxTasks {
    _maxConcurrentTasks = MAX(1, maxTasks);
    self.operationQueue.maxConcurrentOperationCount = _maxConcurrentTasks;
}

- (NSInteger)activeTasks {
    __block NSInteger count = 0;
    dispatch_sync(self.synchronizationQueue, ^{
        for (CactusTask *task in self.tasks.allValues) {
            if (task.state == CactusTaskStateRunning) {
                count++;
            }
        }
    });
    return count;
}

- (NSInteger)pendingTasks {
    __block NSInteger count = 0;
    dispatch_sync(self.synchronizationQueue, ^{
        for (CactusTask *task in self.tasks.allValues) {
            if (task.state == CactusTaskStatePending) {
                count++;
            }
        }
    });
    return count;
}

- (CactusTask *)submitTask:(CactusTask *)task {
    if (!self.isRunning) {
        return nil;
    }
    
    dispatch_barrier_async(self.synchronizationQueue, ^{
        self.tasks[task.taskId] = task;
    });
    
    [self executeTask:task];
    return task;
}

- (void)submitTask:(CactusTask *)task
   progressHandler:(CactusTaskProgressHandler)progressHandler
 completionHandler:(CactusTaskCompletionHandler)completionHandler {
    task.progressHandler = progressHandler;
    task.completionHandler = completionHandler;
    [self submitTask:task];
}

- (NSArray<CactusTask *> *)submitTasks:(NSArray<CactusTask *> *)tasks {
    NSMutableArray<CactusTask *> *submittedTasks = [NSMutableArray array];
    for (CactusTask *task in tasks) {
        CactusTask *submittedTask = [self submitTask:task];
        if (submittedTask) {
            [submittedTasks addObject:submittedTask];
        }
    }
    return [submittedTasks copy];
}

- (void)executeTask:(CactusTask *)task {
    NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        if (task.isCancelled) {
            return;
        }
        
        @synchronized(task) {
            task.state = CactusTaskStateRunning;
            task.startedAt = [NSDate date];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(processor:didStartTask:)]) {
                [self.delegate processor:self didStartTask:task];
            }
        });
        
        __weak typeof(task) weakTask = task;
        CactusTaskProgressHandler progressHandler = ^(float progress) {
            __strong typeof(weakTask) strongTask = weakTask;
            if (strongTask && !strongTask.isCancelled) {
                @synchronized(strongTask) {
                    strongTask.progress = progress;
                }
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (strongTask.progressHandler) {
                        strongTask.progressHandler(progress);
                    }
                    if ([self.delegate respondsToSelector:@selector(processor:didUpdateProgress:forTask:)]) {
                        [self.delegate processor:self didUpdateProgress:progress forTask:strongTask];
                    }
                });
            }
        };
        
        @try {
            id result = nil;
            NSError *error = nil;
            
            if (!task.isCancelled && task.executionBlock) {
                result = task.executionBlock(task, progressHandler);
            }
            
            if (task.isCancelled) {
                @synchronized(task) {
                    task.state = CactusTaskStateCancelled;
                    task.completedAt = [NSDate date];
                }
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([self.delegate respondsToSelector:@selector(processor:didCancelTask:)]) {
                        [self.delegate processor:self didCancelTask:task];
                    }
                });
            } else {
                @synchronized(task) {
                    task.state = CactusTaskStateCompleted;
                    task.completedAt = [NSDate date];
                    task.progress = 1.0f;
                }
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (task.completionHandler) {
                        task.completionHandler(result, error);
                    }
                    if ([self.delegate respondsToSelector:@selector(processor:didCompleteTask:withResult:)]) {
                        [self.delegate processor:self didCompleteTask:task withResult:result];
                    }
                });
            }
        } @catch (NSException *exception) {
            NSError *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                                 code:CactusLLMErrorUnknown
                                             userInfo:@{
                                                 NSLocalizedDescriptionKey: exception.reason ?: @"Task execution failed",
                                                 @"exception": exception
                                             }];
            
            @synchronized(task) {
                task.state = CactusTaskStateFailed;
                task.completedAt = [NSDate date];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (task.completionHandler) {
                    task.completionHandler(nil, error);
                }
                if ([self.delegate respondsToSelector:@selector(processor:didFailTask:withError:)]) {
                    [self.delegate processor:self didFailTask:task withError:error];
                }
            });
        }
    }];
    
    // Set operation priority based on task priority
    switch (task.priority) {
        case CactusTaskPriorityCritical:
            operation.queuePriority = NSOperationQueuePriorityVeryHigh;
            break;
        case CactusTaskPriorityHigh:
            operation.queuePriority = NSOperationQueuePriorityHigh;
            break;
        case CactusTaskPriorityNormal:
            operation.queuePriority = NSOperationQueuePriorityNormal;
            break;
        case CactusTaskPriorityLow:
            operation.queuePriority = NSOperationQueuePriorityLow;
            break;
    }
    
    [self.operationQueue addOperation:operation];
}

- (void)cancelTask:(NSUUID *)taskId {
    __block CactusTask *task = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        task = self.tasks[taskId];
    });
    
    if (task) {
        [task cancel];
    }
}

- (void)cancelAllTasks {
    __block NSArray<CactusTask *> *allTasks = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        allTasks = [self.tasks.allValues copy];
    });
    
    for (CactusTask *task in allTasks) {
        [task cancel];
    }
    
    [self.operationQueue cancelAllOperations];
}

- (void)cancelTasksOfType:(CactusTaskType)type {
    __block NSArray<CactusTask *> *tasksToCancel = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        NSMutableArray<CactusTask *> *filteredTasks = [NSMutableArray array];
        for (CactusTask *task in self.tasks.allValues) {
            if (task.type == type) {
                [filteredTasks addObject:task];
            }
        }
        tasksToCancel = [filteredTasks copy];
    });
    
    for (CactusTask *task in tasksToCancel) {
        [task cancel];
    }
}

- (CactusTask *)taskWithId:(NSUUID *)taskId {
    __block CactusTask *task = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        task = self.tasks[taskId];
    });
    return task;
}

- (NSArray<CactusTask *> *)tasksWithType:(CactusTaskType)type {
    __block NSArray<CactusTask *> *filteredTasks = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        NSMutableArray<CactusTask *> *tasks = [NSMutableArray array];
        for (CactusTask *task in self.tasks.allValues) {
            if (task.type == type) {
                [tasks addObject:task];
            }
        }
        filteredTasks = [tasks copy];
    });
    return filteredTasks;
}

- (NSArray<CactusTask *> *)tasksWithState:(CactusTaskState)state {
    __block NSArray<CactusTask *> *filteredTasks = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        NSMutableArray<CactusTask *> *tasks = [NSMutableArray array];
        for (CactusTask *task in self.tasks.allValues) {
            if (task.state == state) {
                [tasks addObject:task];
            }
        }
        filteredTasks = [tasks copy];
    });
    return filteredTasks;
}

- (NSArray<CactusTask *> *)allTasks {
    __block NSArray<CactusTask *> *allTasks = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        allTasks = [self.tasks.allValues copy];
    });
    return allTasks;
}

- (void)start {
    self.isRunning = YES;
}

- (void)stop {
    self.isRunning = NO;
    [self cancelAllTasks];
}

- (void)pause {
    self.operationQueue.suspended = YES;
}

- (void)resume {
    self.operationQueue.suspended = NO;
}

- (NSDictionary *)statistics {
    __block NSInteger pending = 0, running = 0, completed = 0, cancelled = 0, failed = 0;
    
    dispatch_sync(self.synchronizationQueue, ^{
        for (CactusTask *task in self.tasks.allValues) {
            switch (task.state) {
                case CactusTaskStatePending: pending++; break;
                case CactusTaskStateRunning: running++; break;
                case CactusTaskStateCompleted: completed++; break;
                case CactusTaskStateCancelled: cancelled++; break;
                case CactusTaskStateFailed: failed++; break;
            }
        }
    });
    
    return @{
        @"totalTasks": @(self.tasks.count),
        @"pendingTasks": @(pending),
        @"runningTasks": @(running),
        @"completedTasks": @(completed),
        @"cancelledTasks": @(cancelled),
        @"failedTasks": @(failed),
        @"maxConcurrentTasks": @(self.maxConcurrentTasks),
        @"isRunning": @(self.isRunning)
    };
}

@end

// MARK: - Convenience Task Builders

@implementation CactusTask (ConvenienceBuilders)

+ (instancetype)modelLoadTaskWithPath:(NSString *)modelPath
                           parameters:(NSDictionary *)parameters
                      progressHandler:(CactusTaskProgressHandler)progressHandler
                    completionHandler:(CactusTaskCompletionHandler)completionHandler {
    
    CactusTask *task = [CactusTask taskWithType:CactusTaskTypeModelLoad
                                       priority:CactusTaskPriorityHigh
                                    description:[NSString stringWithFormat:@"Loading model: %@", modelPath.lastPathComponent]
                                 executionBlock:^id(CactusTask *task, CactusTaskProgressHandler progress) {
                                     // Implementation will be added when integrating with actual model loading
                                     progress(1.0f);
                                     return @{@"modelPath": modelPath, @"loaded": @YES};
                                 }];
    
    task.progressHandler = progressHandler;
    task.completionHandler = completionHandler;
    return task;
}

+ (instancetype)generationTaskWithPrompt:(NSString *)prompt
                           configuration:(id)configuration
                         progressHandler:(CactusTaskProgressHandler)progressHandler
                       completionHandler:(CactusTaskCompletionHandler)completionHandler {
    
    CactusTask *task = [CactusTask taskWithType:CactusTaskTypeGeneration
                                       priority:CactusTaskPriorityNormal
                                    description:[NSString stringWithFormat:@"Generating text for prompt: %@", [prompt substringToIndex:MIN(50, prompt.length)]]
                                 executionBlock:^id(CactusTask *task, CactusTaskProgressHandler progress) {
                                     // Implementation will be added when integrating with actual generation
                                     progress(1.0f);
                                     return @{@"text": @"Generated response", @"tokens": @42};
                                 }];
    
    task.progressHandler = progressHandler;
    task.completionHandler = completionHandler;
    return task;
}

+ (instancetype)embeddingTaskWithText:(NSString *)text
                        configuration:(id)configuration
                    completionHandler:(CactusTaskCompletionHandler)completionHandler {
    
    CactusTask *task = [CactusTask taskWithType:CactusTaskTypeEmbedding
                                       priority:CactusTaskPriorityNormal
                                    description:[NSString stringWithFormat:@"Computing embedding for text: %@", [text substringToIndex:MIN(50, text.length)]]
                                 executionBlock:^id(CactusTask *task, CactusTaskProgressHandler progress) {
                                     // Implementation will be added when integrating with actual embedding
                                     progress(1.0f);
                                     return @{@"embedding": @[], @"dimensions": @768};
                                 }];
    
    task.completionHandler = completionHandler;
    return task;
}

+ (instancetype)benchmarkTaskWithParameters:(NSDictionary *)parameters
                           completionHandler:(CactusTaskCompletionHandler)completionHandler {
    
    CactusTask *task = [CactusTask taskWithType:CactusTaskTypeBenchmark
                                       priority:CactusTaskPriorityLow
                                    description:@"Running benchmark"
                                 executionBlock:^id(CactusTask *task, CactusTaskProgressHandler progress) {
                                     // Implementation will be added when integrating with actual benchmark
                                     progress(1.0f);
                                     return @{@"results": @"Benchmark completed"};
                                 }];
    
    task.completionHandler = completionHandler;
    return task;
}

+ (instancetype)tokenizationTaskWithText:(NSString *)text
                              mediaPaths:(NSArray<NSString *> *)mediaPaths
                       completionHandler:(CactusTaskCompletionHandler)completionHandler {
    
    CactusTask *task = [CactusTask taskWithType:CactusTaskTypeTokenization
                                       priority:CactusTaskPriorityNormal
                                    description:@"Tokenizing text"
                                 executionBlock:^id(CactusTask *task, CactusTaskProgressHandler progress) {
                                     // Implementation will be added when integrating with actual tokenization
                                     progress(1.0f);
                                     return @{@"tokens": @[], @"count": @0};
                                 }];
    
    task.completionHandler = completionHandler;
    return task;
}

+ (instancetype)multimodalTaskWithPrompt:(NSString *)prompt
                               mediaPaths:(NSArray<NSString *> *)mediaPaths
                            configuration:(id)configuration
                          progressHandler:(CactusTaskProgressHandler)progressHandler
                        completionHandler:(CactusTaskCompletionHandler)completionHandler {
    
    CactusTask *task = [CactusTask taskWithType:CactusTaskTypeMultimodal
                                       priority:CactusTaskPriorityNormal
                                    description:@"Processing multimodal input"
                                 executionBlock:^id(CactusTask *task, CactusTaskProgressHandler progress) {
                                     // Implementation will be added when integrating with actual multimodal processing
                                     progress(1.0f);
                                     return @{@"response": @"Multimodal response"};
                                 }];
    
    task.progressHandler = progressHandler;
    task.completionHandler = completionHandler;
    return task;
}

@end
