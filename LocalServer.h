#import <Foundation/Foundation.h>

@interface LocalServer : NSObject

@property (nonatomic, readonly) NSUInteger port;
@property (nonatomic, readonly) BOOL serviceLoaded;

- (BOOL)start:(NSError **)error;

@end