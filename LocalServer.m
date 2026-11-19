#import "LocalServer.h"
#import "ServiceBridge.h"
#import "HLSProxy.h"
#import "GCDWebServer.h"
#import "GCDWebServerDataResponse.h"
#import "GCDWebServerRequest.h"
#import "GCDWebServerResponse.h"

@interface LocalServer ()
@property (nonatomic, strong) ServiceBridge *service;
@property (nonatomic, strong) HLSProxy *hls;
@property (nonatomic, readwrite) NSUInteger port;
@property (nonatomic, readwrite) BOOL serviceLoaded;
@end

@implementation LocalServer

- (BOOL)start:(NSError **)error {
    self.service = [[ServiceBridge alloc] init];
    self.serviceLoaded = [self.service load];
    if (!self.serviceLoaded) {
        NSLog(@"[xuper-ios] aviso: el servicio JS no cargo; se usara el catalogo empaquetado");
    }

    self.hls = [[HLSProxy alloc] init];
    GCDWebServer *gws = [[GCDWebServer alloc] init];
    __weak typeof(self) weakSelf = self;

    /* UI propia, hecha para el iPad. Si no se encuentra, se sigue sirviendo
       el servicio: el WebView mostrara aviso en vez de pantalla negra. */
    NSString *uiIndex = [[NSBundle mainBundle] pathForResource:@"index"
                                                        ofType:@"html"
                                                   inDirectory:@"web"];
    NSLog(@"[xuper-ios] UI index %@", uiIndex ?: @"NO ENCONTRADO");
    if (uiIndex) {
        NSString *uiDir = [uiIndex stringByDeletingLastPathComponent];
        [gws addGETHandlerForBasePath:@"/web/"
                         directoryPath:[uiDir stringByAppendingString:@"/"]
                         indexFilename:@"index.html"
                              cacheAge:0
                   allowRangeRequests:NO];
    }

    /* Posters empaquetados (los usa la rejilla de la UI). */
    NSString *posterRoot = [[NSBundle mainBundle] pathForResource:@"posters" ofType:nil];
    if (!posterRoot) {
        posterRoot = [[NSBundle mainBundle] pathForResource:@"posters"
                                                     ofType:nil
                                                inDirectory:@"Resources"];
    }
    NSLog(@"[xuper-ios] posters %@", posterRoot ?: @"NO ENCONTRADOS");
    if (posterRoot) {
        [gws addGETHandlerForBasePath:@"/posters/"
                         directoryPath:[posterRoot stringByAppendingString:@"/"]
                         indexFilename:nil
                              cacheAge:86400
                   allowRangeRequests:NO];
    }

    /* Proxy de video: playlist y segmentos TS del CDN con sus cabeceras. */
    [gws addHandlerForMethod:@"GET"
                   pathRegex:@"/hls/[A-Za-z0-9]+\\.m3u8"
                requestClass:[GCDWebServerRequest class]
                processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        NSString *token = [request.path.lastPathComponent stringByDeletingPathExtension];
        NSString *playlist = [weakSelf.hls playlistForToken:token];
        if (!playlist) return [GCDWebServerResponse responseWithStatusCode:404];
        GCDWebServerDataResponse *r = [GCDWebServerDataResponse responseWithData:
            [playlist dataUsingEncoding:NSUTF8StringEncoding]
            contentType:@"application/vnd.apple.mpegurl"];
        [weakSelf addCORS:r];
        [r setValue:@"no-store" forAdditionalHeader:@"Cache-Control"];
        return r;
    }];
    [gws addHandlerForMethod:@"GET"
                   pathRegex:@"/media/[A-Za-z0-9]+\\.ts"
                requestClass:[GCDWebServerRequest class]
            asyncProcessBlock:^(GCDWebServerRequest *request,
                                GCDWebServerCompletionBlock completion) {
        NSString *token = [request.path.lastPathComponent stringByDeletingPathExtension];
        [weakSelf.hls mediaForToken:token request:request completion:completion];
    }];

    [gws addDefaultHandlerForMethod:@"OPTIONS"
                        requestClass:[GCDWebServerRequest class]
                        processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        GCDWebServerResponse *r = [GCDWebServerResponse responseWithStatusCode:204];
        [weakSelf addCORS:r];
        return r;
    }];

    NSArray *methods = @[@"ping", @"home", @"search", @"detail", @"resolve", @"resolveSmooth",
                         @"history", @"mediaInfo", @"liveChannels", @"liveCategories",
                         @"resolveLive", @"fetchM3u", @"abortMedia", @"prewarm", @"checkUpdate",
                         @"netdiag", @"setProxy", @"keepAlive", @"heartbeat", @"liveLog"];
    for (NSString *name in methods) {
        NSString *path = [@"/" stringByAppendingString:name];
        [gws addHandlerForMethod:@"GET"
                            path:path
                    requestClass:[GCDWebServerRequest class]
                asyncProcessBlock:^(GCDWebServerRequest *request,
                                    GCDWebServerCompletionBlock completion) {
            [weakSelf handleMethod:name request:request completion:completion];
        }];
    }

    NSError *lastError = nil;
    NSDictionary *opts = @{
        GCDWebServerOption_Port: @8910,
        GCDWebServerOption_BindToLocalhost: @YES,
        GCDWebServerOption_AutomaticallySuspendInBackground: @NO
    };
    if (![gws startWithOptions:opts error:&lastError]) {
        NSLog(@"[xuper-ios] 8910 ocupado (%@); uso puerto efimero", lastError.localizedDescription);
        opts = @{
            GCDWebServerOption_Port: @0,
            GCDWebServerOption_BindToLocalhost: @YES,
            GCDWebServerOption_AutomaticallySuspendInBackground: @NO
        };
        if (![gws startWithOptions:opts error:&lastError]) {
            if (error) *error = lastError;
            return NO;
        }
    }
    self.port = gws.port;
    NSLog(@"[xuper-ios] UI + API en 127.0.0.1:%lu", (unsigned long)self.port);
    return YES;
}

