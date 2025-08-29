//
//  CactusModelManager.mm
//  CactusFramework
//

#import "CactusModelManager.h"
#import "CactusLLMError.h"
#import "CactusBackgroundProcessor.h"
#import "cactus/cactus.h"
#import "cactus/common.h"
#import "cactus/llama-vocab.h"
#import <mutex>

// Notification names
NSNotificationName const CactusModelManagerDidChangeStateNotification = @"CactusModelManagerDidChangeStateNotification";
NSNotificationName const CactusModelManagerDidLoadModelNotification = @"CactusModelManagerDidLoadModelNotification";
NSNotificationName const CactusModelManagerDidUnloadModelNotification = @"CactusModelManagerDidUnloadModelNotification";
NSNotificationName const CactusModelManagerDidFailToLoadNotification = @"CactusModelManagerDidFailToLoadNotification";

// Notification keys
NSString * const CactusModelManagerStateKey = @"state";
NSString * const CactusModelManagerModelInfoKey = @"modelInfo";
NSString * const CactusModelManagerErrorKey = @"error";
NSString * const CactusModelManagerProgressKey = @"progress";

@interface CactusModelManager ()
@property (nonatomic, readwrite) CactusModelState state;
@property (nonatomic, strong, nullable) CactusModelConfiguration *currentConfiguration;
@property (nonatomic, strong, nullable) NSDictionary *modelInfo;
@property (nonatomic, strong, nullable) NSError *lastError;
@property (nonatomic, strong) dispatch_queue_t synchronizationQueue;
@end

@implementation CactusModelManager {
    cactus::cactus_context *_context;
    std::mutex _contextMutex;
    NSUUID *_currentLoadingTaskId;
}

+ (instancetype)sharedManager {
    static CactusModelManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _state = CactusModelStateUnloaded;
        _context = nullptr;
        _synchronizationQueue = dispatch_queue_create("com.cactus.model.manager", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)dealloc {
    [self unloadModelWithCompletionHandler:nil];
}

#pragma mark - Properties

- (BOOL)isLoaded {
    return self.state == CactusModelStateLoaded;
}

- (BOOL)isLoading {
    return self.state == CactusModelStateLoading;
}

#pragma mark - Private Methods

- (void)setState:(CactusModelState)state {
    dispatch_barrier_async(self.synchronizationQueue, ^{
        if (self->_state != state) {
            self->_state = state;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(modelManager:didChangeState:)]) {
                    [self.delegate modelManager:self didChangeState:state];
                }
                
                [[NSNotificationCenter defaultCenter] postNotificationName:CactusModelManagerDidChangeStateNotification
                                                                    object:self
                                                                  userInfo:@{CactusModelManagerStateKey: @(state)}];
            });
        }
    });
}

- (common_params)convertConfiguration:(CactusModelConfiguration *)config {
    common_params params;
    
    params.model.path = config.modelPath.UTF8String;
    params.n_ctx = (int32_t)config.contextSize;
    params.n_batch = (int32_t)config.batchSize;
    params.n_ubatch = (int32_t)config.ubatchSize;
    params.n_gpu_layers = (int32_t)config.gpuLayers;
    params.cpuparams.n_threads = (int32_t)config.threads;
    params.use_mmap = config.useMMap;
    params.use_mlock = config.useMLock;
    params.flash_attn = config.flashAttention;
    params.embedding = config.enableEmbedding;
    params.pooling_type = (enum llama_pooling_type)config.poolingType;
    params.embd_normalize = (int32_t)config.embeddingNormalize;
    
    if (config.cacheTypeK) {
        try {
            params.cache_type_k = cactus::kv_cache_type_from_str(config.cacheTypeK.UTF8String);
        } catch (...) {
            // Use default if conversion fails
        }
    }
    
    if (config.cacheTypeV) {
        try {
            params.cache_type_v = cactus::kv_cache_type_from_str(config.cacheTypeV.UTF8String);
        } catch (...) {
            // Use default if conversion fails
        }
    }
    
    if (config.chatTemplate) {
        params.chat_template = config.chatTemplate.UTF8String;
    }
    
    return params;
}

