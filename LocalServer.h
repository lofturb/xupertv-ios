#import <Foundation/Foundation.h>

@interface LocalServer : NSObject

@property (nonatomic, readonly) NSUInteger port;

- (BOOL)start:(NSError **)error;

@end