//
//  CactusLLMMessage.h
//  CactusFramework
//
//  Created by LAP16455 on 15/8/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSString * CactusLLMRole NS_TYPED_EXTENSIBLE_ENUM;
FOUNDATION_EXPORT CactusLLMRole const CactusLLMRoleSystem;
FOUNDATION_EXPORT CactusLLMRole const CactusLLMRoleUser;
FOUNDATION_EXPORT CactusLLMRole const CactusLLMRoleAssistant;
FOUNDATION_EXPORT CactusLLMRole const CactusLLMRoleTool; // cho function-calling

@interface CactusLLMMessage : NSObject
@property (nonatomic, copy) CactusLLMRole role;
@property (nonatomic, copy) NSString *content;
@property (nonatomic, strong) NSDictionary *tools;
@property (nonatomic, copy, nullable) NSString *name;     // tên tool (nếu role=tool)
@property (nonatomic, copy, nullable) NSString *toolCall; // JSON yêu cầu tool (nếu assistant sinh ra)
+ (instancetype)messageWithRole:(CactusLLMRole)role content:(NSString *)content;
+ (instancetype)messageWithTools:(NSDictionary *)tools content:(NSString *)content;
- (NSDictionary *)dictionary;
@end

NS_ASSUME_NONNULL_END
