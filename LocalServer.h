#import <Foundation/Foundation.h>

@interface LocalServer : NSObject

@property (nonatomic, readonly) NSUInteger port;
@property (nonatomic, readonly) BOOL serviceLoaded;

- (BOOL)start:(NSError **)error;

typedef void (^XuperJsonHandler)(NSString *json);

- (void)callService:(NSString *)lunaService
         parameters:(NSString *)paramsJSON
         completion:(XuperJsonHandler)completion;

@end