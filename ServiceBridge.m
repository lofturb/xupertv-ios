#import "ServiceBridge.h"
#import <JavaScriptCore/JavaScriptCore.h>
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#import <string.h>
#import <stdio.h>

@interface ServiceBridge () <NSURLSessionDelegate>
@property (nonatomic, strong) JSContext *context;
@property (nonatomic, strong) NSMutableDictionary *pending;
@property (nonatomic, strong) NSMutableDictionary *tasks;
@property (nonatomic, strong) NSMutableSet *cancelledTimers;
@property (nonatomic, strong) JSValue *httpDone;
@property (nonatomic, strong) JSValue *timerFire;
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation ServiceBridge

- (instancetype)init {
    self = [super init];
    if (self) {
        _pending = [NSMutableDictionary dictionary];
        _tasks = [NSMutableDictionary dictionary];
        _cancelledTimers = [NSMutableSet set];
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        cfg.timeoutIntervalForRequest = 30.0;
        _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    }
    return self;
}

- (BOOL)load {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *shimsPath = [bundle pathForResource:@"shims" ofType:@"js" inDirectory:@"service"];
    NSString *magisPath = [bundle pathForResource:@"magis" ofType:@"js" inDirectory:@"service"];
    NSString *seedsPath = [bundle pathForResource:@"seeds-fallback" ofType:@"json" inDirectory:@"service"];
    if (!shimsPath || !magisPath || !seedsPath) {
        NSLog(@"[xuper-ios] faltan recursos de servicio (%@, %@, %@)", shimsPath, magisPath, seedsPath);
        return NO;
    }
    NSString *shims = [NSString stringWithContentsOfFile:shimsPath encoding:NSUTF8StringEncoding error:NULL];
    NSString *magis = [NSString stringWithContentsOfFile:magisPath encoding:NSUTF8StringEncoding error:NULL];
    NSString *seeds = [NSString stringWithContentsOfFile:seedsPath encoding:NSUTF8StringEncoding error:NULL];
    if (!shims || !magis || !seeds) return NO;

    self.context = [[JSContext alloc] init];
    __weak typeof(self) weakSelf = self;
    self.context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) {
        NSLog(@"[xuper-ios] JS exception: %@", [exception toString]);
    };

    self.context[@"__native3DES"] = ^NSString *(NSString *b64, NSString *keyHex, NSNumber *encrypt) {
        return [weakSelf threeDES:b64 keyHex:keyHex encrypt:encrypt.boolValue] ?: @"";
    };
    self.context[@"__nativeDigest"] = ^NSString *(NSString *b64, NSString *alg) {
        return [weakSelf digest:b64 alg:alg] ?: @"";
    };
    self.context[@"__nativeRandom"] = ^NSString *(NSNumber *n) {
        int len = n.intValue; if (len <= 0) len = 16;
        uint8_t *buf = malloc((size_t)len);
        SecRandomCopyBytes(kSecRandomDefault, (size_t)len, buf);
        NSData *data = [NSData dataWithBytes:buf length:(NSUInteger)len];
        free(buf);
        return [data base64EncodedStringWithOptions:0];
    };
    self.context[@"__nativeHTTP"] = ^(NSString *opts, NSString *body, NSString *sid) {
        [weakSelf http:opts body:body sid:sid];
    };
    self.context[@"__nativeAbort"] = ^(NSString *sid) {
        NSURLSessionDataTask *task = weakSelf.tasks[@([sid longLongValue])];
        if (task) { [task cancel]; [weakSelf.tasks removeObjectForKey:@([sid longLongValue])]; }
    };
    self.context[@"__nativeTimer"] = ^(NSNumber *ms, NSString *sid) {
        [weakSelf timer:ms sid:sid];
    };
    self.context[@"__nativeCancelTimer"] = ^(NSString *sid) {
        [weakSelf.cancelledTimers addObject:sid];
    };
    self.context[@"__nativeLog"] = ^(id msg) {
        NSLog(@"[xuper-js] %@", msg);
    };
    self.context[@"__deliver"] = ^(NSString *token, NSString *error, NSString *data) {
        [weakSelf deliver:token error:error data:data];
    };

    [self.context evaluateScript:shims];
    if (self.context.exception) {
        NSLog(@"[xuper-ios] error cargando shims: %@", [self.context.exception toString]);
        return NO;
    }
    [self.context evaluateScript:[NSString stringWithFormat:@"__seedsFallbackSet(%@);", seeds]];
    [self.context evaluateScript:magis];
    if (self.context.exception) {
        NSLog(@"[xuper-ios] error cargando magis: %@", [self.context.exception toString]);
        return NO;
    }
    JSValue *loaded = [self.context evaluateScript:@"__magisLoaded()"];
    if (![loaded toBool]) {
        NSLog(@"[xuper-ios] magis no expone home/search/detail/resolve");
        return NO;
    }
    self.httpDone = self.context[@"__httpDone"];
    self.timerFire = self.context[@"__timerFire"];
    if (!self.httpDone || !self.timerFire) {
        NSLog(@"[xuper-ios] faltan callbacks JS (httpDone/timerFire)");
        return NO;
    }
    NSLog(@"[xuper-ios] servicio JS cargado");
    return YES;
}

