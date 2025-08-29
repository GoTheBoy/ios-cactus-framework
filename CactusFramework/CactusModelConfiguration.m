//
//  CactusModelConfiguration.m
//  CactusFramework
//

#import "CactusModelConfiguration.h"
#import "CactusLLMError.h"

// MARK: - Model Configuration Implementation

@implementation CactusModelConfiguration

- (instancetype)init {
    if (self = [super init]) {
        // Set default values
        _contextSize = 4096;
        _batchSize = 512;
        _ubatchSize = 512;
        _gpuLayers = 0;
        _threads = 0;
        _useMMap = YES;
        _useMLock = NO;
        _flashAttention = YES;
        _cacheTypeK = @"f16";
        _cacheTypeV = @"f16";
        _enableEmbedding = NO;
        _poolingType = 0;
        _embeddingNormalize = -1;
    }
    return self;
}

+ (instancetype)defaultConfiguration {
    return [[self alloc] init];
}

+ (instancetype)configurationWithModelPath:(NSString *)modelPath {
    CactusModelConfiguration *config = [self defaultConfiguration];
#if !TARGET_OS_SIMULATOR
    config.gpuLayers = -1
#endif
    config.modelPath = modelPath;
    return config;
}

- (BOOL)isValid:(NSError **)error {
    if (!self.modelPath || self.modelPath.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                         code:CactusLLMErrorInvalidArgument
                                     userInfo:@{NSLocalizedDescriptionKey: @"Model path is required"}];
        }
        return NO;
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.modelPath]) {
        if (error) {
            *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                         code:CactusLLMErrorModelLoadFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Model file does not exist"}];
        }
        return NO;
    }
    
    if (self.contextSize <= 0) {
        if (error) {
            *error = [NSError errorWithDomain:CactusLLMErrorDomain
                                         code:CactusLLMErrorInvalidArgument
                                     userInfo:@{NSLocalizedDescriptionKey: @"Context size must be positive"}];
        }
        return NO;
    }
    
    return YES;
}

- (id)copyWithZone:(NSZone *)zone {
    CactusModelConfiguration *copy = [[CactusModelConfiguration alloc] init];
    copy.modelPath = [self.modelPath copyWithZone:zone];
    copy.contextSize = self.contextSize;
    copy.batchSize = self.batchSize;
    copy.ubatchSize = self.ubatchSize;
    copy.gpuLayers = self.gpuLayers;
    copy.threads = self.threads;
    copy.useMMap = self.useMMap;
    copy.useMLock = self.useMLock;
    copy.flashAttention = self.flashAttention;
    copy.cacheTypeK = [self.cacheTypeK copyWithZone:zone];
    copy.cacheTypeV = [self.cacheTypeV copyWithZone:zone];
    copy.chatTemplate = [self.chatTemplate copyWithZone:zone];
    copy.enableEmbedding = self.enableEmbedding;
    copy.poolingType = self.poolingType;
    copy.embeddingNormalize = self.embeddingNormalize;
    copy.progressCallback = [self.progressCallback copyWithZone:zone];
    return copy;
}

@end

// MARK: - Generation Configuration Implementation

@implementation CactusGenerationConfiguration

- (instancetype)init {
    if (self = [super init]) {
        // Set default values
        _maxTokens = -1;
        _seed = -1;
        _temperature = 0.8f;
        _topK = 40;
        _topP = 0.95f;
        _minP = 0.05f;
        _typicalP = 1.0f;
        _penaltyLastN = 64;
        _penaltyRepeat = 1.1f;
        _penaltyFreq = 0.0f;
        _penaltyPresent = 0.0f;
        _mirostat = 0;
        _mirostatTau = 5.0f;
        _mirostatEta = 0.1f;
        _ignoreEOS = NO;
        _nProbs = 0;
    }
    return self;
}

+ (instancetype)defaultConfiguration {
    return [[self alloc] init];
}

+ (instancetype)fastConfiguration {
    CactusGenerationConfiguration *config = [self defaultConfiguration];
    config.temperature = 0.3f;
    config.topK = 20;
    config.topP = 0.9f;
    config.maxTokens = 256;
    return config;
}

+ (instancetype)creativeConfiguration {
    CactusGenerationConfiguration *config = [self defaultConfiguration];
    config.temperature = 1.2f;
    config.topK = 60;
    config.topP = 0.95f;
    config.penaltyRepeat = 1.05f;
    return config;
}

+ (instancetype)preciseConfiguration {
    CactusGenerationConfiguration *config = [self defaultConfiguration];
    config.temperature = 0.1f;
    config.topK = 10;
    config.topP = 0.85f;
    config.penaltyRepeat = 1.15f;
    return config;
}

