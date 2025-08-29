# CactusFramework Modern Objective-C Wrapper

Một wrapper Objective-C hiện đại, dễ sử dụng và có thể mở rộng cho CactusFramework, được thiết kế theo các nguyên tắc:

- **Dễ sử dụng**: API đơn giản với các phương thức tiện ích
- **Dễ mở rộng**: Kiến trúc modular với các protocol và delegate
- **Tùy chỉnh linh hoạt**: Các class configuration cho phép tùy chỉnh chi tiết
- **Background processing**: Tất cả task nặng được xử lý trên background thread

## Kiến trúc

### Core Components

1. **Configuration Layer**
   - `CactusModelConfiguration`: Cấu hình model và performance
   - `CactusGenerationConfiguration`: Cấu hình generation parameters
   - `CactusMultimodalConfiguration`: Cấu hình multimodal features
   - `CactusLoRAConfiguration`: Cấu hình LoRA adapters

2. **Management Layer**
   - `CactusModelManager`: Quản lý lifecycle của model (thread-safe)
   - `CactusSessionManager`: Quản lý chat sessions và streaming
   - `CactusBackgroundProcessor`: Xử lý background tasks với priority queue

3. **Utility Layer**
   - `CactusTokenizer`: Tokenization và detokenization
   - `CactusBenchmark`: Performance benchmarking
   - `CactusLoRAManager`: LoRA adapter management
   - `CactusLogger`: Logging system với multiple levels
   - `CactusPerformanceMonitor`: Real-time performance monitoring

4. **Facade Layer**
   - `CactusFrameworkModern`: Main facade class với API đơn giản
   - `CactusFrameworkBuilder`: Builder pattern cho setup phức tạp

## Quick Start

### 1. Basic Chat Setup (Cách đơn giản nhất)

```objc
#import "CactusFrameworkModern.h"

// Setup và chat trong một bước
[CactusFrameworkModern setupForChatWithModelPath:@"/path/to/model.gguf"
                               completionHandler:^(CactusFrameworkModern *framework, NSError *error) {
    if (error) {
        NSLog(@"Setup failed: %@", error.localizedDescription);
        return;
    }
    
    // Chat ngay lập tức
    [framework chatWithMessage:@"Hello! How are you?"
              completionHandler:^(NSString *response, NSError *error) {
        NSLog(@"AI: %@", response);
    }];
}];
```

### 2. Streaming Chat với Progress

```objc
CactusFrameworkModern *framework = [CactusFrameworkModern shared];

[framework chatWithMessage:@"Tell me a story"
            progressHandler:^(NSString *partialResponse) {
    // Nhận từng token khi được generate
    NSLog(@"Streaming: %@", partialResponse);
} completionHandler:^(NSString *response, NSError *error) {
    NSLog(@"Complete: %@", response);
}];
```

### 3. Custom Configuration

```objc
// Tạo model configuration tùy chỉnh
CactusModelConfiguration *modelConfig = [CactusModelConfiguration configurationWithModelPath:@"/path/to/model.gguf"];
modelConfig.contextSize = 8192;
modelConfig.gpuLayers = 35;
modelConfig.flashAttention = YES;

// Tạo generation configuration
CactusGenerationConfiguration *genConfig = [CactusGenerationConfiguration creativeConfiguration];
genConfig.temperature = 0.9f;
genConfig.maxTokens = 500;

CactusFrameworkModern *framework = [CactusFrameworkModern shared];
[framework loadModelWithConfiguration:modelConfig
                    completionHandler:^(BOOL success, NSError *error) {
    if (success) {
        [framework completeText:@"Write a story about"
                  configuration:genConfig
              completionHandler:^(NSString *completion, NSError *error) {
            NSLog(@"Creative story: %@", completion);
        }];
    }
}];
```

## Advanced Features

### Session Management

