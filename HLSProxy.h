#import <Foundation/Foundation.h>
#import "GCDWebServer.h"

@interface HLSProxy : NSObject

- (NSString *)registerStream:(NSDictionary *)stream;
- (NSString *)playlistForToken:(NSString *)token;
- (NSDictionary *)sourceForToken:(NSString *)token;
- (void)relayToken:(NSString *)token
          request:(GCDWebServerRequest *)request
       completion:(GCDWebServerCompletionBlock)completion;
- (void)mediaForToken:(NSString *)token
              request:(GCDWebServerRequest *)request
           completion:(GCDWebServerCompletionBlock)completion;

@end