- (void)handleMethod:(NSString *)name
             request:(GCDWebServerRequest *)request
          completion:(GCDWebServerCompletionBlock)completion {
    NSDictionary *params = [self paramsFromRequest:request];
    [self runMethod:name params:params completion:^(NSDictionary *out) {
        completion([self json:out]);
    }];
}

- (NSString *)localPlaylistForRemote:(NSString *)remoteURL
                             headers:(NSDictionary *)headers {
    if (!remoteURL.length || !self.hls) return nil;
    NSString *token = [self.hls registerStream:@{ @"url": remoteURL,
                                                 @"headers": headers ?: @{},
                                                 @"duration": @0 }];
    if (!token.length) return nil;
    return [NSString stringWithFormat:@"http://127.0.0.1:%lu/hls/%@.m3u8",
            (unsigned long)self.port, token];
}

- (void)callService:(NSString *)lunaService
         parameters:(NSString *)paramsJSON
         completion:(XuperJsonHandler)completion {
    if (!completion) return;
    NSString *method = [lunaService lastPathComponent];
    NSDictionary *parsed = [self paramsFromQuery:paramsJSON];
    [self runMethod:method params:(parsed ?: @{}) completion:^(NSDictionary *out) {
        NSData *d = [NSJSONSerialization dataWithJSONObject:out options:0 error:NULL];
        completion(d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"{}");
    }];
}

- (void)runMethod:(NSString *)name
           params:(NSDictionary *)params
       completion:(void (^)(NSDictionary *out))completion {
    void (^reply)(NSDictionary *) = ^(NSDictionary *d) { completion(d ?: @{}); };
    if ([name isEqualToString:@"ping"]) {
        reply(@{@"returnValue": @YES,
                @"service": @"com.webosflux.xupertv.ios",
                @"version": @"1.0.0",
                @"platform": @"ios-armv7"});
        return;
    }
    if ([name isEqualToString:@"liveChannels"]) { reply(@{@"returnValue": @YES, @"channels": @[]}); return; }
    if ([name isEqualToString:@"liveCategories"]) { reply(@{@"returnValue": @YES, @"categories": @[]}); return; }
    if ([name isEqualToString:@"resolveLive"]) {
        reply(@{@"returnValue": @NO, @"errorText": @"TV en vivo no disponible en esta version"});
        return;
    }
    if ([name isEqualToString:@"abortMedia"] || [name isEqualToString:@"prewarm"] ||
        [name isEqualToString:@"setProxy"] || [name isEqualToString:@"keepAlive"] ||
        [name isEqualToString:@"heartbeat"] || [name isEqualToString:@"liveLog"]) {
        reply(@{@"returnValue": @YES});
        return;
    }
    if ([name isEqualToString:@"checkUpdate"]) { reply(@{@"returnValue": @YES, @"hasUpdate": @NO}); return; }
    if ([name isEqualToString:@"netdiag"]) { reply(@{@"returnValue": @YES, @"ok": @YES}); return; }
    if (!self.service) {
        reply(@{@"returnValue": @NO, @"errorText": @"servicio no cargado"});
        return;
    }

    NSString *callName = name;
    if ([name isEqualToString:@"resolveSmooth"]) callName = @"resolve";
    __weak typeof(self) weakSelf = self;
    [self.service invoke:callName params:params completion:^(NSError *error, id data) {
        if (error) {
            NSLog(@"[xuper-ios] %@: %@", name, error.localizedDescription);
            reply(@{@"returnValue": @NO, @"errorText": error.localizedDescription ?: @"error"});
            return;
        }
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        if ([data isKindOfClass:[NSDictionary class]]) [out addEntriesFromDictionary:data];
        if ([name isEqualToString:@"resolve"] || [name isEqualToString:@"resolveSmooth"]) {
            NSDictionary *src = [data isKindOfClass:[NSDictionary class]] ? data : nil;
            NSString *srcUrl = src[@"url"];
            if ([srcUrl isKindOfClass:[NSString class]] && srcUrl.length) out[@"remoteUrl"] = srcUrl;
            NSDictionary *srcHeaders = src[@"headers"];
            if ([srcHeaders isKindOfClass:[NSDictionary class]]) out[@"remoteHeaders"] = srcHeaders;
            NSString *token = [weakSelf.hls registerStream:src ?: @{}];
            if (!token) {
                reply(@{@"returnValue": @NO, @"errorText": @"el portal no devolvio URL de video"});
                return;
            }
            NSString *local = [NSString stringWithFormat:@"http://127.0.0.1:%lu/hls/%@.m3u8",
                               (unsigned long)weakSelf.port, token];
            out[@"url"] = local;
            out[@"proxyPath"] = local;
            out[@"isHls"] = @YES;
            out[@"mime"] = @"application/vnd.apple.mpegurl";
            if (!out[@"codec"]) out[@"codec"] = @"H264";
        }
        out[@"returnValue"] = @YES;
        reply(out);
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
    NSArray *numbers = @[@"pageNum", @"trackIndex", @"audioTrack", @"duration",
                         @"resumePosition", @"position", @"season"];
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

- (NSDictionary *)paramsFromQuery:(NSString *)json {
    if (!json.length) return @{};
    NSData *d = [json dataUsingEncoding:NSUTF8StringEncoding];
    id obj = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    if ([obj isKindOfClass:[NSDictionary class]]) return obj;
    return @{};
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