```objc
CactusFrameworkModern *framework = [CactusFrameworkModern shared];

// Tạo nhiều session cho các mục đích khác nhau
CactusSession *assistantSession = [framework createChatSessionWithSystemPrompt:@"You are a helpful assistant."];
CactusSession *creativeSession = [framework createChatSessionWithSystemPrompt:@"You are a creative writer."];

// Sử dụng session riêng biệt
CactusLLMMessage *question = [CactusLLMMessage messageWithRole:CactusLLMRoleUser content:@"Explain quantum physics"];
[assistantSession addMessage:question];

[assistantSession generateResponseWithCompletionHandler:^(CactusGenerationResult *result, NSError *error) {
    NSLog(@"Assistant: %@", result.text);
    
    // Validate conversation integrity
    [assistantSession validateConversationIntegrity];
    BOOL isValidFlow = [assistantSession hasValidConversationFlow];
    
    // Get conversation statistics
    NSArray *userMessages = [assistantSession getUserMessages];
    NSArray *assistantMessages = [assistantSession getAssistantMessages];
    NSLog(@"Session: %ld user messages, %ld assistant messages", (long)userMessages.count, (long)assistantMessages.count);
}];
```

### Conversation Management

```objc
CactusSession *session = [framework createChatSession];

// Add messages to build conversation
[session addMessage:[CactusLLMMessage messageWithRole:CactusLLMRoleUser content:@"Hello!"]];
[session addMessage:[CactusLLMMessage messageWithRole:CactusLLMRoleAssistant content:@"Hi there! How can I help you?"]];
[session addMessage:[CactusLLMMessage messageWithRole:CactusLLMRoleUser content:@"Tell me a joke"]];

// Validate conversation integrity
[session validateConversationIntegrity];
BOOL isValidFlow = [session hasValidConversationFlow];

// Get conversation components
NSArray *history = [session getConversationHistory];
NSArray *userMessages = [session getUserMessages];
NSArray *assistantMessages = [session getAssistantMessages];
```

### Multimodal Processing

```objc
// Initialize multimodal
NSError *error = nil;
BOOL success = [framework initializeMultimodalWithProjectionPath:@"/path/to/mmproj.gguf" error:&error];

if (success) {
    // Process image với text
    [framework processMultimodalInput:@"What's in this image?"
                           mediaPaths:@[@"/path/to/image.jpg"]
                    completionHandler:^(NSString *response, NSError *error) {
        NSLog(@"Vision response: %@", response);
    }];
}
```

### LoRA Adapters

```objc
// Apply LoRA adapters
CactusLoRAAdapter *adapter1 = [CactusLoRAAdapter adapterWithPath:@"/path/to/lora1.gguf" scale:1.0f];
CactusLoRAAdapter *adapter2 = [CactusLoRAAdapter adapterWithPath:@"/path/to/lora2.gguf" scale:0.8f];

NSError *error = nil;
BOOL success = [framework applyLoRAAdapters:@[adapter1, adapter2] error:&error];

if (success) {
    NSLog(@"LoRA adapters applied: %@", [framework loadedLoRAAdapters]);
}
```

### Performance Monitoring

```objc
// Bắt đầu monitoring
[CactusPerformanceMonitor startMonitoring];

// Set memory threshold
[CactusPerformanceMonitor setMemoryUsageThreshold:1024 // 1GB
                                           handler:^(NSUInteger currentUsageMB) {
    NSLog(@"High memory usage: %lu MB", currentUsageMB);
}];

// Get current stats
NSDictionary *stats = [framework performanceStats];
NSLog(@"Performance: %@", stats);
```

### Builder Pattern

```objc
[[[[CactusFrameworkBuilder builder]
    withModelPath:@"/path/to/model.gguf"]
    withLogLevel:CactusLogLevelDebug]
    withMaxConcurrentSessions:10]
    buildAndInitializeWithCompletionHandler:^(CactusFrameworkModern *framework, NSError *error) {
    
    if (framework) {
        NSLog(@"Framework ready!");
        // Sử dụng framework...
    }
}];
```

## Configuration Options

### Model Configuration