- (NSDictionary *)extractModelInfo:(cactus::cactus_context *)context {
    if (!context) return nil;
    
    char desc[1024];
    llama_model_desc(context->model, desc, sizeof(desc));

    int count = llama_model_meta_count(context->model);
    NSDictionary *meta = [[NSMutableDictionary alloc] init];
    for (int i = 0; i < count; i++) {
        char key[256];
        llama_model_meta_key_by_index(context->model, i, key, sizeof(key));
        char val[4096];
        llama_model_meta_val_str_by_index(context->model, i, val, sizeof(val));

        NSString *keyStr = [NSString stringWithUTF8String:key];
        NSString *valStr = [NSString stringWithUTF8String:val];
        [meta setValue:valStr forKey:keyStr];
    }

    auto template_tool_use = context->templates.get()->template_tool_use.get();
    NSDictionary *tool_use_caps_dir = nil;
    if (template_tool_use) {
        auto tool_use_caps = template_tool_use->original_caps();
        tool_use_caps_dir = @{
            @"tools": @(tool_use_caps.supports_tools),
            @"toolCalls": @(tool_use_caps.supports_tool_calls),
            @"toolResponses": @(tool_use_caps.supports_tool_responses),
            @"systemRole": @(tool_use_caps.supports_system_role),
            @"parallelToolCalls": @(tool_use_caps.supports_parallel_tool_calls),
            @"toolCallId": @(tool_use_caps.supports_tool_call_id)
        };
    }

    auto default_tmpl = context->templates.get()->template_default.get();
    auto default_tmpl_caps = default_tmpl->original_caps();

    return @{
        @"desc": [NSString stringWithUTF8String:desc],
        @"size": @(llama_model_size(context->model)),
        @"nEmbd": @(llama_model_n_embd(context->model)),
        @"nParams": @(llama_model_n_params(context->model)),
        @"chatTemplates": @{
            @"llamaChat": @(context->validateModelChatTemplate(false, nullptr)),
            @"minja": @{
                @"default": @(context->validateModelChatTemplate(true, nullptr)),
                @"defaultCaps": @{
                    @"tools": @(default_tmpl_caps.supports_tools),
                    @"toolCalls": @(default_tmpl_caps.supports_tool_calls),
                    @"toolResponses": @(default_tmpl_caps.supports_tool_responses),
                    @"systemRole": @(default_tmpl_caps.supports_system_role),
                    @"parallelToolCalls": @(default_tmpl_caps.supports_parallel_tool_calls),
                    @"toolCallId": @(default_tmpl_caps.supports_tool_call_id)
                },
                @"toolUse": @(context->validateModelChatTemplate(true, "tool_use")),
                @"toolUseCaps": tool_use_caps_dir ?: @{}
            }
        },
        @"metadata": meta,

        // deprecated
        @"isChatTemplateSupported": @(context->validateModelChatTemplate(false, nullptr))
    };
}

#pragma mark - Public Methods

- (void)loadModelWithConfiguration:(CactusModelConfiguration *)configuration
                  completionHandler:(void(^)(BOOL success, NSError * _Nullable error))completionHandler {
    [self loadModelWithConfiguration:configuration
                     progressHandler:nil
                   completionHandler:completionHandler];
}