- (id)copyWithZone:(NSZone *)zone {
    CactusGenerationConfiguration *copy = [[CactusGenerationConfiguration alloc] init];
    copy.maxTokens = self.maxTokens;
    copy.seed = self.seed;
    copy.temperature = self.temperature;
    copy.topK = self.topK;
    copy.topP = self.topP;
    copy.minP = self.minP;
    copy.typicalP = self.typicalP;
    copy.penaltyLastN = self.penaltyLastN;
    copy.penaltyRepeat = self.penaltyRepeat;
    copy.penaltyFreq = self.penaltyFreq;
    copy.penaltyPresent = self.penaltyPresent;
    copy.mirostat = self.mirostat;
    copy.mirostatTau = self.mirostatTau;
    copy.mirostatEta = self.mirostatEta;
    copy.ignoreEOS = self.ignoreEOS;
    copy.stopSequences = [self.stopSequences copyWithZone:zone];
    copy.grammar = [self.grammar copyWithZone:zone];
    copy.nProbs = self.nProbs;
    return copy;
}

#pragma mark - Utility Methods

- (BOOL)containsStopSequence:(NSString *)text {
    if (!text || text.length == 0 || !self.stopSequences || self.stopSequences.count == 0) {
        return NO;
    }
    
    for (NSString *stopSeq in self.stopSequences) {
        if (stopSeq && stopSeq.length > 0 && [text containsString:stopSeq]) {
            return YES;
        }
    }
    
    return NO;
}

- (NSString *)detectedStopSequence:(NSString *)text {
    if (!text || text.length == 0 || !self.stopSequences || self.stopSequences.count == 0) {
        return nil;
    }
    
    for (NSString *stopSeq in self.stopSequences) {
        if (stopSeq && stopSeq.length > 0 && [text containsString:stopSeq]) {
            return stopSeq;
        }
    }
    
    return nil;
}

- (NSArray<NSString *> *)filteredStopSequences {
    if (!self.stopSequences) {
        return @[];
    }
    
    NSMutableArray<NSString *> *filtered = [NSMutableArray array];
    for (NSString *stopSeq in self.stopSequences) {
        if (stopSeq && stopSeq.length > 0) {
            [filtered addObject:stopSeq];
        }
    }
    
    return [filtered copy];
}

@end

// MARK: - Multimodal Configuration Implementation

@implementation CactusMultimodalConfiguration

- (instancetype)init {
    if (self = [super init]) {
        _useGPU = YES;
        _enableVision = YES;
        _enableAudio = YES;
    }
    return self;
}

+ (instancetype)defaultConfiguration {
    return [[self alloc] init];
}

+ (instancetype)visionOnlyConfiguration {
    CactusMultimodalConfiguration *config = [self defaultConfiguration];
    config.enableAudio = NO;
    return config;
}

+ (instancetype)audioOnlyConfiguration {
    CactusMultimodalConfiguration *config = [self defaultConfiguration];
    config.enableVision = NO;
    return config;
}

- (id)copyWithZone:(NSZone *)zone {
    CactusMultimodalConfiguration *copy = [[CactusMultimodalConfiguration alloc] init];
    copy.mmprojPath = [self.mmprojPath copyWithZone:zone];
    copy.useGPU = self.useGPU;
    copy.enableVision = self.enableVision;
    copy.enableAudio = self.enableAudio;
    copy.vocoderPath = [self.vocoderPath copyWithZone:zone];
    return copy;
}

@end

// MARK: - LoRA Adapter Implementation

@implementation CactusLoRAAdapter

- (instancetype)init {
    if (self = [super init]) {
        _scale = 1.0f;
    }
    return self;
}

+ (instancetype)adapterWithPath:(NSString *)path {
    CactusLoRAAdapter *adapter = [[self alloc] init];
    adapter.path = path;
    return adapter;
}

+ (instancetype)adapterWithPath:(NSString *)path scale:(float)scale {
    CactusLoRAAdapter *adapter = [self adapterWithPath:path];
    adapter.scale = scale;
    return adapter;
}

- (id)copyWithZone:(NSZone *)zone {
    CactusLoRAAdapter *copy = [[CactusLoRAAdapter alloc] init];
    copy.path = [self.path copyWithZone:zone];
    copy.scale = self.scale;
    return copy;
}

@end

// MARK: - LoRA Configuration Implementation

@implementation CactusLoRAConfiguration

+ (instancetype)configurationWithAdapters:(NSArray<CactusLoRAAdapter *> *)adapters {
    CactusLoRAConfiguration *config = [[self alloc] init];
    config.adapters = adapters;
    return config;
}

- (id)copyWithZone:(NSZone *)zone {
    CactusLoRAConfiguration *copy = [[CactusLoRAConfiguration alloc] init];
    copy.adapters = [self.adapters copyWithZone:zone];
    return copy;
}

@end
