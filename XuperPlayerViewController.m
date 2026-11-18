#import "XuperPlayerViewController.h"
#import <MobileVLCKit/MobileVLCKit.h>

@interface XuperPlayerViewController () <VLCMediaPlayerDelegate>
@property (nonatomic, copy) NSString *videoURL;
@property (nonatomic, copy) NSDictionary *headers;
@property (nonatomic, copy) NSString *videoTitle;
@property (nonatomic, strong) VLCMediaPlayer *player;
@property (nonatomic, strong) UIView *videoView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UILabel *hud;
@end

@implementation XuperPlayerViewController

- (instancetype)initWithURL:(NSString *)url
                    headers:(NSDictionary *)headers
                      title:(NSString *)title {
    self = [super init];
    if (self) {
        _videoURL = [url copy];
        _headers = [headers copy] ?: @{};
        _videoTitle = [title copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    self.videoView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.videoView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.videoView.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.videoView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.spinner.center = CGPointMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0);
    [self.spinner startAnimating];
    [self.view addSubview:self.spinner];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.player) return;
    [self startPlayback];
}

- (void)startPlayback {
    NSURL *url = [NSURL URLWithString:self.videoURL ?: @""];
    if (!url) {
        NSLog(@"[xuper-vlc] URL no valida");
        return;
    }
    NSLog(@"[xuper-vlc] abriendo %@", self.videoURL);
    VLCMedia *media = [VLCMedia mediaWithURL:url];
    NSMutableDictionary *opts = [NSMutableDictionary dictionary];
    opts[@":network-caching"] = @(2000);
    NSMutableString *ua = [NSMutableString stringWithString:@"Mozilla/5.0"];
    NSMutableDictionary *refs = [NSMutableDictionary dictionary];
    for (NSString *key in self.headers) {
        NSString *value = [self.headers[key] description];
        NSString *lower = [key lowercaseString];
        if ([lower isEqualToString:@"user-agent"]) {
            [ua setString:value];
        } else {
            refs[key] = value;
        }
    }
    opts[@":http-user-agent"] = [ua copy];
    if (refs.count) opts[@":http-referrer"] = [refs copy];
    [media addOptions:opts];

    VLCMediaPlayer *player = [[VLCMediaPlayer alloc] init];
    player.media = media;
    player.delegate = self;
    player.drawable = self.videoView;
    self.player = player;
    [player play];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    close.frame = CGRectMake(12.0, 12.0, 56.0, 46.0);
    [close setTitle:@"\u2715" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont boldSystemFontOfSize:26.0];
    close.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
    close.layer.cornerRadius = 9.0;
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];
    self.closeButton = close;
}

- (void)closeTapped {
    [self.player stop];
    self.player = nil;
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)mediaPlayerStateChanged:(NSNotification *)aNotification {
    if (self.player.state == VLCMediaPlayerStatePlaying) {
        [self.spinner stopAnimating];
    } else if (self.player.state == VLCMediaPlayerStateError) {
        [self.spinner stopAnimating];
        NSLog(@"[xuper-vlc] error del reproductor");
    }
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