- (void)loadModelWithConfiguration:(CactusModelConfiguration *)configuration
                   progressHandler:(CactusTaskProgressHandler)progressHandler
                 completionHandler:(void(^)(BOOL success, NSError * _Nullable error))completionHandler {
    
    // Validate configuration
    NSError *validationError = nil;
    if (![self validateConfiguration:configuration error:&validationError]) {
        if (completionHandler) {
            completionHandler(NO, validationError);
        }
        return;
    }
    
    // Check if already loading
    if (self.isLoading) {
        NSError *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                             code:CactusLLMErrorInvalidState
                                         userInfo:@{NSLocalizedDescriptionKey: @"Model is already loading"}];
        if (completionHandler) {
            completionHandler(NO, error);
        }
        return;
    }
    
    // Cancel any existing loading task
    if (_currentLoadingTaskId) {
        [[CactusBackgroundProcessor sharedProcessor] cancelTask:_currentLoadingTaskId];
        _currentLoadingTaskId = nil;
    }
    
    self.state = CactusModelStateLoading;
    self.currentConfiguration = [configuration copy];
    self.lastError = nil;
    
    // Create loading task
    __weak typeof(self) weakSelf = self;
    CactusTask *loadTask = [CactusTask taskWithType:CactusTaskTypeModelLoad
                                           priority:CactusTaskPriorityHigh
                                        description:[NSString stringWithFormat:@"Loading model: %@", configuration.modelPath.lastPathComponent]
                                     executionBlock:^id(CactusTask *task, CactusTaskProgressHandler progress) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;
        
        std::lock_guard<std::mutex> lock(strongSelf->_contextMutex);
        
        // Clean up existing context
        if (strongSelf->_context) {
            delete strongSelf->_context;
            strongSelf->_context = nullptr;
        }
        
        // Create new context
        strongSelf->_context = new cactus::cactus_context();
        
        // Convert configuration
        common_params params = [strongSelf convertConfiguration:configuration];
        
        // Set progress callback if provided
        if (configuration.progressCallback) {
            // Note: This would need to be integrated with the actual llama.cpp progress callback
            progress(0.1f);
        }
        
        // Load model
        progress(0.2f);
        bool success = strongSelf->_context->loadModel(params);
        
        if (!success) {
            delete strongSelf->_context;
            strongSelf->_context = nullptr;
            
            NSError *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                                 code:CactusLLMErrorModelLoadFailed
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to load model"}];
            @throw [NSException exceptionWithName:@"ModelLoadException"
                                           reason:error.localizedDescription
                                         userInfo:@{@"error": error}];
        }
        
        progress(0.9f);
        
        // Extract model info
        NSDictionary *modelInfo = [strongSelf extractModelInfo:strongSelf->_context];
        progress(1.0f);
        
        return modelInfo;
    }];
    
    // Set task callbacks
    loadTask.progressHandler = ^(float progress) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && progressHandler) {
            progressHandler(progress);
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([strongSelf.delegate respondsToSelector:@selector(modelManager:didUpdateLoadingProgress:)]) {
                [strongSelf.delegate modelManager:strongSelf didUpdateLoadingProgress:progress];
            }
        });
    };
    
    loadTask.completionHandler = ^(id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        strongSelf->_currentLoadingTaskId = nil;
        
        if (error) {
            strongSelf.state = CactusModelStateError;
            strongSelf.lastError = error;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([strongSelf.delegate respondsToSelector:@selector(modelManager:didFailToLoadWithError:)]) {
                    [strongSelf.delegate modelManager:strongSelf didFailToLoadWithError:error];
                }
                
                [[NSNotificationCenter defaultCenter] postNotificationName:CactusModelManagerDidFailToLoadNotification
                                                                    object:strongSelf
                                                                  userInfo:@{CactusModelManagerErrorKey: error}];
            });
            
            if (completionHandler) {
                completionHandler(NO, error);
            }
        } else {
            strongSelf.modelInfo = result;
            strongSelf.state = CactusModelStateLoaded;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([strongSelf.delegate respondsToSelector:@selector(modelManager:didLoadModelWithInfo:)]) {
                    [strongSelf.delegate modelManager:strongSelf didLoadModelWithInfo:result];
                }
                
                [[NSNotificationCenter defaultCenter] postNotificationName:CactusModelManagerDidLoadModelNotification
                                                                    object:strongSelf
                                                                  userInfo:@{CactusModelManagerModelInfoKey: result}];
            });
            
            if (completionHandler) {
                completionHandler(YES, nil);
            }
        }
    };
    
    // Submit task
    _currentLoadingTaskId = loadTask.taskId;
    [[CactusBackgroundProcessor sharedProcessor] submitTask:loadTask];
}

