//
//  CactusLLMTools.h
//  CactusFramework
//
//  Created by LAP16455 on 15/8/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CactusLLMTools : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *desc;
@property (nonatomic, strong) NSDictionary *parametersJSONSchema; // JSON Schema dạng NSDictionary
@end

NS_ASSUME_NONNULL_END
