//
//  CactusFrameworkUsageExample.m
//  CactusFramework
//

#import "CactusFrameworkUsageExample.h"
#import "CactusLLMMessage.h"
#import "CactusLLMError.h"

@implementation CactusFrameworkUsageExample

#pragma mark - Basic Usage Examples

+ (void)example1_QuickChatSetup {
    NSLog(@"=== Example 1: Quick Chat Setup ===");
    
    // Simplest way to set up chat
//    NSString *modelPath = @"/path/to/your/model.gguf";
    NSString *modelPath = [[NSBundle mainBundle] pathForResource:@"llama_3.2_1b_intruct_tool_calling_v2.Q2_K" ofType:@"gguf"];
    
    [CactusFrameworkModern setupForChatWithModelPath:modelPath
                                   completionHandler:^(CactusFrameworkModern * _Nullable framework, NSError * _Nullable error) {
        if (error) {
            NSLog(@"Failed to setup framework: %@", error.localizedDescription);
            return;
        }
        
        NSLog(@"Framework ready! Model info: %@", framework.currentModelInfo);
        
        // Simple chat
        [framework chatWithMessage:@"Hello! How are you today?"
                  completionHandler:^(NSString * _Nullable response, NSError * _Nullable error) {
            if (response) {
                NSLog(@"AI Response: %@", response);
            } else {
                NSLog(@"Chat failed: %@", error.localizedDescription);
            }
        }];
    }];
}

+ (void)example2_SimpleCompletion {
    NSLog(@"=== Example 2: Simple Completion ===");
    
    CactusFrameworkModern *framework = [CactusFrameworkModern shared];
    
    // Complete text with default settings
    [framework completeText:@"The future of artificial intelligence is"
          completionHandler:^(NSString * _Nullable completion, NSError * _Nullable error) {
        if (completion) {
            NSLog(@"Completion: %@", completion);
        } else {
            NSLog(@"Completion failed: %@", error.localizedDescription);
        }
    }];
}

+ (void)example3_CustomConfiguration {
    NSLog(@"=== Example 3: Custom Configuration ===");
    
    // Create custom model configuration
    CactusModelConfiguration *modelConfig = [CactusModelConfiguration configurationWithModelPath:@"/path/to/model.gguf"];
    modelConfig.contextSize = 8192;
    modelConfig.gpuLayers = 35;
    modelConfig.batchSize = 1024;
    modelConfig.flashAttention = YES;
    
    // Create custom generation configuration with stop sequences
    CactusGenerationConfiguration *genConfig = [CactusGenerationConfiguration creativeConfiguration];
    genConfig.maxTokens = 500;
    genConfig.temperature = 0.9f;
    
    // Set stop sequences to control generation
    genConfig.stopSequences = @[
        @"\n\n",           // Stop at double newlines
        @"The End",        // Stop at "The End"
        @"[END]",          // Stop at [END] marker
        @"</s>",           // Stop at end token
        @"Human:",         // Stop at human prompt
        @"Assistant:"      // Stop at assistant prompt
    ];
    
    CactusFrameworkModern *framework = [CactusFrameworkModern shared];
    [framework initializeWithDelegate:nil];
    
    [framework loadModelWithConfiguration:modelConfig
                        completionHandler:^(BOOL success, NSError * _Nullable error) {
        if (!success) {
            NSLog(@"Model loading failed: %@", error.localizedDescription);
            return;
        }
        
        // Use the custom generation config with stop sequences
        [framework completeText:@"Write a creative story about"
                  configuration:genConfig
              completionHandler:^(NSString * _Nullable completion, NSError * _Nullable error) {
            NSLog(@"Creative completion: %@", completion ?: error.localizedDescription);
        }];
    }];
}

#pragma mark - Advanced Usage Examples