```objc
CactusModelConfiguration *config = [CactusModelConfiguration defaultConfiguration];
config.modelPath = @"/path/to/model.gguf";
config.contextSize = 4096;           // Context window size
config.batchSize = 512;              // Batch size for processing
config.gpuLayers = -1;               // Auto-detect GPU layers
config.threads = 0;                  // Auto-detect CPU threads
config.useMMap = YES;                // Use memory mapping
config.flashAttention = YES;         // Enable flash attention
config.cacheTypeK = @"f16";          // Key cache type
config.cacheTypeV = @"f16";          // Value cache type
```

### Generation Configuration

```objc
CactusGenerationConfiguration *config = [CactusGenerationConfiguration defaultConfiguration];
config.maxTokens = 500;              // Max tokens to generate
config.temperature = 0.8f;           // Creativity level
config.topK = 40;                    // Top-K sampling
config.topP = 0.95f;                 // Top-P sampling
config.penaltyRepeat = 1.1f;         // Repetition penalty
config.stopSequences = @[@"</s>"];   // Stop sequences

// Stop sequences control when generation should stop
config.stopSequences = @[
    @"\n\n",           // Stop at paragraph breaks
    @"Human:",         // Stop at human prompts
    @"Assistant:",     // Stop at assistant responses
    @"[END]",          // Stop at end markers
    @"The End"         // Stop at story endings
];

// Utility methods for stop sequence management
BOOL containsStop = [config containsStopSequence:text];
NSString *detectedStop = [config detectedStopSequence:text];
NSArray *filteredStops = [config filteredStopSequences];
```

## Error Handling

```objc
[framework loadModelAtPath:@"/path/to/model.gguf"
         completionHandler:^(BOOL success, NSError *error) {
    if (!success) {
        switch (error.code) {
            case CactusLLMErrorFileNotFound:
                NSLog(@"Model file not found");
                break;
            case CactusLLMErrorModelLoadFailed:
                NSLog(@"Model loading failed");
                break;
            case CactusLLMErrorInvalidArgument:
                NSLog(@"Invalid configuration");
                break;
            default:
                NSLog(@"Unexpected error: %@", error.localizedDescription);
                break;
        }
    }
}];
```

## Background Processing

Tất cả các operation nặng đều được xử lý trên background threads:

- Model loading
- Text generation
- Tokenization
- Benchmarking
- Multimodal processing

Framework tự động quản lý thread pool và priority queue để đảm bảo performance tốt nhất.

## Logging

```objc
// Configure logging
[CactusLogger setLogLevel:CactusLogLevelInfo];

// Custom log handler
[CactusLogger setLogHandler:^(CactusLogLevel level, NSString *message) {
    // Custom logging logic
    NSLog(@"[Custom] %@", message);
}];

// Enable file logging
[CactusLogger enableFileLogging:@"/path/to/logfile.txt"];
```

## Best Practices

1. **Model Loading**: Luôn load model trước khi sử dụng
2. **Error Handling**: Luôn check error trong completion handlers
3. **Session Management**: Destroy sessions khi không cần thiết
4. **Memory Management**: Monitor memory usage cho models lớn
5. **Background Processing**: Sử dụng progress handlers cho UX tốt hơn
6. **Configuration**: Sử dụng preset configurations cho các use case phổ biến

## Examples

Xem file `CactusFrameworkUsageExample.m` để có các ví dụ chi tiết về:

- Basic usage patterns
- Advanced features
- Error handling
- Performance monitoring
- Production-ready code

## Thread Safety

Tất cả các public API đều thread-safe. Framework sử dụng:

- Concurrent queues cho read operations
- Barrier queues cho write operations
- Atomic properties cho state management
- Proper synchronization cho shared resources

## Performance

Framework được tối ưu cho performance:

- Background processing cho tất cả heavy operations
- Memory-efficient tokenization
- Optimized model loading
- Smart session management
- Real-time performance monitoring

Sử dụng `CactusBenchmark` để đo performance của model trên device cụ thể.
