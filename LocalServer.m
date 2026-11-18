#import "LocalServer.h"
#import "ServiceBridge.h"
#import "GCDWebServer.h"
#import "GCDWebServerDataResponse.h"
#import "GCDWebServerRequest.h"
#import "GCDWebServerResponse.h"

@interface LocalServer ()
@property (nonatomic, strong) ServiceBridge *service;
@end

@implementation LocalServer {
    GCDWebServer *_web;
    GCDWebServer *_api;
}

- (BOOL)start:(NSError **)error {
    self.service = [[ServiceBridge alloc] init];
    if (![self.service load]) {
        NSLog(@"[xuper-ios] aviso: el servicio JS no cargo; la app usara el catalogo empaquetado");
    }

    NSString *indexPath = [[NSBundle mainBundle] pathForResource:@"index"
                                                          ofType:@"html"
                                                     inDirectory:@"fidelity"];
    if (!indexPath) {
        if (error) {
            *error = [NSError errorWithDomain:@"XuperTV"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Falta Resources/fidelity/index.html"}];
        }
        return NO;
    }
    NSString *webRoot = [indexPath stringByDeletingLastPathComponent];
    _web = [[GCDWebServer alloc] init];

    [_web addHandlerForMethod:@"GET"
                         path:@"/index.html"
                 requestClass:[GCDWebServerRequest class]
                 processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        NSMutableString *html = [NSMutableString stringWithContentsOfFile:indexPath
                                                                 encoding:NSUTF8StringEncoding
                                                                    error:NULL];
        if (!html) {
            return [GCDWebServerDataResponse responseWithHTML:@"<h1>XuperTV</h1>"];
        }
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<meta[^>]*name=[\"']viewport[\"'][^>]*>"
                                                                          options:NSRegularExpressionCaseInsensitive
                                                                            error:NULL];
        [re replaceMatchesInString:html
                           options:0
                             range:NSMakeRange(0, html.length)
                      withTemplate:@"<meta name=\"viewport\" content=\"width=1920, height=1080, user-scalable=no\">"];
        return [GCDWebServerDataResponse responseWithHTML:html];
    }];

    [_web addGETHandlerForBasePath:@"/"
                       directoryPath:webRoot
                       indexFilename:nil
                            cacheAge:0
                allowRangeRequests:YES];

    NSArray *ports = @[@8080, @8081, @0];
    NSError *lastError = nil;
    BOOL webStarted = NO;
    for (NSNumber *port in ports) {
        NSDictionary *options = @{
            GCDWebServerOption_Port: port,
            GCDWebServerOption_BindToLocalhost: @YES,
            GCDWebServerOption_AutomaticallySuspendInBackground: @NO
        };
        if ([_web startWithOptions:options error:&lastError]) {
            _port = _web.port;
            webStarted = YES;
            NSLog(@"[xuper-ios] web en 127.0.0.1:%lu", (unsigned long)_port);
            break;
        }
    }
    if (!webStarted) {
        if (error) *error = lastError;
        _web = nil;
        return NO;
    }

    [self startAPI];
    return YES;
}

- (void)startAPI {
    _api = [[GCDWebServer alloc] init];
    __weak typeof(self) weakSelf = self;
    [_api addDefaultHandlerForMethod:@"OPTIONS"
                        requestClass:[GCDWebServerRequest class]
                        processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        GCDWebServerResponse *r = [GCDWebServerResponse responseWithStatusCode:204];
        [weakSelf addCORS:r];
        return r;
    }];

    NSArray *methods = @[@"ping", @"home", @"search", @"detail", @"resolve", @"resolveSmooth",
                         @"mediaInfo", @"liveChannels", @"liveCategories", @"resolveLive",
                         @"fetchM3u", @"abortMedia", @"prewarm", @"checkUpdate", @"netdiag",
                         @"setProxy", @"keepAlive", @"heartbeat", @"liveLog"];
    for (NSString *name in methods) {
        NSString *path = [@"/" stringByAppendingString:name];
        [_api addHandlerForMethod:@"GET"
                             path:path
                     requestClass:[GCDWebServerRequest class]
                 asyncProcessBlock:^(GCDWebServerRequest *request, GCDWebServerCompletionBlock completion) {
            [weakSelf handleMethod:name request:request completion:completion];
        }];
    }

    NSError *error = nil;
    NSDictionary *options = @{
        GCDWebServerOption_Port: @8910,
        GCDWebServerOption_BindToLocalhost: @YES,
        GCDWebServerOption_AutomaticallySuspendInBackground: @NO
    };
    if (![_api startWithOptions:options error:&error]) {
        NSLog(@"[xuper-ios] API 8910 no arranco: %@", error.localizedDescription);
        _api = nil;
    } else {
        NSLog(@"[xuper-ios] API en 127.0.0.1:8910");
    }
}