+ (void)example4_SessionManagement {
    NSLog(@"=== Example 4: Session Management ===");
    
    CactusFrameworkModern *framework = [CactusFrameworkModern shared];
    
    // Create multiple chat sessions with different purposes
    CactusSession *assistantSession = [framework createChatSessionWithSystemPrompt:@"You are a helpful assistant."];
    CactusSession *creativeSession = [framework createChatSessionWithSystemPrompt:@"You are a creative writer."];
    CactusSession *techSession = [framework createChatSessionWithSystemPrompt:@"You are a technical expert."];
    
    // Use different sessions for different types of conversations
    CactusLLMMessage *techQuestion = [CactusLLMMessage messageWithRole:CactusLLMRoleUser
                                                               content:@"Explain how neural networks work."];
    [techSession addMessage:techQuestion];
    
    [techSession generateResponseWithCompletionHandler:^(CactusGenerationResult * _Nullable result, NSError * _Nullable error) {
        NSLog(@"Tech Session Response: %@", result.text ?: error.localizedDescription);
        
        // Validate conversation integrity
        [techSession validateConversationIntegrity];
        BOOL isValidFlow = [techSession hasValidConversationFlow];
        NSLog(@"Tech session has valid flow: %@", isValidFlow ? @"YES" : @"NO");
        
        // Get conversation statistics
        NSArray *userMessages = [techSession getUserMessages];
        NSArray *assistantMessages = [techSession getAssistantMessages];
        NSLog(@"Tech session: %ld user messages, %ld assistant messages", (long)userMessages.count, (long)assistantMessages.count);
    }];
    
    CactusLLMMessage *creativePrompt = [CactusLLMMessage messageWithRole:CactusLLMRoleUser
                                                                 content:@"Write a poem about the ocean."];
    [creativeSession addMessage:creativePrompt];
    
    [creativeSession generateResponseWithCompletionHandler:^(CactusGenerationResult * _Nullable result, NSError * _Nullable error) {
        NSLog(@"Creative Session Response: %@", result.text ?: error.localizedDescription);
        
        // Validate conversation integrity
        [creativeSession validateConversationIntegrity];
        BOOL isValidFlow = [creativeSession hasValidConversationFlow];
        NSLog(@"Creative session has valid flow: %@", isValidFlow ? @"YES" : @"NO");
        
        // Clean up sessions when done
        [framework destroySession:techSession.sessionId];
        [framework destroySession:creativeSession.sessionId];
        [framework destroySession:assistantSession.sessionId];
    }];
}

+ (void)example5_StreamingResponses {
    NSLog(@"=== Example 5: Streaming Responses ===");
    
    CactusFrameworkModern *framework = [CactusFrameworkModern shared];
    
    [framework chatWithMessage:@"Tell me a long story about space exploration."
                progressHandler:^(NSString *partialResponse) {
        // This gets called as tokens are generated
        NSLog(@"Streaming: %@", partialResponse);
    } completionHandler:^(NSString * _Nullable response, NSError * _Nullable error) {
        NSLog(@"Final response: %@", response ?: error.localizedDescription);
    }];
}

+ (void)example6_MultimodalProcessing {
    NSLog(@"=== Example 6: Multimodal Processing ===");
    
    CactusFrameworkModern *framework = [CactusFrameworkModern shared];
    
    // Initialize multimodal capabilities
    NSError *multimodalError = nil;
    BOOL success = [framework initializeMultimodalWithProjectionPath:@"/path/to/mmproj.gguf" 
                                                               error:&multimodalError];
    
    if (!success) {
        NSLog(@"Multimodal initialization failed: %@", multimodalError.localizedDescription);
        return;
    }
    
    // Process image with text
    NSArray<NSString *> *mediaPaths = @[@"/path/to/image.jpg"];
    
    [framework processMultimodalInput:@"What do you see in this image?"
                           mediaPaths:mediaPaths
                    completionHandler:^(NSString * _Nullable response, NSError * _Nullable error) {
        NSLog(@"Multimodal response: %@", response ?: error.localizedDescription);
    }];
}

#pragma mark - Advanced Features

+ (void)example7_LoRAAdapters {
    NSLog(@"=== Example 7: LoRA Adapters ===");
    
    CactusFrameworkModern *framework = [CactusFrameworkModern shared];
    
    // Apply a single LoRA adapter
    NSError *error = nil;
    BOOL success = [framework applyLoRAAdapter:@"/path/to/lora1.gguf" 
                                         scale:1.0f 
                                         error:&error];
    
    if (!success) {
        NSLog(@"Failed to apply LoRA adapter: %@", error.localizedDescription);
        return;
    }
    
    // Apply multiple LoRA adapters
    CactusLoRAAdapter *adapter1 = [CactusLoRAAdapter adapterWithPath:@"/path/to/lora1.gguf" scale:1.0f];
    CactusLoRAAdapter *adapter2 = [CactusLoRAAdapter adapterWithPath:@"/path/to/lora2.gguf" scale:0.8f];
    
    success = [framework applyLoRAAdapters:@[adapter1, adapter2] error:&error];
    
    if (success) {
        NSLog(@"Applied LoRA adapters: %@", [framework loadedLoRAAdapters]);
        
        // Test with LoRA applied
        [framework chatWithMessage:@"Test message with LoRA adapters"
                  completionHandler:^(NSString * _Nullable response, NSError * _Nullable error) {
            NSLog(@"LoRA-enhanced response: %@", response ?: error.localizedDescription);
            
            // Remove adapters when done
            [framework removeAllLoRAAdapters];
        }];
    } else {
        NSLog(@"Failed to apply LoRA adapters: %@", error.localizedDescription);
    }
}

