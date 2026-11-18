#import <UIKit/UIKit.h>

@interface XuperPlayerViewController : UIViewController

- (instancetype)initWithURL:(NSString *)url
                    headers:(NSDictionary *)headers
                      title:(NSString *)title;

@end