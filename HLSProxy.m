#import "HLSProxy.h"
#import "GCDWebServerDataResponse.h"
#import "GCDWebServerResponse.h"

/* Remux local del CDN para VLC.
   AVPlayer no decodifica HEVC en el A5 (error 3). VLC si, por CPU, pero no
   puede usar las cabeceras del portal (Content-Auth etc.). Por eso VLC lee
   un HLS local de un unico segmento y este servidor pide el TS al CDN con
   sus cabeceras y lo reenvia byte a byte.
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
        cfg.timeoutIntervalForRequest = 600.0;
        cfg.timeoutIntervalForResource = 3600.0;
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

    NSMutableURLRequest *reqmut = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    reqmut.timeoutInterval = 600.0;
    NSString *range = request.headers[@"Range"];
    if (range.length) [reqmut setValue:range forHTTPHeaderField:@"Range"];
    NSDictionary *headers = s[@"headers"];
    for (NSString *key in headers) {
        [reqmut setValue:[headers[key] description] forHTTPHeaderField:key];
    }
    NSLog(@"[xuper-relay] %@ rango=%@", token, range ?: @"-");

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:reqmut
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSHTTPURLResponse *hr = (NSHTTPURLResponse *)resp;
        if (err || !hr) {
            NSLog(@"[xuper-relay] %@ error %@", token, err.localizedDescription);
            completion([GCDWebServerResponse responseWithStatusCode:502]);
            return;
        }
        NSLog(@"[xuper-relay] %@ %ld %lu bytes", token, (long)hr.statusCode,
              (unsigned long)data.length);
        GCDWebServerDataResponse *r =
            [GCDWebServerDataResponse responseWithData:(data ?: [NSData data])
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