+ (void)example8_StopSequences {
    NSLog(@"=== Example 8: Stop Sequences ===");
    
    CactusFrameworkModern *framework = [CactusFrameworkModern shared];
    
    // Create configuration with specific stop sequences
    CactusGenerationConfiguration *config = [CactusGenerationConfiguration defaultConfiguration];
    config.maxTokens = 1000;
    config.temperature = 0.7f;
    
    // Set various types of stop sequences
    config.stopSequences = @[
        @"\n\n",           // Paragraph breaks
        @"Human:",         // Human prompts
        @"Assistant:",     // Assistant responses
        @"[END]",          // End markers
        @"</s>",           // End tokens
        @"The End",        // Story endings
        @"In conclusion",  // Conclusion phrases
        @"To summarize"    // Summary phrases
    ];
    
    // Test stop sequence detection
    NSString *testText = @"This is a test text with Human: in it";
    BOOL containsStop = [config containsStopSequence:testText];
    NSString *detectedStop = [config detectedStopSequence:testText];
    
    NSLog(@"Test text: '%@'", testText);
    NSLog(@"Contains stop sequence: %@", containsStop ? @"YES" : @"NO");
    NSLog(@"Detected stop sequence: '%@'", detectedStop ?: @"None");
    
    // Get filtered stop sequences (removes empty ones)
    NSArray<NSString *> *filtered = [config filteredStopSequences];
    NSLog(@"Filtered stop sequences: %@", filtered);
    
    // Use in generation
    [framework completeText:@"Write a story about a robot"
              configuration:config
          completionHandler:^(NSString * _Nullable completion, NSError * _Nullable error) {
        if (completion) {
            NSLog(@"Story with stop sequences: %@", completion);
        } else {
            NSLog(@"Generation failed: %@", error.localizedDescription);
        }
    }];
}

+ (void)example9_Benchmarking {
    NSLog(@"=== Example 9: Benchmarking ===");
    
    CactusFrameworkModern *framework = [CactusFrameworkModern shared];
    
    // Quick benchmark
    [framework runQuickBenchmarkWithCompletionHandler:^(CactusBenchmarkResult * _Nullable result, NSError * _Nullable error) {
        if (result) {
            NSLog(@"Benchmark results:\n%@", [result summaryString]);
            NSLog(@"Performance: %.1f tokens/sec (generation)", result.textGenerationSpeed);
        } else {
            NSLog(@"Benchmark failed: %@", error.localizedDescription);
        }
    }];
    
    // Custom benchmark configuration
    NSDictionary *benchConfig = @{
        @"promptTokens": @1024,
        @"generationTokens": @256,
        @"parallel": @2,
        @"repetitions": @5
    };
    
    [framework runBenchmarkWithConfiguration:benchConfig
                            completionHandler:^(CactusBenchmarkResult * _Nullable result, NSError * _Nullable error) {
        if (result) {
            NSLog(@"Custom benchmark: %@", [result toDictionary]);
        }
    }];
}

+ (void)example10_BackgroundProcessing {
    NSLog(@"=== Example 9: Background Processing ===");
    
    CactusBackgroundProcessor *processor = [CactusBackgroundProcessor sharedProcessor];
    
    // Configure background processor
    [processor setMaxConcurrentTasks:3];
    
    // Create multiple tasks
    for (int i = 0; i < 5; i++) {
        CactusTask *task = [CactusTask taskWithType:CactusTaskTypeGeneration
                                           priority:CactusTaskPriorityNormal
                                        description:[NSString stringWithFormat:@"Task %d", i+1]
                                     executionBlock:^id(CactusTask *task, CactusTaskProgressHandler progressHandler) {
            // Simulate work
            for (int j = 0; j < 10; j++) {
                if (task.isCancelled) break;
                
                [NSThread sleepForTimeInterval:0.1];
                progressHandler((float)j / 10.0f);
            }
            
            return [NSString stringWithFormat:@"Task %@ completed", task.taskId.UUIDString];
        }];
        
        task.progressHandler = ^(float progress) {
            NSLog(@"Task %@ progress: %.1f%%", task.taskId.UUIDString, progress * 100);
        };
        
        task.completionHandler = ^(id result, NSError *error) {
            NSLog(@"Task completed: %@", result);
        };
        
        [processor submitTask:task];
    }
    
    // Monitor processor statistics
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSDictionary *stats = [processor statistics];
        NSLog(@"Processor stats: %@", stats);
    });
}

#pragma mark - Production Examples

