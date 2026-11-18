#import "RootViewController.h"
#import "LocalServer.h"
#import <WebKit/WebKit.h>

@interface RootViewController () <WKNavigationDelegate>

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
    self.backButton.frame = CGRectMake(self.view.bounds.size.width - 70.0, self.view.bounds.size.height - 70.0, 54.0, 54.0);
    self.backButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    [self.backButton setTitle:@"\u2039" forState:UIControlStateNormal];
    [self.backButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.backButton.titleLabel.font = [UIFont boldSystemFontOfSize:34.0];
    self.backButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
    self.backButton.layer.cornerRadius = 27.0;
    self.backButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.45].CGColor;
    self.backButton.layer.borderWidth = 1.0;
    self.backButton.alpha = 0.7;
    self.backButton.accessibilityLabel = @"Atras";
    [self.backButton addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.backButton];
}

- (void)goBack {
    NSString *js =
        @"(function(){try{if(window.__xuper&&window.__xuper.key){window.__xuper.key(461);return;}}catch(e){}"
         "var ev;try{ev=new KeyboardEvent('keydown',{keyCode:461,which:461,key:'GoBack',bubbles:true});}"
         "catch(e){ev=document.createEvent('Event');ev.initEvent('keydown',true,true);}"
         "try{ev.keyCode=461;ev.which=461;ev.charCode=461;}catch(e){}document.dispatchEvent(ev);})();";
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

- (NSString *)bootstrapScript {
    return @"(function(){"
    "var info={modelName:'LJ5500',platformVersionMajor:3,platformVersionMinor:0,"
    "uhd:false,uhd8K:false,screenWidth:1024,screenHeight:768,modelName:'LJ5500'};"
    "window.__xuperIos=true;"
    "window.PalmSystem=window.PalmSystem||{};"
    "window.PalmSystem.deviceInfo=JSON.stringify(info);"
    "window.PalmSystem.platformBack=function(){};"
    "window.webOS=window.webOS||{};"
    "window.webOS.deviceInfo=function(cb){try{cb(info);}catch(e){}};"
    "window.webOS.systemInfo=function(cb){try{cb(info);}catch(e){}};"
    "window.webOS.platformBack=function(){};"
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