- (void)invoke:(NSString *)method params:(NSDictionary *)params completion:(XuperServiceCompletion)completion {
    if (!completion) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self invoke:method params:params completion:completion];
        });
        return;
    }
    if (!self.context) {
        completion([NSError errorWithDomain:@"XuperTV" code:1 userInfo:@{NSLocalizedDescriptionKey: @"servicio JS no cargado"}], nil);
        return;
    }
    NSString *token = [[NSUUID UUID] UUIDString];
    self.pending[token] = [completion copy];
    NSData *pdata = [NSJSONSerialization dataWithJSONObject:params ?: @{} options:0 error:NULL];
    NSString *pjson = pdata ? [[NSString alloc] initWithData:pdata encoding:NSUTF8StringEncoding] : @"{}";
    JSValue *fn = self.context[@"__serviceInvoke"];
    if (!fn) {
        [self.pending removeObjectForKey:token];
        completion([NSError errorWithDomain:@"XuperTV" code:1 userInfo:@{NSLocalizedDescriptionKey: @"servicio JS sin __serviceInvoke"}], nil);
        return;
    }
    [fn callWithArguments:@[method ?: @"", pjson, token]];
    if (self.context.exception) {
        NSLog(@"[xuper-ios] JS invoke: %@", [self.context.exception toString]);
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(35.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        XuperServiceCompletion cb = weakSelf.pending[token];
        if (cb) {
            [weakSelf.pending removeObjectForKey:token];
            cb([NSError errorWithDomain:@"XuperTV" code:2 userInfo:@{NSLocalizedDescriptionKey: @"el portal no respondio a tiempo"}], nil);
        }
    });
}

- (void)deliver:(NSString *)token error:(NSString *)error data:(NSString *)dataJSON {
    XuperServiceCompletion cb = self.pending[token];
    if (!cb) return;
    [self.pending removeObjectForKey:token];
    if (error.length) {
        cb([NSError errorWithDomain:@"XuperTV" code:1 userInfo:@{NSLocalizedDescriptionKey: error}], nil);
        return;
    }
    id data = nil;
    if (dataJSON.length) {
        NSData *d = [dataJSON dataUsingEncoding:NSUTF8StringEncoding];
        data = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
    }
    cb(nil, data);
}

- (void)http:(NSString *)optsJSON body:(NSString *)bodyB64 sid:(NSString *)sid {
    NSData *od = [optsJSON dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *opts = od ? [NSJSONSerialization JSONObjectWithData:od options:0 error:NULL] : nil;
    NSString *url = opts[@"url"];
    if (!url.length) {
        [self httpDoneFor:sid status:-1 headers:@"{}" body:@""];
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    double ms = [opts[@"timeout"] doubleValue];
    req.timeoutInterval = ms > 0 ? ms / 1000.0 : 25.0;
    req.HTTPMethod = opts[@"method"] ?: @"GET";
    NSDictionary *headers = opts[@"headers"];
    if ([headers isKindOfClass:[NSDictionary class]]) {
        for (id key in headers) {
            [req setValue:[headers[key] description] forHTTPHeaderField:[key description]];
        }
    }
    NSData *body = bodyB64.length ? [[NSData alloc] initWithBase64EncodedString:bodyB64 options:0] : nil;
    if (body.length) req.HTTPBody = body;
    NSNumber *tid = @([sid longLongValue]);
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!self.tasks[tid]) return;
        [self.tasks removeObjectForKey:tid];
        if (error) {
            [self httpDoneFor:sid status:-1 headers:@"{}" body:@""];
            return;
        }
        NSHTTPURLResponse *hr = (NSHTTPURLResponse *)response;
        NSMutableDictionary *hs = [NSMutableDictionary dictionary];
        for (id key in hr.allHeaderFields) {
            hs[[key description]] = [hr.allHeaderFields[key] description];
        }
        NSData *hdata = [NSJSONSerialization dataWithJSONObject:hs options:0 error:NULL];
        NSString *hjson = hdata ? [[NSString alloc] initWithData:hdata encoding:NSUTF8StringEncoding] : @"{}";
        NSString *b64 = [(data ?: [NSData data]) base64EncodedStringWithOptions:0];
        [self httpDoneFor:sid status:hr.statusCode headers:hjson body:b64];
    }];
    self.tasks[tid] = task;
    [task resume];
}

