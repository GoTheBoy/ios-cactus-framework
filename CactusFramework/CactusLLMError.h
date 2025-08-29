//
//  CactusLLMError.h
//  CactusFramework
//
//  Created by LAP16455 on 15/8/25.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, CactusLLMError) {
    CactusLLMErrorUnknown              = -1,
    CactusLLMErrorModelNotLoaded       = -2,
    CactusLLMErrorModelLoadFailed      = -3,
    CactusLLMErrorGenerationCancelled  = -4,
    CactusLLMErrorInvalidArgument      = -5,
    CactusLLMErrorBackend              = -6,
    CactusLLMErrorFileNotFound         = -7,
    CactusLLMErrorGenerationFailed     = -8,
    CactusLLMErrorMultimodalNotEnabled = -9,
    CactusLLMErrorInvalidState         = -10,
    CactusLLMErrorMultimodalInitFailed = -11,
    CactusLLMErrorLoRAApplicationFailed= -12,
    CactusLLMErrorTokenizationFailed   = -13,
    CactusLLMErrorDetokenizationFailed = -14,
    CactusLLMErrorInvalidModel         = -15
    
};

FOUNDATION_EXPORT NSString * const CactusLLMErrorDomain;
