#import <Foundation/Foundation.h>
#import "GCDWebServer.h"

@interface HLSProxy : NSObject

- (NSString *)registerStream:(NSDictionary *)stream;
- (NSString *)playlistForToken:(NSString *)token;
- (void)mediaForToken:(NSString *)token
              request:(GCDWebServerRequest *)request
           completion:(GCDWebServerCompletionBlock)completion;

@end