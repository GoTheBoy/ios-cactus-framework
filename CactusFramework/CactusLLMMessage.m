//
//  CactusLLMMessage.m
//  CactusFramework
//
//  Created by LAP16455 on 15/8/25.
//

#import "CactusLLMMessage.h"

CactusLLMRole const CactusLLMRoleSystem    = @"system";
CactusLLMRole const CactusLLMRoleUser      = @"user";
CactusLLMRole const CactusLLMRoleAssistant = @"assistant";
CactusLLMRole const CactusLLMRoleTool      = @"tool";

@implementation CactusLLMMessage
+ (instancetype)messageWithRole:(CactusLLMRole)role content:(NSString *)content {
    CactusLLMMessage *m = [CactusLLMMessage new];
    m.role = role;
    m.content = content ?: @"";
    return m;
}

+ (instancetype)messageWithTools:(NSDictionary *)tools content:(NSString *)content {
    CactusLLMMessage *m = [CactusLLMMessage new];
    m.role = CactusLLMRoleSystem;
    m.content = content;
    m.tools = tools;
    return m;
}

- (NSDictionary *)dictionary {
    NSDictionary *prompt = [NSDictionary dictionaryWithObjectsAndKeys:self.role, @"role", self.content, @"content", nil];
    return prompt;
}
@end
