#import "HLSProxy.h"
#import "GCDWebServerDataResponse.h"
#import "GCDWebServerResponse.h"

/* Puente de video para el iPad mini 1 (A5).
 *
 * AVPlayer solo decodifica por hardware y el A5 no tiene HEVC: los titulos
 * en H265 dan error 3 y se quedan en "Cargando". VLCKit trae decodificador
 * por CPU y si puede, pero no admite las cabeceras del portal (Content-Auth
 * y compania).
 *
 * Este objeto hace de proxy local:
 *   - registerStream guarda la URL firmada del CDN y sus cabeceras.
 *   - playlistForToken devuelve una lista HLS de un unico segmento.
 *   - mediaForToken pide el TS al CDN con esas cabeceras y lo entrega.
 * Asi VLC recibe un .ts correcto y no hace falta descargar el episodio
 * entero antes de empezar.
 */

@interface HLSProxy () <NSURLSessionDelegate>
@property (nonatomic, strong) NSMutableDictionary *streams;
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation HLSProxy

- (instancetype)init {
    self = [super init];
    if (self) {
        _streams = [NSMutableDictionary dictionary];
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 120.0;
        cfg.timeoutIntervalForResource = 600.0;
        _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
    }
    return self;
}

- (NSString *)registerStream:(NSDictionary *)stream {
    NSString *url = [stream[@"url"] description];
    if (!url.length) return nil;
    NSString *token = [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
    NSMutableDictionary *s = [NSMutableDictionary dictionary];
    s[@"url"] = url;
    s[@"headers"] = [stream[@"headers"] isKindOfClass:[NSDictionary class]] ? stream[@"headers"] : @{};
    s[@"duration"] = stream[@"duration"] ?: @0;
    self.streams[token] = s;
    return token;
}

- (NSDictionary *)sourceForToken:(NSString *)token {
    NSDictionary *s = self.streams[token];
    if (!s) return nil;
    return @{ @"url": s[@"url"] ?: @"", @"headers": s[@"headers"] ?: @{} };
}

- (NSString *)playlistForToken:(NSString *)token {
    NSDictionary *s = self.streams[token];
    if (!s) return nil;
    double duration = [s[@"duration"] doubleValue];
    if (duration <= 0) duration = 36000.0;
    long target = (long)ceil(duration);
    if (target < 10) target = 10;
    return [NSString stringWithFormat:
            @"#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-PLAYLIST-TYPE:VOD\n"
            "#EXT-X-TARGETDURATION:%ld\n#EXT-X-MEDIA-SEQUENCE:0\n"
            "#EXTINF:%.3f,\nhttp://127.0.0.1:8910/media/%@.ts\n#EXT-X-ENDLIST\n",
            target, duration, token];
}

- (void)mediaForToken:(NSString *)token
              request:(GCDWebServerRequest *)request
           completion:(GCDWebServerCompletionBlock)completion {
    NSDictionary *s = self.streams[token];
    NSString *url = s[@"url"];
    if (!url.length) {
        completion([GCDWebServerResponse responseWithStatusCode:404]);
        return;
    }
    NSMutableURLRequest *cdnReq = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    cdnReq.timeoutInterval = 600.0;
    NSString *range = request.headers[@"Range"];
    if (range.length) [cdnReq setValue:range forHTTPHeaderField:@"Range"];
    NSDictionary *hdrs = s[@"headers"];
    for (NSString *key in hdrs) {
        [cdnReq setValue:[hdrs[key] description] forHTTPHeaderField:key];
    }
    NSLog(@"[xuper-relay] %@ rango=%@", token, range ?: @"-");

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:cdnReq
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (![resp isKindOfClass:[NSHTTPURLResponse class]]) {
            NSLog(@"[xuper-relay] %@ sin respuesta: %@", token, err.localizedDescription);
            completion([GCDWebServerResponse responseWithStatusCode:502]);
            return;
        }
        NSHTTPURLResponse *hr = (NSHTTPURLResponse *)resp;
        NSData *body = data ?: [NSData data];
        NSLog(@"[xuper-relay] %@ estado=%ld bytes=%lu", token, (long)hr.statusCode,
              (unsigned long)body.length);
        GCDWebServerDataResponse *r = [GCDWebServerDataResponse responseWithData:body
                                                                    contentType:@"video/mp2t"];
        r.statusCode = hr.statusCode;
        [r setValue:@"*" forAdditionalHeader:@"Access-Control-Allow-Origin"];
        completion(r);
    }];
    [task resume];
}

- (void)relayToken:(NSString *)token
           request:(GCDWebServerRequest *)request
        completion:(GCDWebServerCompletionBlock)completion {
    [self mediaForToken:token request:request completion:completion];
}

- (void)URLSession:(NSURLSession *)session
    didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
      completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSURLCredential *cred = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, cred);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

- (void)dealloc {
    [_session invalidateAndCancel];
}

@end