- (void)unloadModelWithCompletionHandler:(void(^)(void))completionHandler {
    if (self.state == CactusModelStateUnloaded) {
        if (completionHandler) {
            completionHandler();
        }
        return;
    }
    
    // Cancel any loading task
    if (_currentLoadingTaskId) {
        [[CactusBackgroundProcessor sharedProcessor] cancelTask:_currentLoadingTaskId];
        _currentLoadingTaskId = nil;
    }
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        std::lock_guard<std::mutex> lock(self->_contextMutex);
        
        if (self->_context) {
            delete self->_context;
            self->_context = nullptr;
        }
        
        self.currentConfiguration = nil;
        self.modelInfo = nil;
        self.lastError = nil;
        self.state = CactusModelStateUnloaded;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(modelManagerDidUnloadModel:)]) {
                [self.delegate modelManagerDidUnloadModel:self];
            }
            
            [[NSNotificationCenter defaultCenter] postNotificationName:CactusModelManagerDidUnloadModelNotification
                                                                object:self
                                                              userInfo:nil];
            
            if (completionHandler) {
                completionHandler();
            }
        });
    });
}

- (void)reloadModelWithCompletionHandler:(void(^)(BOOL success, NSError * _Nullable error))completionHandler {
    if (!self.currentConfiguration) {
        NSError *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                             code:CactusLLMErrorInvalidState
                                         userInfo:@{NSLocalizedDescriptionKey: @"No configuration available for reload"}];
        if (completionHandler) {
            completionHandler(NO, error);
        }
        return;
    }
    
    CactusModelConfiguration *config = [self.currentConfiguration copy];
    [self unloadModelWithCompletionHandler:^{
        [self loadModelWithConfiguration:config completionHandler:completionHandler];
    }];
}

- (NSDictionary *)getModelInfoForPath:(NSString *)modelPath {
    return [CactusModelManager quickModelInfoForPath:modelPath];
}

- (NSDictionary *)getCurrentModelInfo {
    return self.modelInfo;
}

- (BOOL)validateConfiguration:(CactusModelConfiguration *)configuration error:(NSError **)error {
    return [configuration isValid:error];
}

#pragma mark - Multimodal Support

- (BOOL)initializeMultimodalWithConfiguration:(CactusMultimodalConfiguration *)configuration
                                        error:(NSError **)error {
    std::lock_guard<std::mutex> lock(_contextMutex);
    
    if (!_context) {
        if (error) {
            *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                         code:CactusLLMErrorInvalidState
                                     userInfo:@{NSLocalizedDescriptionKey: @"Model not loaded"}];
        }
        return NO;
    }
    
    if (!configuration.mmprojPath) {
        if (error) {
            *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                         code:CactusLLMErrorInvalidArgument
                                     userInfo:@{NSLocalizedDescriptionKey: @"Multimodal projection path is required"}];
        }
        return NO;
    }
    
    bool success = _context->initMultimodal(configuration.mmprojPath.UTF8String, configuration.useGPU);
    
    if (!success && error) {
        *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                     code:CactusLLMErrorMultimodalInitFailed
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to initialize multimodal capabilities"}];
    }
    
    return success;
}

- (void)releaseMultimodal {
    std::lock_guard<std::mutex> lock(_contextMutex);
    
    if (_context) {
        _context->releaseMultimodal();
    }
}

- (BOOL)isMultimodalEnabled {
    std::lock_guard<std::mutex> lock(_contextMutex);
    
    if (!_context) return NO;
    return _context->isMultimodalEnabled();
}

- (BOOL)isVisionSupported {
    std::lock_guard<std::mutex> lock(_contextMutex);
    
    if (!_context) return NO;
    return _context->isMultimodalSupportVision();
}

