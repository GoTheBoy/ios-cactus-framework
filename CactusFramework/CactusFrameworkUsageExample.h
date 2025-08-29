//
//  CactusFrameworkUsageExample.h
//  CactusFramework
//
//  Usage examples for the modern CactusFramework wrapper
//

#import <Foundation/Foundation.h>
#import "CactusFrameworkModern.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * This class demonstrates various ways to use the CactusFramework wrapper
 * with different levels of complexity and customization.
 */
@interface CactusFrameworkUsageExample : NSObject <CactusFrameworkDelegate>

// MARK: - Basic Usage Examples

/**
 * Example 1: Quick setup for simple chat
 * This is the easiest way to get started with chat functionality
 */
+ (void)example1_QuickChatSetup;

/**
 * Example 2: Simple text completion
 * Shows how to use the framework for text completion tasks
 */
+ (void)example2_SimpleCompletion;

/**
 * Example 3: Custom configuration
 * Demonstrates how to configure the model with custom parameters
 */
+ (void)example3_CustomConfiguration;

// MARK: - Advanced Usage Examples

/**
 * Example 4: Session management
 * Shows how to manage multiple chat sessions
 */
+ (void)example4_SessionManagement;

/**
 * Example 5: Streaming responses
 * Demonstrates real-time token streaming
 */
+ (void)example5_StreamingResponses;

/**
 * Example 6: Multimodal processing
 * Shows how to process images and audio with text
 */
+ (void)example6_MultimodalProcessing;

// MARK: - Advanced Features

/**
 * Example 7: LoRA adapters
 * Demonstrates how to apply and manage LoRA adapters
 */
+ (void)example7_LoRAAdapters;

/**
 * Example 8: Benchmarking
 * Shows how to benchmark model performance
 */
+ (void)example8_Benchmarking;

/**
 * Example 9: Background processing
 * Demonstrates advanced background task management
 */
+ (void)example9_BackgroundProcessing;

// MARK: - Production Examples

/**
 * Example 10: Error handling
 * Shows comprehensive error handling patterns
 */
+ (void)example10_ErrorHandling;

/**
 * Example 11: Performance monitoring
 * Demonstrates how to monitor performance and memory usage
 */
+ (void)example11_PerformanceMonitoring;

/**
 * Example 12: Builder pattern usage
 * Shows how to use the builder pattern for complex setups
 */
+ (void)example12_BuilderPattern;

@end

NS_ASSUME_NONNULL_END
