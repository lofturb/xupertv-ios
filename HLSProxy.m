#import "HLSProxy.h"
#import "GCDWebServerFileResponse.h"
#import "GCDWebServerResponse.h"
#import <UIKit/UIKit.h>

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
        cfg.HTTPMaximumConnectionsPerHost = 2;
        _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    }
    return self;
}

- (NSString *)registerStream:(NSDictionary *)stream {
    NSString *url = stream[@"url"];
    if (!url.length) return nil;
    NSString *token = [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
    NSString *file = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"xuper-%@.ts", token]];
    [self cleanupExcept:file];
    NSMutableDictionary *s = [NSMutableDictionary dictionary];
    s[@"url"] = url;
    s[@"headers"] = [stream[@"headers"] isKindOfClass:[NSDictionary class]] ? stream[@"headers"] : @{};
    s[@"duration"] = stream[@"duration"] ?: @0;
    s[@"file"] = file;
    s[@"state"] = @0;
    s[@"waiters"] = [NSMutableArray array];
    self.streams[token] = s;
    [self downloadToken:token];
    return token;
}

- (NSString *)playlistForToken:(NSString *)token {
    NSDictionary *s = self.streams[token];
    if (!s) return nil;
    double duration = [s[@"duration"] doubleValue];
    if (duration <= 0) duration = 3600.0;
    long target = (long)ceil(duration);
    if (target < 1) target = 1;
    return [NSString stringWithFormat:
            @"#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:%ld\n"
            "#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-PLAYLIST-TYPE:VOD\n"
            "#EXTINF:%.3f,\n/media/%@.ts\n#EXT-X-ENDLIST\n",
            target, duration, token];
}

- (void)mediaForToken:(NSString *)token
              request:(GCDWebServerRequest *)request
           completion:(GCDWebServerCompletionBlock)completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableDictionary *s = self.streams[token];
        if (!s) {
            completion([GCDWebServerResponse responseWithStatusCode:404]);
            return;
        }
        int state = [s[@"state"] intValue];
        if (state == 1 && [[NSFileManager defaultManager] fileExistsAtPath:s[@"file"]]) {
            completion([self responseForToken:token request:request]);
            return;
        }
        if (state == 2) {
            completion([GCDWebServerResponse responseWithStatusCode:502]);
            return;
        }
        [s[@"waiters"] addObject:@[request, [completion copy]]];
        NSLog(@"[xuper-ios] media %@ aun descargando (%lu en espera)", token,
              (unsigned long)[s[@"waiters"] count]);
    });
}

- (GCDWebServerResponse *)responseForToken:(NSString *)token request:(GCDWebServerRequest *)request {
    NSDictionary *s = self.streams[token];
    if (!s) return [GCDWebServerResponse responseWithStatusCode:404];
    NSString *file = s[@"file"];
    GCDWebServerFileResponse *r = request.hasByteRange
        ? [GCDWebServerFileResponse responseWithFile:file byteRange:request.byteRange]
        : [GCDWebServerFileResponse responseWithFile:file];
    r.contentType = @"video/mp2t";
    [r setValue:@"*" forAdditionalHeader:@"Access-Control-Allow-Origin"];
    return r;
}

- (void)downloadToken:(NSString *)token {
    NSMutableDictionary *s = self.streams[token];
    if (!s) return;
    NSString *url = s[@"url"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    req.timeoutInterval = 3600.0;
    NSDictionary *headers = s[@"headers"];
    for (NSString *key in headers) {
        [req setValue:[headers[key] description] forHTTPHeaderField:key];
    }
    NSLog(@"[xuper-ios] descargando media %@", token);
    NSURLSessionDownloadTask *task = [self.session downloadTaskWithRequest:req
        completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableDictionary *cur = self.streams[token];
            if (!cur) return;
            if (error || !location) {
                NSLog(@"[xuper-ios] media %@ fallo: %@", token, error.localizedDescription);
                cur[@"state"] = @2;
                [self flushToken:token status:502];
                return;
            }
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *dest = cur[@"file"];
            [fm removeItemAtPath:dest error:NULL];
            NSError *moveError = nil;
            [fm moveItemAtURL:location toURL:[NSURL fileURLWithPath:dest] error:&moveError];
            if (moveError) {
                NSLog(@"[xuper-ios] media %@ no se pudo mover: %@", token, moveError.localizedDescription);
                cur[@"state"] = @2;
                [self flushToken:token status:502];
                return;
            }
            unsigned long long size = [[[NSFileManager defaultManager] attributesOfItemAtPath:dest error:NULL] fileSize];
            NSLog(@"[xuper-ios] media %@ lista (%llu bytes)", token, size);
            cur[@"state"] = @1;
            [self flushToken:token status:0];
        });
    }];
    [task resume];
}

- (void)flushToken:(NSString *)token status:(NSInteger)status {
    NSMutableDictionary *s = self.streams[token];
    if (!s) return;
    NSArray *waiters = [s[@"waiters"] copy];
    [s[@"waiters"] removeAllObjects];
    for (NSArray *pair in waiters) {
        GCDWebServerRequest *request = pair[0];
        GCDWebServerCompletionBlock completion = pair[1];
        if (status) {
            completion([GCDWebServerResponse responseWithStatusCode:status]);
        } else {
            completion([self responseForToken:token request:request]);
        }
    }
}

- (void)cleanupExcept:(NSString *)keep {
    NSString *tmp = NSTemporaryDirectory();
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tmp error:NULL];
    for (NSString *name in files) {
        if (![name hasPrefix:@"xuper-"] || ![name hasSuffix:@".ts"]) continue;
        NSString *path = [tmp stringByAppendingPathComponent:name];
        if (![path isEqualToString:keep]) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        }
    }
    for (NSString *token in [self.streams allKeys]) {
        NSDictionary *s = self.streams[token];
        if (![s[@"file"] isEqualToString:keep]) [self.streams removeObjectForKey:token];
    }
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