- (void)httpDoneFor:(NSString *)sid status:(NSInteger)status headers:(NSString *)headers body:(NSString *)body {
    if (!self.httpDone) return;
    @try {
        [self.httpDone callWithArguments:@[sid ?: @"", @(status), headers ?: @"{}", body ?: @""]];
    } @catch (NSException *ex) {
        NSLog(@"[xuper-ios] httpDone exception: %@", ex);
    }
}

- (void)timer:(NSNumber *)ms sid:(NSString *)sid {
    int64_t delay = (int64_t)(MAX(0, ms.doubleValue) * NSEC_PER_MSEC);
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay), dispatch_get_main_queue(), ^{
        if ([weakSelf.cancelledTimers containsObject:sid]) {
            [weakSelf.cancelledTimers removeObject:sid];
            return;
        }
        @try {
            [weakSelf.timerFire callWithArguments:@[sid]];
        } @catch (NSException *ex) {
            NSLog(@"[xuper-ios] timerFire exception: %@", ex);
        }
    });
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

- (NSString *)threeDES:(NSString *)b64 keyHex:(NSString *)keyHex encrypt:(BOOL)encrypt {
    NSData *input = [[NSData alloc] initWithBase64EncodedString:b64 ?: @"" options:0];
    NSData *key = [self dataFromHex:keyHex ?: @""];
    if (!input || key.length != kCCKeySize3DES) return @"";
    size_t outLength = 0;
    size_t bufferLength = input.length + kCCBlockSize3DES;
    uint8_t *buffer = malloc(bufferLength);
    if (!buffer) return @"";
    CCCryptorStatus status = CCCrypt(encrypt ? kCCEncrypt : kCCDecrypt,
                                     kCCAlgorithm3DES,
                                     kCCOptionECBMode | kCCOptionPKCS7Padding,
                                     key.bytes, key.length, NULL,
                                     input.bytes, input.length,
                                     buffer, bufferLength, &outLength);
    NSData *out = status == kCCSuccess ? [NSData dataWithBytes:buffer length:outLength] : [NSData data];
    free(buffer);
    return [out base64EncodedStringWithOptions:0];
}

- (NSString *)digest:(NSString *)b64 alg:(NSString *)alg {
    NSData *input = [[NSData alloc] initWithBase64EncodedString:b64 ?: @"" options:0];
    if (!input) return @"";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    NSUInteger len = 0;
    NSString *a = [alg lowercaseString];
    if ([a isEqualToString:@"sha1"]) {
        CC_SHA1(input.bytes, (CC_LONG)input.length, digest);
        len = CC_SHA1_DIGEST_LENGTH;
    } else if ([a isEqualToString:@"sha256"]) {
        CC_SHA256(input.bytes, (CC_LONG)input.length, digest);
        len = CC_SHA256_DIGEST_LENGTH;
    } else {
        CC_MD5(input.bytes, (CC_LONG)input.length, digest);
        len = CC_MD5_DIGEST_LENGTH;
    }
    NSData *out = [NSData dataWithBytes:digest length:len];
    return [out base64EncodedStringWithOptions:0];
}

- (NSData *)dataFromHex:(NSString *)hex {
    NSMutableData *data = [NSMutableData data];
    const char *chars = [hex UTF8String];
    NSUInteger len = strlen(chars);
    unsigned int byte = 0;
    for (NSUInteger i = 0; i + 1 < len; i += 2) {
        sscanf(chars + i, "%2x", &byte);
        uint8_t b = (uint8_t)byte;
        [data appendBytes:&b length:1];
    }
    return data;
}

- (void)dealloc {
    [_session invalidateAndCancel];
}

@end