- (BOOL)isAudioSupported {
    std::lock_guard<std::mutex> lock(_contextMutex);
    
    if (!_context) return NO;
    return _context->isMultimodalSupportAudio();
}

#pragma mark - LoRA Support

- (BOOL)applyLoRAConfiguration:(CactusLoRAConfiguration *)configuration
                         error:(NSError **)error {
    std::lock_guard<std::mutex> lock(_contextMutex);
    
    if (!_context) {
        if (error) {
            *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                         code:CactusLLMErrorInvalidState
                                     userInfo:@{NSLocalizedDescriptionKey: @"Model not loaded"}];
        }
        return NO;
    }
    
    std::vector<common_adapter_lora_info> lora_adapters;
    
    for (CactusLoRAAdapter *adapter in configuration.adapters) {
        common_adapter_lora_info lora_info;
        lora_info.path = adapter.path.UTF8String;
        lora_info.scale = adapter.scale;
        lora_adapters.push_back(lora_info);
    }
    
    int result = _context->applyLoraAdapters(lora_adapters);
    
    if (result != 0 && error) {
        *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                     code:CactusLLMErrorLoRAApplicationFailed
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to apply LoRA adapters"}];
    }
    
    return result == 0;
}

- (void)removeAllLoRAAdapters {
    std::lock_guard<std::mutex> lock(_contextMutex);
    
    if (_context) {
        _context->removeLoraAdapters();
    }
}

- (NSArray<CactusLoRAAdapter *> *)loadedLoRAAdapters {
    std::lock_guard<std::mutex> lock(_contextMutex);
    
    if (!_context) return @[];
    
    auto loaded_adapters = _context->getLoadedLoraAdapters();
    NSMutableArray<CactusLoRAAdapter *> *adapters = [NSMutableArray array];
    
    for (const auto& adapter : loaded_adapters) {
        CactusLoRAAdapter *objcAdapter = [CactusLoRAAdapter adapterWithPath:@(adapter.path.c_str())
                                                                      scale:adapter.scale];
        [adapters addObject:objcAdapter];
    }
    
    return [adapters copy];
}

#pragma mark - Context Management

- (void)clearContext {
    std::lock_guard<std::mutex> lock(_contextMutex);
    
    if (_context) {
        _context->rewind();
    }
}

- (void)resetSampling {
    std::lock_guard<std::mutex> lock(_contextMutex);
    
    if (_context) {
        _context->initSampling();
    }
}

- (void *)internalContext {
    return _context;
}

@end

#pragma mark - Utilities

@implementation CactusModelManager (Utilities)

+ (NSDictionary *)quickModelInfoForPath:(NSString *)modelPath {
    if (![[NSFileManager defaultManager] fileExistsAtPath:modelPath]) {
        return nil;
    }
    
    NSError *error = nil;
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:modelPath error:&error];
    
    if (error) {
        return nil;
    }
    
    return @{
        @"path": modelPath,
        @"size": fileAttributes[NSFileSize] ?: @0,
        @"modificationDate": fileAttributes[NSFileModificationDate] ?: [NSDate distantPast],
        @"filename": modelPath.lastPathComponent
    };
}

+ (NSDictionary *)deviceCapabilities {
    NSProcessInfo *processInfo = [NSProcessInfo processInfo];
    
    return @{
        @"processorCount": @(processInfo.processorCount),
        @"activeProcessorCount": @(processInfo.activeProcessorCount),
        @"physicalMemory": @(processInfo.physicalMemory),
        @"systemUptime": @(processInfo.systemUptime),
        @"operatingSystemVersion": @{
            @"majorVersion": @(processInfo.operatingSystemVersion.majorVersion),
            @"minorVersion": @(processInfo.operatingSystemVersion.minorVersion),
            @"patchVersion": @(processInfo.operatingSystemVersion.patchVersion)
        }
    };
}

+ (void)freeUnusedMemory {
    // This could trigger garbage collection or memory cleanup
    // Implementation depends on specific memory management needs
}

@end
