#import "LocalServer.h"
#import "GCDWebServer.h"
#import "GCDWebServerDataResponse.h"

@implementation LocalServer {
    GCDWebServer *_server;
}

- (BOOL)start:(NSError **)error {
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
    _server = [[GCDWebServer alloc] init];

    [_server addHandlerForMethod:@"GET"
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

    [_server addGETHandlerForBasePath:@"/"
                          directoryPath:webRoot
                          indexFilename:nil
                               cacheAge:0
                   allowRangeRequests:YES];

    NSArray *ports = @[@8080, @8081, @0];
    NSError *lastError = nil;
    for (NSNumber *port in ports) {
        NSDictionary *options = @{
            GCDWebServerOption_Port: port,
            GCDWebServerOption_BindToLocalhost: @YES,
            GCDWebServerOption_AutomaticallySuspendInBackground: @NO
        };
        if ([_server startWithOptions:options error:&lastError]) {
            _port = _server.port;
            NSLog(@"[xuper-ios] web en 127.0.0.1:%lu", (unsigned long)_port);
            return YES;
        }
        NSLog(@"[xuper-ios] puerto %@ ocupado: %@", port, lastError.localizedDescription);
    }
    if (error) *error = lastError;
    _server = nil;
    return NO;
}

@end