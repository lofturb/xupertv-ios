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
@property (nonatomic, readwrite) BOOL serviceLoaded;
@end

@implementation LocalServer {
    GCDWebServer *_web;
    GCDWebServer *_api;
}

- (BOOL)start:(NSError **)error {
    self.service = [[ServiceBridge alloc] init];
    self.serviceLoaded = [self.service load];
    if (!self.serviceLoaded) {
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

    GCDWebServerProcessBlock indexBlock = ^GCDWebServerResponse *(GCDWebServerRequest *request) {
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
        // webOSTV.js define webOS.service.request (Luna) pero en iOS no hay
        // PalmServiceBridge. Se reemplaza por un puente XHR a nuestra API 8910.
        NSString *bridge =
            @"(function(){if(!window.webOS)window.webOS={};window.PalmServiceBridge=undefined;"
             "window.webOS.service={request:function(uri,opts){opts=opts||{};"
             "var method=opts.method||'';var params=opts.parameters||{};var xhr=new XMLHttpRequest();"
             "var url='http://127.0.0.1:8910/'+encodeURIComponent(method)+'?q='+encodeURIComponent(JSON.stringify(params));"
             "var finished=false;var timer=setTimeout(function(){if(finished)return;finished=true;"
             "try{xhr.abort();}catch(e){}if(opts.onFailure)opts.onFailure({returnValue:false,errorText:'timeout'});},35000);"
             "function done(data){if(finished)return;finished=true;clearTimeout(timer);"
             "var ok=!(data&&data.returnValue===false);if(ok){if(opts.onSuccess)opts.onSuccess(data);}"
             "else{if(opts.onFailure)opts.onFailure(data);}if(opts.onComplete)opts.onComplete(data);}"
             "xhr.onreadystatechange=function(){if(xhr.readyState!==4)return;var data;"
             "try{data=JSON.parse(xhr.responseText);}catch(e){data={returnValue:false,errorText:xhr.responseText};}done(data);};"
             "xhr.onerror=function(){done({returnValue:false,errorText:'network'});};"
             "xhr.open('GET',url,true);xhr.send(null);"
             "return {cancel:function(){finished=true;clearTimeout(timer);try{xhr.abort();}catch(e){}}};}};})();";
        NSString *tag = [NSString stringWithFormat:
            @"<script src=\"js/webOSTV.js\"></script><script>%@</script>", bridge];
        [html replaceOccurrencesOfString:@"<script src=\"js/webOSTV.js\"></script>"
                              withString:tag
                                 options:0
                                   range:NSMakeRange(0, html.length)];

        // iOS 9 / A5: sin transiciones ni sombras, y scroll con inercia.
        NSString *perf =
            @"<style id='xuper-ios-perf'>"
             "*{transition:none!important;animation:none!important;box-shadow:none!important;text-shadow:none!important;}"
             "html,body,.scrollable,[class*='rail']{-webkit-overflow-scrolling:touch;}"
             "</style>";
        [html replaceOccurrencesOfString:@"</head>"
                              withString:[perf stringByAppendingString:@"</head>"]
                                 options:0
                                   range:NSMakeRange(0, html.length)];

        // El snapshot del portal trae ~270 tarjetas; en el A5 basta con 90.
        NSString *trim =
            @"<script>(function(){try{var P=window.XUPERTV_PORTAL;if(!P||!P.items||P.items.length<=90)return;"
             "var seen={},out=[],i,it,r,c;for(i=0;i<P.items.length&&out.length<90;i++){"
             "it=P.items[i]||{};r=String(it.row||it.category||'');c=seen[r]||0;"
             "if(c<8){seen[r]=c+1;out.push(it);}}P.items=out;}catch(e){}})();</script>";
        [html replaceOccurrencesOfString:@"<script src=\"data/portal.js\"></script>"
                              withString:[@"<script src=\"data/portal.js\"></script>" stringByAppendingString:trim]
                                 options:0
                                   range:NSMakeRange(0, html.length)];
        return [GCDWebServerDataResponse responseWithHTML:html];
    };

    [_web addGETHandlerForBasePath:@"/"
                       directoryPath:webRoot
                       indexFilename:nil
                            cacheAge:0
                allowRangeRequests:YES];
    // GCDWebServer inserta cada handler al principio: el index debe ir al final
    // para tener prioridad sobre el handler generico de archivos.
    [_web addHandlerForMethod:@"GET"
                         path:@"/index.html"
                 requestClass:[GCDWebServerRequest class]
                 processBlock:indexBlock];

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
    self.hls = [[HLSProxy alloc] init];
    __weak typeof(self) weakSelf = self;

    [_api addHandlerForMethod:@"GET"
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
    [_api addHandlerForMethod:@"GET"
                    pathRegex:@"/media/[A-Za-z0-9]+\\.ts"
                 requestClass:[GCDWebServerRequest class]
             asyncProcessBlock:^(GCDWebServerRequest *request, GCDWebServerCompletionBlock completion) {
        NSString *token = [request.path.lastPathComponent stringByDeletingPathExtension];
        [weakSelf.hls mediaForToken:token request:request completion:completion];
    }];
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
        if ([name isEqualToString:@"resolve"] || [name isEqualToString:@"resolveSmooth"]) {
            NSString *codec = [out[@"codec"] isKindOfClass:[NSString class]]
                ? [out[@"codec"] uppercaseString] : @"";
            if ([codec containsString:@"265"] || [codec containsString:@"HEVC"]) {
                completion([weakSelf json:@{@"returnValue": @NO,
                                            @"errorText": @"Este titulo solo esta en HEVC; el iPad mini 1 no puede decodificarlo."}]);
                return;
            }
            NSString *token = [weakSelf.hls registerStream:(NSDictionary *)data];
            if (!token) {
                completion([weakSelf json:@{@"returnValue": @NO,
                                            @"errorText": @"el portal no devolvio URL de video"}]);
                return;
            }
            NSString *local = [NSString stringWithFormat:@"http://127.0.0.1:8910/hls/%@.m3u8", token];
            out[@"url"] = local;
            out[@"proxyPath"] = local;
            out[@"isHls"] = @YES;
            out[@"mime"] = @"application/vnd.apple.mpegurl";
            if (!out[@"codec"]) out[@"codec"] = @"H264";
        }
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