- (void)handleMethod:(NSString *)name
             request:(GCDWebServerRequest *)request
          completion:(GCDWebServerCompletionBlock)completion {
    if ([name isEqualToString:@"ping"]) {
        completion([self json:@{@"returnValue": @YES,
                                @"service": @"com.webosflux.xupertv.ios",
                                @"version": @"1.0.0",
                                @"platform": @"ios-armv7"}]);
        return;
    }
    if ([name isEqualToString:@"liveChannels"]) {
        completion([self json:@{@"returnValue": @YES, @"channels": @[]}]);
        return;
    }
    if ([name isEqualToString:@"liveCategories"]) {
        completion([self json:@{@"returnValue": @YES, @"categories": @[]}]);
        return;
    }
    if ([name isEqualToString:@"resolveLive"]) {
        completion([self json:@{@"returnValue": @NO, @"errorText": @"TV en vivo no disponible en esta version"}]);
        return;
    }
    if ([name isEqualToString:@"abortMedia"] || [name isEqualToString:@"prewarm"] ||
        [name isEqualToString:@"setProxy"] || [name isEqualToString:@"keepAlive"] ||
        [name isEqualToString:@"heartbeat"] || [name isEqualToString:@"liveLog"]) {
        completion([self json:@{@"returnValue": @YES}]);
        return;
    }
    if ([name isEqualToString:@"checkUpdate"]) {
        completion([self json:@{@"returnValue": @YES, @"hasUpdate": @NO}]);
        return;
    }
    if ([name isEqualToString:@"netdiag"]) {
        completion([self json:@{@"returnValue": @YES, @"ok": @YES}]);
        return;
    }
    if (!self.service) {
        completion([self json:@{@"returnValue": @NO, @"errorText": @"servicio no cargado"}]);
        return;
    }

    NSDictionary *params = [self paramsFromRequest:request];
    NSString *callName = name;
    if ([name isEqualToString:@"resolveSmooth"]) callName = @"resolve";
    __weak typeof(self) weakSelf = self;
    [self.service invoke:callName params:params completion:^(NSError *error, id data) {
        if (error) {
            NSLog(@"[xuper-ios] %@: %@", name, error.localizedDescription);
            completion([weakSelf json:@{@"returnValue": @NO,
                                        @"errorText": error.localizedDescription ?: @"error"}]);
            return;
        }
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        if ([data isKindOfClass:[NSDictionary class]]) [out addEntriesFromDictionary:data];
        out[@"returnValue"] = @YES;
        completion([weakSelf json:out]);
    }];
}

- (NSDictionary *)paramsFromRequest:(GCDWebServerRequest *)request {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSDictionary *query = request.query;
    NSString *q = query[@"q"];
    if (q.length) {
        NSData *d = [q dataUsingEncoding:NSUTF8StringEncoding];
        id obj = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
        if ([obj isKindOfClass:[NSDictionary class]]) [params addEntriesFromDictionary:obj];
    }
    for (NSString *key in query) {
        if (![key isEqualToString:@"q"]) params[key] = query[key];
    }
    NSArray *numbers = @[@"pageNum", @"trackIndex", @"audioTrack", @"duration", @"resumePosition", @"position", @"season"];
    for (NSString *key in numbers) {
        if (params[key]) params[key] = @([params[key] integerValue]);
    }
    NSArray *bools = @[@"forceRelay", @"hevc", @"uhd"];
    for (NSString *key in bools) {
        NSString *v = [params[key] isKindOfClass:[NSString class]] ? [params[key] lowercaseString] : nil;
        if ([v isEqualToString:@"true"] || [v isEqualToString:@"1"]) params[key] = @YES;
        else if ([v isEqualToString:@"false"] || [v isEqualToString:@"0"]) params[key] = @NO;
    }
    return params;
}

- (GCDWebServerResponse *)json:(NSDictionary *)object {
    GCDWebServerDataResponse *r = [GCDWebServerDataResponse responseWithJSONObject:object ?: @{}];
    [self addCORS:r];
    [r setValue:@"no-store" forAdditionalHeader:@"Cache-Control"];
    return r;
}

- (void)addCORS:(GCDWebServerResponse *)response {
    [response setValue:@"*" forAdditionalHeader:@"Access-Control-Allow-Origin"];
    [response setValue:@"GET, POST, OPTIONS" forAdditionalHeader:@"Access-Control-Allow-Methods"];
    [response setValue:@"Content-Type" forAdditionalHeader:@"Access-Control-Allow-Headers"];
}

@end