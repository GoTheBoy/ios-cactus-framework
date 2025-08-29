//
//  CactusBackgroundProcessor.h
//  CactusFramework
//
//  Background processing system for CPU-intensive tasks
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Task priorities
typedef NS_ENUM(NSInteger, CactusTaskPriority) {
    CactusTaskPriorityLow = 0,
    CactusTaskPriorityNormal = 1,
    CactusTaskPriorityHigh = 2,
    CactusTaskPriorityCritical = 3
};

// Task states
typedef NS_ENUM(NSInteger, CactusTaskState) {
    CactusTaskStatePending = 0,
    CactusTaskStateRunning = 1,
    CactusTaskStateCompleted = 2,
    CactusTaskStateCancelled = 3,
    CactusTaskStateFailed = 4
};

// Task types
typedef NS_ENUM(NSInteger, CactusTaskType) {
    CactusTaskTypeModelLoad = 0,
    CactusTaskTypeGeneration = 1,
    CactusTaskTypeEmbedding = 2,
    CactusTaskTypeBenchmark = 3,
    CactusTaskTypeTokenization = 4,
    CactusTaskTypeMultimodal = 5
};

@class CactusTask;

// Task completion handlers
typedef void(^CactusTaskProgressHandler)(float progress);
typedef void(^CactusTaskCompletionHandler)(id _Nullable result, NSError * _Nullable error);
typedef void(^CactusTaskCancellationHandler)(void);

// MARK: - Task Definition

@interface CactusTask : NSObject

@property (nonatomic, readonly) NSUUID *taskId;
@property (nonatomic, readonly) CactusTaskType type;
@property (nonatomic, readonly) CactusTaskPriority priority;
@property (nonatomic, readonly) CactusTaskState state;
@property (nonatomic, readonly) NSDate *createdAt;
@property (nonatomic, readonly, nullable) NSDate *startedAt;
@property (nonatomic, readonly, nullable) NSDate *completedAt;
@property (nonatomic, readonly) float progress;
@property (nonatomic, readonly, nullable) NSString *desc;

// Task execution block
@property (nonatomic, copy, readonly) id(^executionBlock)(CactusTask *task, CactusTaskProgressHandler progressHandler);

// Callbacks
@property (nonatomic, copy, nullable) CactusTaskProgressHandler progressHandler;
@property (nonatomic, copy, nullable) CactusTaskCompletionHandler completionHandler;
@property (nonatomic, copy, nullable) CactusTaskCancellationHandler cancellationHandler;

// Factory methods
+ (instancetype)taskWithType:(CactusTaskType)type
                    priority:(CactusTaskPriority)priority
                 description:(nullable NSString *)description
              executionBlock:(id(^)(CactusTask *task, CactusTaskProgressHandler progressHandler))executionBlock;

// Control methods
- (void)cancel;
- (BOOL)isCancelled;

@end

// MARK: - Background Processor

@protocol CactusBackgroundProcessorDelegate <NSObject>
@optional
- (void)processor:(id)processor didStartTask:(CactusTask *)task;
- (void)processor:(id)processor didCompleteTask:(CactusTask *)task withResult:(id _Nullable)result;
- (void)processor:(id)processor didFailTask:(CactusTask *)task withError:(NSError *)error;
- (void)processor:(id)processor didCancelTask:(CactusTask *)task;
- (void)processor:(id)processor didUpdateProgress:(float)progress forTask:(CactusTask *)task;
@end

@interface CactusBackgroundProcessor : NSObject

@property (nonatomic, weak, nullable) id<CactusBackgroundProcessorDelegate> delegate;
@property (nonatomic, readonly) NSInteger maxConcurrentTasks;
@property (nonatomic, readonly) NSInteger activeTasks;
@property (nonatomic, readonly) NSInteger pendingTasks;
@property (nonatomic, readonly) BOOL isRunning;

// Singleton
+ (instancetype)sharedProcessor;

// Configuration
- (void)setMaxConcurrentTasks:(NSInteger)maxTasks;

// Task management
- (CactusTask *)submitTask:(CactusTask *)task;
- (void)submitTask:(CactusTask *)task
   progressHandler:(nullable CactusTaskProgressHandler)progressHandler
 completionHandler:(nullable CactusTaskCompletionHandler)completionHandler;

// Batch operations
- (NSArray<CactusTask *> *)submitTasks:(NSArray<CactusTask *> *)tasks;

// Task control
- (void)cancelTask:(NSUUID *)taskId;
- (void)cancelAllTasks;
- (void)cancelTasksOfType:(CactusTaskType)type;

// Task queries
- (nullable CactusTask *)taskWithId:(NSUUID *)taskId;
- (NSArray<CactusTask *> *)tasksWithType:(CactusTaskType)type;
- (NSArray<CactusTask *> *)tasksWithState:(CactusTaskState)state;
- (NSArray<CactusTask *> *)allTasks;

// Processor control
- (void)start;
- (void)stop;
- (void)pause;
- (void)resume;

// Statistics
- (NSDictionary *)statistics;

@end

// MARK: - Convenience Task Builders

@interface CactusTask (ConvenienceBuilders)

+ (instancetype)modelLoadTaskWithPath:(NSString *)modelPath
                           parameters:(NSDictionary *)parameters
                      progressHandler:(nullable CactusTaskProgressHandler)progressHandler
                    completionHandler:(nullable CactusTaskCompletionHandler)completionHandler;

+ (instancetype)generationTaskWithPrompt:(NSString *)prompt
                           configuration:(id)configuration
                         progressHandler:(nullable CactusTaskProgressHandler)progressHandler
                       completionHandler:(nullable CactusTaskCompletionHandler)completionHandler;

+ (instancetype)embeddingTaskWithText:(NSString *)text
                        configuration:(id)configuration
                    completionHandler:(nullable CactusTaskCompletionHandler)completionHandler;

+ (instancetype)benchmarkTaskWithParameters:(NSDictionary *)parameters
                           completionHandler:(nullable CactusTaskCompletionHandler)completionHandler;

+ (instancetype)tokenizationTaskWithText:(NSString *)text
                            mediaPaths:(nullable NSArray<NSString *> *)mediaPaths
                         completionHandler:(nullable CactusTaskCompletionHandler)completionHandler;

+ (instancetype)multimodalTaskWithPrompt:(NSString *)prompt
                               mediaPaths:(NSArray<NSString *> *)mediaPaths
                            configuration:(id)configuration
                          progressHandler:(nullable CactusTaskProgressHandler)progressHandler
                        completionHandler:(nullable CactusTaskCompletionHandler)completionHandler;

@end

NS_ASSUME_NONNULL_END