+ (void)example11_ErrorHandling {
    NSLog(@"=== Example 10: Error Handling ===");
    
    CactusFrameworkModern *framework = [CactusFrameworkModern shared];
    
    // Example of comprehensive error handling
    [framework loadModelAtPath:@"/invalid/path/model.gguf"
             completionHandler:^(BOOL success, NSError * _Nullable error) {
        if (!success) {
            switch (error.code) {
                case CactusLLMErrorFileNotFound:
                    NSLog(@"Model file not found. Please check the path.");
                    break;
                case CactusLLMErrorModelLoadFailed:
                    NSLog(@"Model loading failed. Check model format and system resources.");
                    break;
                case CactusLLMErrorInvalidArgument:
                    NSLog(@"Invalid configuration provided.");
                    break;
                default:
                    NSLog(@"Unexpected error: %@", error.localizedDescription);
                    break;
            }
            
            // Log additional error info
            if (error.userInfo[NSUnderlyingErrorKey]) {
                NSLog(@"Underlying error: %@", error.userInfo[NSUnderlyingErrorKey]);
            }
            
            return;
        }
        
        // Try chat with error handling
        [framework chatWithMessage:@"Test message"
                  completionHandler:^(NSString * _Nullable response, NSError * _Nullable error) {
            if (error) {
                NSLog(@"Chat error: %@", error.localizedDescription);
                
                // Handle specific chat errors
                if (error.code == CactusLLMErrorModelNotLoaded) {
                    NSLog(@"Model not loaded - need to load model first");
                } else if (error.code == CactusLLMErrorGenerationFailed) {
                    NSLog(@"Generation failed - try different parameters");
                }
            } else {
                NSLog(@"Chat successful: %@", response);
            }
        }];
    }];
}

+ (void)example12_PerformanceMonitoring {
    NSLog(@"=== Example 11: Performance Monitoring ===");
    
    // Start performance monitoring
    [CactusPerformanceMonitor startMonitoring];
    
    CactusFrameworkModern *framework = [CactusFrameworkModern shared];
    
    // Set up memory usage alerts
    [CactusPerformanceMonitor setMemoryUsageThreshold:1024 // 1GB
                                               handler:^(NSUInteger currentUsageMB) {
        NSLog(@"Memory usage high: %lu MB", (unsigned long)currentUsageMB);
    }];
    
    // Monitor during operations
    [framework chatWithMessage:@"Generate a long response for monitoring"
              completionHandler:^(NSString * _Nullable response, NSError * _Nullable error) {
        // Get current performance stats
        NSDictionary *perfStats = [framework performanceStats];
        NSDictionary *systemInfo = [framework systemInfo];
        
        NSLog(@"Performance stats: %@", perfStats);
        NSLog(@"System info: %@", systemInfo);
        
        // Get framework statistics
        NSDictionary *frameworkStats = [framework frameworkStatistics];
        NSLog(@"Framework stats: %@", frameworkStats);
        
        // Stop monitoring
        [CactusPerformanceMonitor stopMonitoring];
        
        // Get performance history
        NSArray *history = [CactusPerformanceMonitor performanceHistory];
        NSLog(@"Performance history entries: %lu", (unsigned long)history.count);
    }];
}

+ (void)example13_BuilderPattern {
    NSLog(@"=== Example 12: Builder Pattern ===");
    
    // Use builder pattern for complex setup
    [[[[[CactusFrameworkBuilder builder]
        withModelPath:@"/path/to/model.gguf"]
        withLogLevel:CactusLogLevelDebug]
        withMaxConcurrentSessions:10]
        buildAndInitializeWithCompletionHandler:^(CactusFrameworkModern * _Nullable framework, NSError * _Nullable error) {
        
        if (error) {
            NSLog(@"Builder setup failed: %@", error.localizedDescription);
            return;
        }
        
        NSLog(@"Framework built and initialized successfully!");
        NSLog(@"Framework stats: %@", [framework frameworkStatistics]);
        
        // Framework is ready to use
        [framework chatWithMessage:@"Hello from builder pattern!"
                  completionHandler:^(NSString * _Nullable response, NSError * _Nullable error) {
            NSLog(@"Builder pattern chat: %@", response ?: error.localizedDescription);
        }];
    }];
}

#pragma mark - CactusFrameworkDelegate

- (void)frameworkDidInitialize:(id)framework {
    NSLog(@"Framework initialized successfully");
}

- (void)framework:(id)framework didLoadModel:(NSDictionary *)modelInfo {
    NSLog(@"Model loaded: %@", modelInfo);
}

- (void)framework:(id)framework didFailToLoadModel:(NSError *)error {
    NSLog(@"Model loading failed: %@", error.localizedDescription);
}

- (void)framework:(id)framework didReceiveLogMessage:(NSString *)message level:(CactusLogLevel)level {
    NSString *levelString = @"";
    switch (level) {
        case CactusLogLevelVerbose: levelString = @"VERBOSE"; break;
        case CactusLogLevelDebug: levelString = @"DEBUG"; break;
        case CactusLogLevelInfo: levelString = @"INFO"; break;
        case CactusLogLevelWarning: levelString = @"WARNING"; break;
        case CactusLogLevelError: levelString = @"ERROR"; break;
        case CactusLogLevelNone: return;
    }
    
    NSLog(@"[%@] %@", levelString, message);
}

@end
