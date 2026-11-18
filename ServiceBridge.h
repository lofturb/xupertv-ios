#import <Foundation/Foundation.h>

typedef void (^XuperServiceCompletion)(NSError *error, id data);

@interface ServiceBridge : NSObject

- (BOOL)load;
- (void)invoke:(NSString *)method params:(NSDictionary *)params completion:(XuperServiceCompletion)completion;

@end