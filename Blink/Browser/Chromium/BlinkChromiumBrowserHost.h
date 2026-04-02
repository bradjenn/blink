#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class BlinkChromiumBrowserHost;

@interface BlinkChromiumBrowserStateSnapshot : NSObject

@property (nonatomic, copy, readonly, nullable) NSString *urlString;
@property (nonatomic, copy, readonly, nullable) NSString *title;
@property (nonatomic, readonly) BOOL canGoBack;
@property (nonatomic, readonly) BOOL canGoForward;
@property (nonatomic, readonly) BOOL isLoading;

- (instancetype)initWithURLString:(nullable NSString *)urlString
                            title:(nullable NSString *)title
                        canGoBack:(BOOL)canGoBack
                     canGoForward:(BOOL)canGoForward
                        isLoading:(BOOL)isLoading NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@protocol BlinkChromiumBrowserHostDelegate <NSObject>

- (void)chromiumBrowserHostDidReceiveInteraction:(BlinkChromiumBrowserHost *)host;
- (void)chromiumBrowserHost:(BlinkChromiumBrowserHost *)host
                  didUpdate:(BlinkChromiumBrowserStateSnapshot *)snapshot;
- (void)chromiumBrowserHost:(BlinkChromiumBrowserHost *)host
didRequestOpenNewTabWithURLString:(nullable NSString *)urlString;

@end

@interface BlinkChromiumBrowserHost : NSObject

@property (nonatomic, weak, nullable) id<BlinkChromiumBrowserHostDelegate> delegate;
@property (nonatomic, strong, readonly) NSView *hostView;
@property (nonatomic, strong, readonly, nullable) BlinkChromiumBrowserStateSnapshot *snapshot;

- (instancetype)initWithTabIdentifier:(NSString *)tabIdentifier
                    projectIdentifier:(NSString *)projectIdentifier
                     initialURLString:(nullable NSString *)initialURLString NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)loadURLString:(NSString *)urlString;
- (void)focusBrowserView;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)toggleDeveloperTools;
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
