#import "RootViewController.h"
#import "LocalServer.h"
#import "XuperPlayerViewController.h"
#import <WebKit/WebKit.h>

@interface RootViewController () <WKNavigationDelegate, WKScriptMessageHandler>

@property (nonatomic, strong) LocalServer *server;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UIButton *backButton;

@end

@implementation RootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    self.server = [[LocalServer alloc] init];
    NSError *error = nil;
    if (![self.server start:&error]) {
        [self showError:error.localizedDescription ?: @"No se pudo iniciar el servidor local"];
        return;
    }

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    if ([config respondsToSelector:@selector(setRequiresUserActionForMediaPlayback:)]) {
        config.requiresUserActionForMediaPlayback = NO;
    }
    WKUserContentController *uc = [[WKUserContentController alloc] init];
    [uc addUserScript:[[WKUserScript alloc] initWithSource:[self bootstrapScript]
                                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                           forMainFrameOnly:YES]];
    [uc addScriptMessageHandler:self name:@"xuperPlay"];
    [uc addScriptMessageHandler:self name:@"xuperService"];
    config.userContentController = uc;

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.navigationDelegate = self;
    self.webView.backgroundColor = [UIColor blackColor];
    self.webView.opaque = NO;
    self.webView.scrollView.bounces = NO;
    self.webView.scrollView.showsHorizontalScrollIndicator = NO;
    self.webView.scrollView.showsVerticalScrollIndicator = NO;
    if ([self.webView respondsToSelector:@selector(setAllowsBackForwardNavigationGestures:)]) {
        self.webView.allowsBackForwardNavigationGestures = NO;
    }
    [self.view addSubview:self.webView];

    [self addBackButton];

    UILabel *status = [[UILabel alloc] initWithFrame:CGRectMake(8.0, 6.0, 340.0, 18.0)];
    status.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
    status.text = [NSString stringWithFormat:@"iOS 9 armv7 | web %lu | api 8910 | js %@",
                   (unsigned long)self.server.port,
                   self.server.serviceLoaded ? @"ok" : @"fallo"];
    status.font = [UIFont systemFontOfSize:11.0];
    status.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    status.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
    [self.view addSubview:status];

    NSString *url = [NSString stringWithFormat:@"http://127.0.0.1:%lu/index.html", (unsigned long)self.server.port];
    NSLog(@"[xuper-ios] cargando %@", url);
    [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url]]];
}

- (void)addBackButton {
    self.backButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.backButton.frame = CGRectMake(self.view.bounds.size.width - 92.0, 54.0, 64.0, 48.0);
    self.backButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.backButton setTitle:@"\u2039" forState:UIControlStateNormal];
    [self.backButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.backButton.titleLabel.font = [UIFont boldSystemFontOfSize:30.0];
    self.backButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.28];
    self.backButton.layer.cornerRadius = 10.0;
    self.backButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.30].CGColor;
    self.backButton.layer.borderWidth = 1.0;
    self.backButton.alpha = 0.55;
    self.backButton.accessibilityLabel = @"Atras";
    [self.backButton addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.backButton];
}

- (void)goBack {
    NSString *js =
        @"(function(){try{if(window.__xuperNativeBack)return window.__xuperNativeBack();}catch(e){}"
         "var ev;try{ev=new KeyboardEvent('keydown',{keyCode:461,which:461,key:'GoBack',bubbles:true});}"
         "catch(e){ev=document.createEvent('Event');ev.initEvent('keydown',true,true);}"
         "try{ev.keyCode=461;ev.which=461;ev.charCode=461;}catch(e){}document.dispatchEvent(ev);"
         "try{if(window.__xuper&&window.__xuper.key)window.__xuper.key(461);}catch(e2){}})();";
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

- (void)userContentController:(WKUserContentController *)uc
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"xuperService"]) {
        [self handleServiceCall:message.body];
        return;
    }
    if (![message.name isEqualToString:@"xuperPlay"]) return;
    NSDictionary *body = [message.body isKindOfClass:[NSDictionary class]] ? message.body : nil;
    NSString *url = body[@"url"];
    if (![url isKindOfClass:[NSString class]] || !url.length) return;
    NSDictionary *headers = [body[@"headers"] isKindOfClass:[NSDictionary class]] ? body[@"headers"] : @{};
    NSLog(@"[xuper-ios] xuperPlay %@", url);
    XuperPlayerViewController *player =
        [[XuperPlayerViewController alloc] initWithURL:url headers:headers title:body[@"title"]];
    player.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:player animated:YES completion:nil];
}

