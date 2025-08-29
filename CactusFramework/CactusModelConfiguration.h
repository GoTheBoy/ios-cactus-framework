//
//  CactusModelConfiguration.h
//  CactusFramework
//
//  Modern Configuration Classes for CactusFramework
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - Model Configuration

@interface CactusModelConfiguration : NSObject <NSCopying>

// Required
@property (nonatomic, copy) NSString *modelPath;

// Context and Performance
@property (nonatomic, assign) NSInteger contextSize;        // Default: 4096
@property (nonatomic, assign) NSInteger batchSize;          // Default: 512
@property (nonatomic, assign) NSInteger ubatchSize;         // Default: 512
@property (nonatomic, assign) NSInteger gpuLayers;          // Default: -1 (auto)
@property (nonatomic, assign) NSInteger threads;            // Default: 0 (auto)

// Memory Management
@property (nonatomic, assign) BOOL useMMap;                 // Default: YES
@property (nonatomic, assign) BOOL useMLock;                // Default: NO
@property (nonatomic, assign) BOOL flashAttention;          // Default: YES

// Cache Configuration
@property (nonatomic, copy, nullable) NSString *cacheTypeK; // Default: "f16"
@property (nonatomic, copy, nullable) NSString *cacheTypeV; // Default: "f16"

// Chat Template
@property (nonatomic, copy, nullable) NSString *chatTemplate;

// Embedding Configuration
@property (nonatomic, assign) BOOL enableEmbedding;         // Default: NO
@property (nonatomic, assign) NSInteger poolingType;        // Default: 0
@property (nonatomic, assign) NSInteger embeddingNormalize; // Default: -1

// Progress Callback
@property (nonatomic, copy, nullable) void (^progressCallback)(float progress);

// Factory methods
+ (instancetype)defaultConfiguration;
+ (instancetype)configurationWithModelPath:(NSString *)modelPath;

// Validation
- (BOOL)isValid:(NSError **)error;

@end

// MARK: - Generation Configuration

@interface CactusGenerationConfiguration : NSObject <NSCopying>

// Generation Parameters
@property (nonatomic, assign) NSInteger maxTokens;          // Default: -1 (unlimited)
@property (nonatomic, assign) NSInteger seed;               // Default: -1 (random)
@property (nonatomic, assign) float temperature;            // Default: 0.8
@property (nonatomic, assign) NSInteger topK;               // Default: 40
@property (nonatomic, assign) float topP;                   // Default: 0.95
@property (nonatomic, assign) float minP;                   // Default: 0.05
@property (nonatomic, assign) float typicalP;               // Default: 1.0

// Penalty Parameters
@property (nonatomic, assign) NSInteger penaltyLastN;       // Default: 64
@property (nonatomic, assign) float penaltyRepeat;          // Default: 1.1
@property (nonatomic, assign) float penaltyFreq;            // Default: 0.0
@property (nonatomic, assign) float penaltyPresent;         // Default: 0.0

// Mirostat
@property (nonatomic, assign) NSInteger mirostat;           // Default: 0
@property (nonatomic, assign) float mirostatTau;            // Default: 5.0
@property (nonatomic, assign) float mirostatEta;            // Default: 0.1

// Stop Conditions
@property (nonatomic, assign) BOOL ignoreEOS;               // Default: NO
@property (nonatomic, copy, nullable) NSArray<NSString *> *stopSequences;

// Grammar
@property (nonatomic, copy, nullable) NSString *grammar;

// Token Probabilities
@property (nonatomic, assign) NSInteger nProbs;             // Default: 0

// Factory methods
+ (instancetype)defaultConfiguration;
+ (instancetype)fastConfiguration;      // For quick responses
+ (instancetype)creativeConfiguration;  // For creative writing
+ (instancetype)preciseConfiguration;   // For precise answers

// Utility methods
- (BOOL)containsStopSequence:(NSString *)text;
- (NSString *)detectedStopSequence:(NSString *)text;
- (NSArray<NSString *> *)filteredStopSequences; // Remove empty or invalid sequences

@end

// MARK: - Multimodal Configuration

@interface CactusMultimodalConfiguration : NSObject <NSCopying>

@property (nonatomic, copy, nullable) NSString *mmprojPath;
@property (nonatomic, assign) BOOL useGPU;                  // Default: YES
@property (nonatomic, assign) BOOL enableVision;            // Default: YES
@property (nonatomic, assign) BOOL enableAudio;             // Default: YES

// TTS/Vocoder Configuration
@property (nonatomic, copy, nullable) NSString *vocoderPath;

+ (instancetype)defaultConfiguration;
+ (instancetype)visionOnlyConfiguration;
+ (instancetype)audioOnlyConfiguration;

@end

// MARK: - LoRA Configuration

@interface CactusLoRAAdapter : NSObject <NSCopying>

@property (nonatomic, copy) NSString *path;
@property (nonatomic, assign) float scale;                  // Default: 1.0

+ (instancetype)adapterWithPath:(NSString *)path;
+ (instancetype)adapterWithPath:(NSString *)path scale:(float)scale;

@end

@interface CactusLoRAConfiguration : NSObject <NSCopying>

@property (nonatomic, copy) NSArray<CactusLoRAAdapter *> *adapters;

+ (instancetype)configurationWithAdapters:(NSArray<CactusLoRAAdapter *> *)adapters;

@end

NS_ASSUME_NONNULL_END
