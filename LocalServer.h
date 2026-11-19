#import <Foundation/Foundation.h>

@interface LocalServer : NSObject

@property (nonatomic, readonly) NSUInteger port;
@property (nonatomic, readonly) BOOL serviceLoaded;

- (BOOL)start:(NSError **)error;

typedef void (^XuperJsonHandler)(NSString *json);

- (void)callService:(NSString *)lunaService
         parameters:(NSString *)paramsJSON
         completion:(XuperJsonHandler)completion;

/* Registra la URL firmada del CDN y devuelve la lista HLS local que la envuelve
   (los segmentos .ts los pide este proceso con las cabeceras del portal). */
- (NSString *)localPlaylistForRemote:(NSString *)remoteURL
                             headers:(NSDictionary *)headers;

@end