- (void)handleServiceCall:(id)body {
    if (![body isKindOfClass:[NSDictionary class]]) return;
    NSString *ident = body[@"id"];
    NSString *service = body[@"service"];
    NSString *payload = body[@"payload"];
    if (![ident isKindOfClass:[NSString class]] || !ident.length) return;
    if (![service isKindOfClass:[NSString class]] || !service.length) {
        [self replyService:ident json:@"{\"returnValue\":false,\"errorText\":\"servicio vacio\"}"];
        return;
    }
    if (![payload isKindOfClass:[NSString class]] || !payload.length) payload = @"{}";
    __weak typeof(self) weakSelf = self;
    [self.server callService:service
                  parameters:payload
                  completion:^(NSString *json) {
        [weakSelf replyService:ident json:json];
    }];
}

- (void)replyService:(NSString *)ident json:(NSString *)json {
    if (!ident.length) return;
    NSString *safe = json ?: @"{}";
    NSData *d = [NSJSONSerialization dataWithJSONObject:@[ident, safe] options:0 error:NULL];
    NSString *args = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
    if (!args || args.length < 2) args = [NSString stringWithFormat:@"[\"%@\",\"{}\"]", ident];
    NSString *js = [NSString stringWithFormat:
        @"(function(){try{window.__xuperServiceResolve.apply(null,%@);}catch(e){}})();", args];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.webView evaluateJavaScript:js completionHandler:nil];
    });
}

- (NSString *)bootstrapScript {
    return @"(function(){"
    "var info={modelName:'LJ5500',platformVersionMajor:3,platformVersionMinor:0,"
    "uhd:false,uhd8K:false,screenWidth:1024,screenHeight:768,modelName:'LJ5500'};"
    "window.__xuperIos=true;"
    "window.PalmSystem=window.PalmSystem||{};"
    "window.PalmSystem.deviceInfo=JSON.stringify(info);"
    "window.__xuperNativeBack=function(){"
    "try{var ev;try{ev=new KeyboardEvent('keydown',{keyCode:461,which:461,key:'GoBack',bubbles:true});}"
    "catch(e){ev=document.createEvent('Event');ev.initEvent('keydown',true,true);}"
    "try{ev.keyCode=461;ev.which=461;}catch(e2){}document.dispatchEvent(ev);}catch(e3){}"
    "try{if(window.__xuper&&window.__xuper.key)window.__xuper.key(461);}catch(e4){}};"
    "window.PalmSystem.platformBack=window.__xuperNativeBack;"
    "window.webOS=window.webOS||{};"
    "window.webOS.deviceInfo=function(cb){try{cb(info);}catch(e){}};"
    "window.webOS.systemInfo=function(cb){try{cb(info);}catch(e){}};"
    "window.webOS.platformBack=window.__xuperNativeBack;"
    "window.__xuperPlay=function(url,headers,title){"
    "try{window.webkit.messageHandlers.xuperPlay.postMessage("
    "{url:String(url||''),headers:headers||{},title:String(title||'')});}catch(e){}};"
    "try{var k='xuper_global_playback_v1';var s=JSON.parse(localStorage.getItem(k)||'{}');"
    "s.streamMode='normal';s.audioPreferenceCode='es-lat';s.playback=s.playback||{};"
    "s.playback.quality='720';s.playback.audio='spa';localStorage.setItem(k,JSON.stringify(s));"
    "}catch(e){}"
    "document.addEventListener('DOMContentLoaded',function(){"
    "var st=document.createElement('style');"
    "st.textContent='html,body{-webkit-touch-callout:none;-webkit-user-select:none;}body{background:#000;}';"
    "document.head.appendChild(st);"
    "});"
    "})();";
}

- (void)showError:(NSString *)message {
    if (self.errorLabel) return;
    self.errorLabel = [[UILabel alloc] initWithFrame:self.view.bounds];
    self.errorLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.errorLabel.text = message;
    self.errorLabel.textColor = [UIColor whiteColor];
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.font = [UIFont systemFontOfSize:22.0];
    [self.view addSubview:self.errorLabel];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"[xuper-ios] fallo al cargar: %@", error.localizedDescription);
    [self showError:error.localizedDescription];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    NSLog(@"[xuper-ios] pagina cargada: %@", webView.URL.absoluteString);
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

- (BOOL)shouldAutorotate {
    return YES;
}

@end