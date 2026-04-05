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

@interface BlinkChromiumDownloadSnapshot : NSObject

@property (nonatomic, copy, readonly) NSString *downloadIdentifier;
@property (nonatomic, copy, readonly, nullable) NSString *urlString;
@property (nonatomic, copy, readonly) NSString *suggestedFileName;
@property (nonatomic, copy, readonly, nullable) NSString *fullPath;
@property (nonatomic, readonly) int64_t receivedBytes;
@property (nonatomic, readonly) int64_t totalBytes;
@property (nonatomic, readonly) NSInteger percentComplete;
@property (nonatomic, readonly) int64_t currentSpeed;
@property (nonatomic, readonly) BOOL isInProgress;
@property (nonatomic, readonly) BOOL isComplete;
@property (nonatomic, readonly) BOOL isCanceled;
@property (nonatomic, readonly) BOOL isInterrupted;

- (instancetype)initWithDownloadIdentifier:(NSString *)downloadIdentifier
                                 urlString:(nullable NSString *)urlString
                         suggestedFileName:(NSString *)suggestedFileName
                                  fullPath:(nullable NSString *)fullPath
                             receivedBytes:(int64_t)receivedBytes
                                totalBytes:(int64_t)totalBytes
                           percentComplete:(NSInteger)percentComplete
                              currentSpeed:(int64_t)currentSpeed
                              isInProgress:(BOOL)isInProgress
                                isComplete:(BOOL)isComplete
                                isCanceled:(BOOL)isCanceled
                             isInterrupted:(BOOL)isInterrupted NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@protocol BlinkChromiumBrowserHostDelegate <NSObject>

- (void)chromiumBrowserHostDidReceiveInteraction:(BlinkChromiumBrowserHost *)host;
- (void)chromiumBrowserHost:(BlinkChromiumBrowserHost *)host
                  didUpdate:(BlinkChromiumBrowserStateSnapshot *)snapshot;
- (void)chromiumBrowserHost:(BlinkChromiumBrowserHost *)host
didRequestOpenNewTabWithURLString:(nullable NSString *)urlString;
- (void)chromiumBrowserHost:(BlinkChromiumBrowserHost *)host
          didUpdateDownload:(BlinkChromiumDownloadSnapshot *)snapshot;

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
