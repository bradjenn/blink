#import "BlinkChromiumBrowserHost.h"

#import <AppKit/AppKit.h>

#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_download_handler.h"
#include "include/cef_display_handler.h"
#include "include/cef_focus_handler.h"
#include "include/cef_frame.h"
#include "include/cef_life_span_handler.h"
#include "include/cef_load_handler.h"
#include "include/cef_request_handler.h"
#include "include/cef_request_context.h"
#include "include/wrapper/cef_helpers.h"

#import "BlinkChromiumRuntime.h"

#ifndef NDEBUG
#define BlinkChromiumPopupDebugLog(fmt, ...) NSLog((@"[BlinkPopup] " fmt), ##__VA_ARGS__)
#else
#define BlinkChromiumPopupDebugLog(...)
#endif

typedef void (^BlinkChromiumOpenNewTabHandler)(NSString *_Nullable urlString);
typedef void (^BlinkChromiumPopupLifecycleHandler)(void);
typedef void (^BlinkChromiumDownloadUpdateHandler)(NSString *downloadIdentifier,
                                                   NSString *_Nullable urlString,
                                                   NSString *suggestedFileName,
                                                   NSString *_Nullable fullPath,
                                                   int64_t receivedBytes,
                                                   int64_t totalBytes,
                                                   NSInteger percentComplete,
                                                   int64_t currentSpeed,
                                                   BOOL isInProgress,
                                                   BOOL isComplete,
                                                   BOOL isCanceled,
                                                   BOOL isInterrupted);

@protocol BlinkChromiumHostViewOwner <NSObject>

- (void)hostViewDidMoveToWindow;
- (void)hostViewDidLayout;
- (void)hostViewWillStartLiveResize;
- (void)hostViewDidEndLiveResize;

@end

@protocol BlinkChromiumClientHost <NSObject>

- (void)clientDidCreateBrowser;
- (void)clientDidCloseBrowser;
- (void)clientDidReceiveInteraction;
- (void)clientDidUpdateURLString:(nullable NSString *)urlString
                           title:(nullable NSString *)title
                       canGoBack:(BOOL)canGoBack
                    canGoForward:(BOOL)canGoForward
                       isLoading:(BOOL)isLoading;
- (void)clientDidRequestOpenNewTabWithURLString:(nullable NSString *)urlString;
- (void)clientDidUpdateDownloadWithIdentifier:(NSString *)downloadIdentifier
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
                                isInterrupted:(BOOL)isInterrupted;
- (BOOL)clientHandleExternalNavigationForURLString:(nullable NSString *)urlString;
- (BOOL)clientConfigurePopupWithID:(int)popupID
                   targetURLString:(nullable NSString *)targetURLString
                 targetDisposition:(CefLifeSpanHandler::WindowOpenDisposition)targetDisposition
                     popupFeatures:(const CefPopupFeatures&)popupFeatures
                        windowInfo:(CefWindowInfo&)windowInfo
                            client:(CefRefPtr<CefClient>&)client
                          settings:(CefBrowserSettings&)settings;
- (void)clientDidAbortPopupWithID:(int)popupID;

@end

@class BlinkChromiumPopupWindowController;

@interface BlinkChromiumRequestContext ()
- (CefRefPtr<CefRequestContext>)requestContext;
@end

@interface BlinkChromiumBrowserHost () <BlinkChromiumHostViewOwner, BlinkChromiumClientHost>
- (void)hostViewDidMoveToWindow;
- (void)hostViewDidLayout;
- (void)clientDidCreateBrowser;
- (void)clientDidCloseBrowser;
- (void)clientDidReceiveInteraction;
- (void)clientDidUpdateURLString:(nullable NSString *)urlString
                           title:(nullable NSString *)title
                       canGoBack:(BOOL)canGoBack
                    canGoForward:(BOOL)canGoForward
                       isLoading:(BOOL)isLoading;
- (void)clientDidUpdateDownloadWithIdentifier:(NSString *)downloadIdentifier
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
                                isInterrupted:(BOOL)isInterrupted;
- (void)clientDidRequestOpenNewTabWithURLString:(nullable NSString *)urlString;
- (BOOL)clientHandleExternalNavigationForURLString:(nullable NSString *)urlString;
- (BOOL)clientConfigurePopupWithID:(int)popupID
                   targetURLString:(nullable NSString *)targetURLString
                 targetDisposition:(CefLifeSpanHandler::WindowOpenDisposition)targetDisposition
                     popupFeatures:(const CefPopupFeatures&)popupFeatures
                        windowInfo:(CefWindowInfo&)windowInfo
                            client:(CefRefPtr<CefClient>&)client
                          settings:(CefBrowserSettings&)settings;
- (void)clientDidAbortPopupWithID:(int)popupID;
- (void)clearPendingPopupWithID:(int)popupID;
@end

@interface BlinkChromiumHostView : NSView

@property (nonatomic, weak) id<BlinkChromiumHostViewOwner> owner;

@end

@implementation BlinkChromiumHostView

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    NSEventModifierFlags modifiers = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    NSString *characters = event.charactersIgnoringModifiers.lowercaseString;
    NSString *windowIdentifier = self.window.identifier;
    if (modifiers == NSEventModifierFlagCommand &&
        [characters isEqualToString:@"w"] &&
        ![windowIdentifier isEqualToString:@"BlinkChromiumPopupWindow"]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"BlinkCloseActiveTabShortcut" object:nil];
        return YES;
    }

    return [super performKeyEquivalent:event];
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)preservesContentDuringLiveResize {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self.owner hostViewDidMoveToWindow];
}

- (void)viewWillStartLiveResize {
    [super viewWillStartLiveResize];
    [self.owner hostViewWillStartLiveResize];
}

- (void)viewDidEndLiveResize {
    [super viewDidEndLiveResize];
    [self.owner hostViewDidEndLiveResize];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
}

- (void)layout {
    [super layout];
    [self.owner hostViewDidLayout];
}

@end

namespace {

std::string BlinkChromiumStartupURL(NSString *urlString) {
    if (urlString.length == 0) {
        return "about:blank";
    }

    return urlString.UTF8String;
}

NSString *BlinkChromiumStringOrNil(const CefString& value) {
    if (value.empty()) {
        return nil;
    }

    return [NSString stringWithUTF8String:value.ToString().c_str()];
}

NSString *BlinkChromiumSafeDownloadFileName(NSString *suggestedName, NSString *urlString) {
    NSString *trimmedSuggestedName = [suggestedName.lastPathComponent stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmedSuggestedName.length > 0) {
        return trimmedSuggestedName;
    }

    NSURL *url = urlString.length > 0 ? [NSURL URLWithString:urlString] : nil;
    NSString *candidate = [url.lastPathComponent stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (candidate.length > 0) {
        return candidate;
    }

    return @"download";
}

NSString *BlinkChromiumUniqueDownloadPath(NSString *suggestedName, NSString *urlString) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *downloadsDirectory = [fileManager URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask].firstObject;
    if (downloadsDirectory == nil) {
        downloadsDirectory = [NSURL fileURLWithPath:[@"~/Downloads" stringByExpandingTildeInPath] isDirectory:YES];
    }

    NSString *fileName = BlinkChromiumSafeDownloadFileName(suggestedName, urlString);
    NSString *baseName = fileName.stringByDeletingPathExtension;
    NSString *fileExtension = fileName.pathExtension;

    NSURL *candidateURL = [downloadsDirectory URLByAppendingPathComponent:fileName isDirectory:NO];
    NSUInteger suffix = 2;
    while ([fileManager fileExistsAtPath:candidateURL.path]) {
        NSString *dedupedName = fileExtension.length > 0
            ? [NSString stringWithFormat:@"%@ %lu.%@", baseName, (unsigned long)suffix, fileExtension]
            : [NSString stringWithFormat:@"%@ %lu", baseName, (unsigned long)suffix];
        candidateURL = [downloadsDirectory URLByAppendingPathComponent:dedupedName isDirectory:NO];
        suffix += 1;
    }

    return candidateURL.path;
}

void BlinkChromiumOpenURLExternally(NSString *urlString) {
    NSURL *externalURL = [NSURL URLWithString:urlString];
    if (externalURL == nil) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSWorkspace sharedWorkspace] openURL:externalURL];
    });
}

void BlinkChromiumDispatchToMainQueue(dispatch_block_t block) {
    if (block == nil) {
        return;
    }

    if (NSThread.isMainThread) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

BOOL BlinkChromiumShouldOpenPopupExternally(NSString *urlString) {
    if (urlString.length == 0) {
        return NO;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *host = url.host.lowercaseString;
    NSString *path = url.path.lowercaseString;
    NSString *absoluteString = url.absoluteString.lowercaseString;
    NSString *provider = nil;
    NSString *idp = nil;
    BOOL referencesDailyDev = [absoluteString containsString:@"daily.dev"];

    for (NSURLQueryItem *item in components.queryItems) {
        NSString *name = item.name.lowercaseString;
        NSString *value = item.value.lowercaseString;
        if (value.length > 0 && [value containsString:@"daily.dev"]) {
            referencesDailyDev = YES;
        }
        if ([name isEqualToString:@"provider"]) {
            provider = value;
        } else if ([name isEqualToString:@"idp"]) {
            idp = value;
        } else if ([name isEqualToString:@"redirect_uri"] ||
                   [name isEqualToString:@"redirecturl"] ||
                   [name isEqualToString:@"callbackurl"] ||
                   [name isEqualToString:@"returnto"] ||
                   [name isEqualToString:@"next"] ||
                   [name isEqualToString:@"continue"]) {
            referencesDailyDev = referencesDailyDev || [value containsString:@"daily.dev"];
        }
    }

    if (host.length == 0) {
        return NO;
    }

    if (referencesDailyDev) {
        return NO;
    }

    if (([provider isEqualToString:@"google"] || [idp isEqualToString:@"google"]) &&
        (([host containsString:@"supabase"] && [path containsString:@"/auth/"]) ||
         [path containsString:@"/authorize"] ||
         [path containsString:@"/callback"] ||
         [absoluteString containsString:@"oauth"])) {
        return YES;
    }

    if (([host isEqualToString:@"api.daily.dev"] && [path hasPrefix:@"/auth/"]) ||
        ([host isEqualToString:@"app.daily.dev"] && [path hasPrefix:@"/callback"])) {
        return NO;
    }

    if (([host hasSuffix:@".daily.dev"] || [host isEqualToString:@"daily.dev"]) &&
        (([path containsString:@"/auth"] ||
          [path containsString:@"/oauth"] ||
          [path containsString:@"/signin"] ||
          [path containsString:@"/login"] ||
          [path containsString:@"/callback"]) &&
         ([provider isEqualToString:@"google"] ||
          [idp isEqualToString:@"google"] ||
          [absoluteString containsString:@"google"]))) {
        return NO;
    }

    if ([host isEqualToString:@"accounts.google.com"]) {
        return YES;
    }

    if ([host hasSuffix:@".accounts.google.com"]) {
        return YES;
    }

    if (([host hasSuffix:@".google.com"] || [host isEqualToString:@"google.com"]) &&
        ([path containsString:@"/o/oauth"] ||
         [path containsString:@"/signin/oauth"] ||
         [absoluteString containsString:@"oauth"] ||
         [absoluteString containsString:@"googleusercontent.com"])) {
        return YES;
    }

    return NO;
}

BOOL BlinkChromiumTargetDispositionOpensTab(CefLifeSpanHandler::WindowOpenDisposition targetDisposition) {
    switch (targetDisposition) {
    case CEF_WOD_NEW_FOREGROUND_TAB:
    case CEF_WOD_NEW_BACKGROUND_TAB:
    case CEF_WOD_SINGLETON_TAB:
    case CEF_WOD_SWITCH_TO_TAB:
        return YES;
    default:
        return NO;
    }
}

BOOL BlinkChromiumPopupFeaturesRequestSeparateWindow(const CefPopupFeatures& popupFeatures) {
    return popupFeatures.isPopup ||
        popupFeatures.xSet ||
        popupFeatures.ySet ||
        popupFeatures.widthSet ||
        popupFeatures.heightSet;
}

BOOL BlinkChromiumLooksLikeAuthenticationPopupURL(NSString *urlString) {
    if (urlString.length == 0) {
        return NO;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *host = url.host.lowercaseString;
    NSString *path = url.path.lowercaseString;
    NSString *absoluteString = url.absoluteString.lowercaseString;
    NSString *provider = nil;
    NSString *idp = nil;

    for (NSURLQueryItem *item in components.queryItems) {
        NSString *name = item.name.lowercaseString;
        NSString *value = item.value.lowercaseString;
        if ([name isEqualToString:@"provider"]) {
            provider = value;
        } else if ([name isEqualToString:@"idp"]) {
            idp = value;
        }
    }

    if ([host isEqualToString:@"accounts.google.com"] ||
        [host hasSuffix:@".accounts.google.com"]) {
        return YES;
    }

    if (([host hasSuffix:@".google.com"] || [host isEqualToString:@"google.com"]) &&
        ([path containsString:@"/o/oauth"] ||
         [path containsString:@"/signin/oauth"] ||
         [absoluteString containsString:@"oauth"])) {
        return YES;
    }

    BOOL looksLikeAuthPath =
        [path containsString:@"/auth"] ||
        [path containsString:@"/oauth"] ||
        [path containsString:@"/login"] ||
        [path containsString:@"/signin"] ||
        [path containsString:@"/authorize"] ||
        [path containsString:@"/callback"];
    BOOL referencesGoogle =
        [provider isEqualToString:@"google"] ||
        [idp isEqualToString:@"google"] ||
        [absoluteString containsString:@"google"];

    return looksLikeAuthPath && referencesGoogle;
}

BOOL BlinkChromiumLooksLikeDownloadURL(NSString *urlString) {
    if (urlString.length == 0) {
        return NO;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    NSString *absoluteString = url.absoluteString.lowercaseString;
    NSString *path = url.path.lowercaseString;

    if ([absoluteString containsString:@"download="] ||
        [absoluteString containsString:@"attachment="] ||
        [absoluteString containsString:@"/download"] ||
        [absoluteString containsString:@"installer"] ||
        [absoluteString containsString:@"setup"]) {
        return YES;
    }

    static NSSet<NSString *> *downloadExtensions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        downloadExtensions = [NSSet setWithArray:@[
            @"zip", @"dmg", @"pkg", @"tar", @"gz", @"tgz", @"xz", @"bz2", @"7z",
            @"rar", @"exe", @"msi", @"deb", @"rpm", @"iso", @"appimage", @"bin", @"mpkg"
        ]];
    });

    NSString *extension = path.pathExtension.lowercaseString;
    return extension.length > 0 && [downloadExtensions containsObject:extension];
}

BOOL BlinkChromiumLooksLikeDownloadLandingURL(NSString *urlString) {
    if (BlinkChromiumLooksLikeDownloadURL(urlString)) {
        return YES;
    }

    if (urlString.length == 0) {
        return NO;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    NSString *absoluteString = url.absoluteString.lowercaseString;
    NSString *path = url.path.lowercaseString;
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *source = nil;
    NSString *configuration = nil;

    for (NSURLQueryItem *item in components.queryItems) {
        NSString *name = item.name.lowercaseString;
        NSString *value = item.value.lowercaseString;
        if ([name isEqualToString:@"src"] || [name isEqualToString:@"source"]) {
            source = value;
        } else if ([name isEqualToString:@"configuration"]) {
            configuration = value;
        }
    }

    if ([path containsString:@"/release"] &&
        ((source != nil && [source containsString:@"download"]) ||
         (configuration != nil && [configuration containsString:@"release"]) ||
         [absoluteString containsString:@"download"])) {
        return YES;
    }

    return NO;
}

NSString *BlinkChromiumWindowTitle(NSString *title, NSString *urlString) {
    NSString *trimmedTitle = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmedTitle.length > 0) {
        return trimmedTitle;
    }

    NSURL *url = urlString.length > 0 ? [NSURL URLWithString:urlString] : nil;
    NSString *host = url.host;
    if (host.length > 0) {
        return host;
    }

    return @"Popup";
}

NSRect BlinkChromiumPopupFrame(const CefPopupFeatures& popupFeatures) {
    CGFloat width = popupFeatures.widthSet ? MAX(320.0, popupFeatures.width) : 1100.0;
    CGFloat height = popupFeatures.heightSet ? MAX(240.0, popupFeatures.height) : 780.0;
    NSRect frame = NSMakeRect(0.0, 0.0, width, height);

    NSScreen *screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
    if (screen == nil) {
        return frame;
    }

    NSRect visibleFrame = screen.visibleFrame;
    frame.origin.x = popupFeatures.xSet ? popupFeatures.x : NSMidX(visibleFrame) - width / 2.0;
    frame.origin.y = popupFeatures.ySet ? popupFeatures.y : NSMidY(visibleFrame) - height / 2.0;
    return frame;
}

NSMutableSet<BlinkChromiumPopupWindowController *> *BlinkChromiumActivePopupControllers() {
    static NSMutableSet<BlinkChromiumPopupWindowController *> *controllers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controllers = [NSMutableSet set];
    });
    return controllers;
}

class BlinkChromiumClient final : public CefClient,
                                  public CefDownloadHandler,
                                  public CefDisplayHandler,
                                  public CefLoadHandler,
                                  public CefLifeSpanHandler,
                                  public CefFocusHandler,
                                  public CefRequestHandler {
public:
    explicit BlinkChromiumClient(id<BlinkChromiumClientHost> host)
        : host_(host) {}

    void DetachHost() {
        host_ = nil;
    }

    bool HasBrowser() const {
        return browser_ != nullptr;
    }

    void LoadURL(const std::string& url) {
        CEF_REQUIRE_UI_THREAD();
        pending_url_ = url;
        if (browser_ != nullptr) {
            browser_->GetMainFrame()->LoadURL(url);
        }
    }

    void FocusBrowser() {
        CEF_REQUIRE_UI_THREAD();
        if (browser_ != nullptr) {
            pending_focus_ = false;
            browser_->GetHost()->SetFocus(true);
        } else {
            pending_focus_ = true;
        }
    }

    void GoBack() {
        CEF_REQUIRE_UI_THREAD();
        if (browser_ != nullptr && browser_->CanGoBack()) {
            browser_->GoBack();
        }
    }

    void GoForward() {
        CEF_REQUIRE_UI_THREAD();
        if (browser_ != nullptr && browser_->CanGoForward()) {
            browser_->GoForward();
        }
    }

    void Reload() {
        CEF_REQUIRE_UI_THREAD();
        if (browser_ != nullptr) {
            browser_->Reload();
        }
    }

    void ToggleDeveloperTools() {
        CEF_REQUIRE_UI_THREAD();
        if (browser_ == nullptr) {
            return;
        }

        CefRefPtr<CefBrowserHost> host = browser_->GetHost();
        if (host == nullptr) {
            return;
        }

        if (host->HasDevTools()) {
            host->CloseDevTools();
            return;
        }

        CefWindowInfo windowInfo;
        CefBrowserSettings settings;
        host->ShowDevTools(windowInfo, nullptr, settings, CefPoint());
    }

    void CloseBrowser() {
        CEF_REQUIRE_UI_THREAD();
        if (browser_ != nullptr) {
            browser_->GetHost()->CloseBrowser(true);
        }
    }

    void WasResized() {
        CEF_REQUIRE_UI_THREAD();
        if (browser_ != nullptr) {
            browser_->GetHost()->WasResized();
        }
    }

    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override {
        return this;
    }

    CefRefPtr<CefLoadHandler> GetLoadHandler() override {
        return this;
    }

    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override {
        return this;
    }

    CefRefPtr<CefFocusHandler> GetFocusHandler() override {
        return this;
    }

    CefRefPtr<CefRequestHandler> GetRequestHandler() override {
        return this;
    }

    CefRefPtr<CefDownloadHandler> GetDownloadHandler() override {
        return this;
    }

    void OnAddressChange(
        CefRefPtr<CefBrowser> browser,
        CefRefPtr<CefFrame> frame,
        const CefString& url
    ) override {
        CEF_REQUIRE_UI_THREAD();
        if (!frame->IsMain()) {
            return;
        }

        current_url_ = url.ToString();
        PublishSnapshot();
    }

    void OnTitleChange(
        CefRefPtr<CefBrowser> browser,
        const CefString& title
    ) override {
        CEF_REQUIRE_UI_THREAD();
        current_title_ = title.ToString();
        PublishSnapshot();
    }

    void OnLoadingStateChange(
        CefRefPtr<CefBrowser> browser,
        bool isLoading,
        bool canGoBack,
        bool canGoForward
    ) override {
        CEF_REQUIRE_UI_THREAD();
        is_loading_ = isLoading;
        can_go_back_ = canGoBack;
        can_go_forward_ = canGoForward;
        if (browser != nullptr) {
            current_url_ = browser->GetMainFrame()->GetURL().ToString();
        }
        PublishSnapshot();
    }

    bool OnBeforeBrowse(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefFrame> frame,
                        CefRefPtr<CefRequest> request,
                        bool user_gesture,
                        bool is_redirect) override {
        CEF_REQUIRE_UI_THREAD();
        if (host_ == nil || frame == nullptr || !frame->IsMain() || request == nullptr) {
            return false;
        }

        NSString *requestURLString = BlinkChromiumStringOrNil(request->GetURL());
        return [host_ clientHandleExternalNavigationForURLString:requestURLString];
    }

    bool OnBeforePopup(
        CefRefPtr<CefBrowser> browser,
        CefRefPtr<CefFrame> frame,
        int popup_id,
        const CefString& target_url,
        const CefString& target_frame_name,
        WindowOpenDisposition target_disposition,
        bool user_gesture,
        const CefPopupFeatures& popupFeatures,
        CefWindowInfo& windowInfo,
        CefRefPtr<CefClient>& client,
        CefBrowserSettings& settings,
        CefRefPtr<CefDictionaryValue>& extra_info,
        bool* no_javascript_access
    ) override {
        CEF_REQUIRE_UI_THREAD();
        if (host_ == nil) {
            return true;
        }

        NSString *targetURLString = BlinkChromiumStringOrNil(target_url);
        if (no_javascript_access != nullptr) {
            *no_javascript_access = false;
        }

        BlinkChromiumPopupDebugLog(
            @"OnBeforePopup target=%@ disposition=%d userGesture=%d",
            targetURLString ?: @"<nil>",
            (int)target_disposition,
            user_gesture
        );

        if (targetURLString == nil || [targetURLString isEqualToString:@"about:blank"]) {
            if (BlinkChromiumPopupFeaturesRequestSeparateWindow(popupFeatures) ||
                !BlinkChromiumTargetDispositionOpensTab(target_disposition)) {
                if ([host_ clientConfigurePopupWithID:popup_id
                                      targetURLString:targetURLString
                                    targetDisposition:target_disposition
                                        popupFeatures:popupFeatures
                                           windowInfo:windowInfo
                                               client:client
                                             settings:settings]) {
                    BlinkChromiumPopupDebugLog(@"Popup retained as hidden bootstrap %@", targetURLString ?: @"<nil>");
                    return false;
                }
            }

            BlinkChromiumPopupDebugLog(@"Blank bootstrap popup fell back to default handling");
            client = nullptr;
            return false;
        }

        if (BlinkChromiumShouldOpenPopupExternally(targetURLString)) {
            BlinkChromiumPopupDebugLog(@"Popup matched external handoff %@", targetURLString);
            if ([host_ clientHandleExternalNavigationForURLString:targetURLString]) {
                return true;
            }
        }

        if (BlinkChromiumTargetDispositionOpensTab(target_disposition) &&
            !BlinkChromiumPopupFeaturesRequestSeparateWindow(popupFeatures) &&
            !BlinkChromiumLooksLikeAuthenticationPopupURL(targetURLString) &&
            !BlinkChromiumLooksLikeDownloadLandingURL(targetURLString)) {
            BlinkChromiumPopupDebugLog(@"Popup routed to Blink tab %@", targetURLString);
            [host_ clientDidRequestOpenNewTabWithURLString:targetURLString];
            return true;
        }

        if ([host_ clientConfigurePopupWithID:popup_id
                              targetURLString:targetURLString
                            targetDisposition:target_disposition
                                popupFeatures:popupFeatures
                                   windowInfo:windowInfo
                                       client:client
                                     settings:settings]) {
            BlinkChromiumPopupDebugLog(@"Popup routed to popup window %@", targetURLString);
            return false;
        }

        BlinkChromiumPopupDebugLog(@"Popup fell back to Blink tab %@", targetURLString);
        [host_ clientDidRequestOpenNewTabWithURLString:targetURLString];
        return true;
    }

    void OnBeforePopupAborted(CefRefPtr<CefBrowser> browser, int popup_id) override {
        CEF_REQUIRE_UI_THREAD();
        if (host_ != nil) {
            [host_ clientDidAbortPopupWithID:popup_id];
        }
    }

    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
        CEF_REQUIRE_UI_THREAD();
        browser_ = browser;
        if (host_ != nil) {
            [host_ clientDidCreateBrowser];
        }
        if (!pending_url_.empty()) {
            browser_->GetMainFrame()->LoadURL(pending_url_);
        }
        if (pending_focus_) {
            pending_focus_ = false;
            browser_->GetHost()->SetFocus(true);
        }
        PublishSnapshot();
    }

    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
        CEF_REQUIRE_UI_THREAD();
        browser_ = nullptr;
        if (host_ != nil) {
            [host_ clientDidCloseBrowser];
        }
    }

    void OnGotFocus(CefRefPtr<CefBrowser> browser) override {
        CEF_REQUIRE_UI_THREAD();
        if (host_ != nil) {
            [host_ clientDidReceiveInteraction];
        }
    }

    bool OnBeforeDownload(CefRefPtr<CefBrowser> browser,
                          CefRefPtr<CefDownloadItem> download_item,
                          const CefString& suggested_name,
                          CefRefPtr<CefBeforeDownloadCallback> callback) override {
        CEF_REQUIRE_UI_THREAD();
        if (host_ == nil || download_item == nullptr || callback == nullptr) {
            return false;
        }

        NSString *urlString = BlinkChromiumStringOrNil(download_item->GetURL());
        NSString *suggestedFileName =
            BlinkChromiumSafeDownloadFileName(BlinkChromiumStringOrNil(suggested_name) ?: @"", urlString ?: @"");
        NSString *downloadPath = BlinkChromiumUniqueDownloadPath(suggestedFileName, urlString ?: @"");
        callback->Continue(downloadPath.UTF8String, false);
        return true;
    }

    void OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
                           CefRefPtr<CefDownloadItem> download_item,
                           CefRefPtr<CefDownloadItemCallback> callback) override {
        CEF_REQUIRE_UI_THREAD();
        if (host_ == nil || download_item == nullptr || !download_item->IsValid()) {
            return;
        }

        NSString *downloadIdentifier = [NSString stringWithFormat:@"%u", download_item->GetId()];
        NSString *urlString = BlinkChromiumStringOrNil(download_item->GetURL());
        NSString *suggestedFileName = BlinkChromiumSafeDownloadFileName(
            BlinkChromiumStringOrNil(download_item->GetSuggestedFileName()) ?: @"",
            urlString ?: @""
        );
        [host_ clientDidUpdateDownloadWithIdentifier:downloadIdentifier
                                           urlString:urlString
                                   suggestedFileName:suggestedFileName
                                            fullPath:BlinkChromiumStringOrNil(download_item->GetFullPath())
                                       receivedBytes:download_item->GetReceivedBytes()
                                          totalBytes:download_item->GetTotalBytes()
                                     percentComplete:download_item->GetPercentComplete()
                                        currentSpeed:download_item->GetCurrentSpeed()
                                        isInProgress:download_item->IsInProgress()
                                          isComplete:download_item->IsComplete()
                                          isCanceled:download_item->IsCanceled()
                                       isInterrupted:download_item->IsInterrupted()];
    }

private:
    void PublishSnapshot() {
        if (host_ == nil) {
            return;
        }

        NSString *urlString = current_url_.empty() ? nil : [NSString stringWithUTF8String:current_url_.c_str()];
        NSString *titleString = current_title_.empty() ? nil : [NSString stringWithUTF8String:current_title_.c_str()];
        [host_ clientDidUpdateURLString:urlString
                                  title:titleString
                              canGoBack:can_go_back_
                           canGoForward:can_go_forward_
                              isLoading:is_loading_];
    }

    __weak id<BlinkChromiumClientHost> host_ = nil;
    CefRefPtr<CefBrowser> browser_;
    std::string pending_url_;
    std::string current_url_;
    std::string current_title_;
    bool pending_focus_ = false;
    bool can_go_back_ = false;
    bool can_go_forward_ = false;
    bool is_loading_ = false;

    IMPLEMENT_REFCOUNTING(BlinkChromiumClient);
    DISALLOW_COPY_AND_ASSIGN(BlinkChromiumClient);
};

}  // namespace

@interface BlinkChromiumPopupWindowController : NSObject <NSWindowDelegate, BlinkChromiumHostViewOwner, BlinkChromiumClientHost>

- (instancetype)initWithInitialURLString:(nullable NSString *)initialURLString
                           popupFeatures:(const CefPopupFeatures&)popupFeatures
                             onOpenNewTab:(BlinkChromiumOpenNewTabHandler)onOpenNewTab
                         onDownloadUpdate:(BlinkChromiumDownloadUpdateHandler)onDownloadUpdate
                                onCreated:(BlinkChromiumPopupLifecycleHandler)onCreated
                                 onClosed:(BlinkChromiumPopupLifecycleHandler)onClosed;
- (void)configureWindowInfo:(CefWindowInfo&)windowInfo
                     client:(CefRefPtr<CefClient>&)client
                   settings:(CefBrowserSettings&)settings;
- (void)abortPendingPopup;

@end

@implementation BlinkChromiumPopupWindowController {
@private
    NSString *_initialURLString;
    BOOL _didCreateBrowser;
    BOOL _didHandOffExternalNavigation;
    BOOL _didFinishClosing;
    BOOL _hasPresentedWindow;
    BOOL _isClosingBrowser;
    BOOL _isInLiveResize;
    NSSize _lastReportedHostSize;
    dispatch_block_t _pendingResizeWorkItem;
    NSWindow *_window;
    BlinkChromiumHostView *_hostView;
    BlinkChromiumBrowserStateSnapshot *_snapshot;
    NSMutableDictionary<NSNumber *, BlinkChromiumPopupWindowController *> *_pendingPopupControllers;
    BlinkChromiumOpenNewTabHandler _onOpenNewTab;
    BlinkChromiumDownloadUpdateHandler _onDownloadUpdate;
    BlinkChromiumPopupLifecycleHandler _onCreated;
    BlinkChromiumPopupLifecycleHandler _onClosed;
    CefRefPtr<BlinkChromiumClient> _client;
}

- (instancetype)initWithInitialURLString:(NSString *)initialURLString
                           popupFeatures:(const CefPopupFeatures&)popupFeatures
                             onOpenNewTab:(BlinkChromiumOpenNewTabHandler)onOpenNewTab
                         onDownloadUpdate:(BlinkChromiumDownloadUpdateHandler)onDownloadUpdate
                                onCreated:(BlinkChromiumPopupLifecycleHandler)onCreated
                                 onClosed:(BlinkChromiumPopupLifecycleHandler)onClosed {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _initialURLString = [initialURLString copy];
    _pendingPopupControllers = [NSMutableDictionary dictionary];
    _onOpenNewTab = [onOpenNewTab copy];
    _onDownloadUpdate = [onDownloadUpdate copy];
    _onCreated = [onCreated copy];
    _onClosed = [onClosed copy];

    NSRect frame = BlinkChromiumPopupFrame(popupFeatures);
    _hostView = [[BlinkChromiumHostView alloc] initWithFrame:NSMakeRect(0.0, 0.0, frame.size.width, frame.size.height)];
    _hostView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _hostView.owner = self;

    NSWindowStyleMask styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
        NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:styleMask
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.delegate = self;
    _window.identifier = NSUserInterfaceItemIdentifier(@"BlinkChromiumPopupWindow");
    _window.title = BlinkChromiumWindowTitle(nil, _initialURLString);
    _window.contentView = _hostView;

    _client = new BlinkChromiumClient(self);
    [BlinkChromiumActivePopupControllers() addObject:self];

    return self;
}

- (BOOL)shouldPresentWindowForURLString:(NSString *)urlString {
    NSString *candidateURLString = urlString ?: _snapshot.urlString ?: _initialURLString;
    if (candidateURLString.length == 0 || [candidateURLString isEqualToString:@"about:blank"]) {
        return NO;
    }

    if (BlinkChromiumLooksLikeDownloadLandingURL(candidateURLString)) {
        return NO;
    }

    return YES;
}

- (void)presentWindowIfNeededForURLString:(NSString *)urlString {
    if (_hasPresentedWindow || ![self shouldPresentWindowForURLString:urlString]) {
        return;
    }

    _hasPresentedWindow = YES;
    [_window makeKeyAndOrderFront:nil];
}

- (void)configureWindowInfo:(CefWindowInfo&)windowInfo
                     client:(CefRefPtr<CefClient>&)client
                   settings:(CefBrowserSettings&)settings {
    windowInfo.SetAsChild(
        (__bridge CefWindowHandle)_hostView,
        CefRect(0, 0, _hostView.bounds.size.width, _hostView.bounds.size.height)
    );
    windowInfo.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
    client = _client;
}

- (void)abortPendingPopup {
    [self cancelPendingResizeWorkItem];
    [self finishClosing];
    if (_window != nil) {
        [_window orderOut:nil];
        [_window close];
        _window = nil;
    }
}

- (void)hostViewDidMoveToWindow {
    _window.preservesContentDuringLiveResize = YES;
}

- (void)hostViewWillStartLiveResize {
    _isInLiveResize = YES;
    [self cancelPendingResizeWorkItem];
}

- (void)hostViewDidEndLiveResize {
    _isInLiveResize = NO;
    [self cancelPendingResizeWorkItem];
    [self flushPendingResizeIfNeeded];
}

- (void)hostViewDidLayout {
    [self scheduleResizeIfNeeded];
}

- (void)scheduleResizeIfNeeded {
    if (_client == nullptr || !_client->HasBrowser()) {
        return;
    }

    NSSize hostSize = _hostView.bounds.size;
    if (NSEqualSizes(_lastReportedHostSize, hostSize)) {
        return;
    }

    if (_isInLiveResize) {
        return;
    }

    [self flushResizeForSize:hostSize];
}

- (void)flushPendingResizeIfNeeded {
    if (_client == nullptr || !_client->HasBrowser()) {
        return;
    }

    NSSize hostSize = _hostView.bounds.size;
    if (NSEqualSizes(_lastReportedHostSize, hostSize)) {
        return;
    }

    [self flushResizeForSize:hostSize];
}

- (void)flushResizeForSize:(NSSize)hostSize {
    if (hostSize.width <= 0.0 || hostSize.height <= 0.0) {
        return;
    }

    _lastReportedHostSize = hostSize;
    _client->WasResized();
}

- (void)cancelPendingResizeWorkItem {
    if (_pendingResizeWorkItem == nil) {
        return;
    }

    dispatch_block_cancel(_pendingResizeWorkItem);
    _pendingResizeWorkItem = nil;
}

- (void)clientDidCreateBrowser {
    _didCreateBrowser = YES;
    if (_onCreated != nil) {
        _onCreated();
        _onCreated = nil;
    }
    [self presentWindowIfNeededForURLString:_initialURLString];
    _client->FocusBrowser();
    [self flushPendingResizeIfNeeded];
}

- (void)clientDidCloseBrowser {
    _didCreateBrowser = NO;
    if (_window != nil) {
        [_window close];
    }
    [self finishClosing];
}

- (void)clientDidReceiveInteraction {
    if (_window.firstResponder != _hostView) {
        [_window makeFirstResponder:_hostView];
    }
}

- (void)clientDidUpdateURLString:(NSString *)urlString
                           title:(NSString *)title
                       canGoBack:(BOOL)canGoBack
                    canGoForward:(BOOL)canGoForward
                       isLoading:(BOOL)isLoading {
    if ([self clientHandleExternalNavigationForURLString:urlString]) {
        return;
    }

    _snapshot = [[BlinkChromiumBrowserStateSnapshot alloc] initWithURLString:urlString
                                                                       title:title
                                                                   canGoBack:canGoBack
                                                                canGoForward:canGoForward
                                                                   isLoading:isLoading];
    _window.title = BlinkChromiumWindowTitle(title, urlString ?: _initialURLString);
    [self presentWindowIfNeededForURLString:urlString];
}

- (void)clientDidRequestOpenNewTabWithURLString:(NSString *)urlString {
    BlinkChromiumPopupDebugLog(@"Popup requested Blink tab %@", urlString ?: @"<nil>");
    if (_onOpenNewTab != nil) {
        _onOpenNewTab(urlString);
    }
}

- (void)clientDidUpdateDownloadWithIdentifier:(NSString *)downloadIdentifier
                                    urlString:(NSString *)urlString
                            suggestedFileName:(NSString *)suggestedFileName
                                     fullPath:(NSString *)fullPath
                                receivedBytes:(int64_t)receivedBytes
                                   totalBytes:(int64_t)totalBytes
                              percentComplete:(NSInteger)percentComplete
                                 currentSpeed:(int64_t)currentSpeed
                                 isInProgress:(BOOL)isInProgress
                                   isComplete:(BOOL)isComplete
                                 isCanceled:(BOOL)isCanceled
                                isInterrupted:(BOOL)isInterrupted {
    if (_onDownloadUpdate != nil) {
        _onDownloadUpdate(downloadIdentifier,
                          urlString,
                          suggestedFileName,
                          fullPath,
                          receivedBytes,
                          totalBytes,
                          percentComplete,
                          currentSpeed,
                          isInProgress,
                          isComplete,
                          isCanceled,
                          isInterrupted);
    }

    NSString *currentURLString = _snapshot.urlString ?: _initialURLString;
    BOOL isBlankPopup = currentURLString.length == 0 || [currentURLString isEqualToString:@"about:blank"];
    if (!isBlankPopup) {
        return;
    }

    if (_client != nullptr && _client->HasBrowser()) {
        _isClosingBrowser = YES;
        _client->CloseBrowser();
    } else {
        [self abortPendingPopup];
    }
}

- (BOOL)clientHandleExternalNavigationForURLString:(NSString *)urlString {
    if (_didHandOffExternalNavigation || !BlinkChromiumShouldOpenPopupExternally(urlString)) {
        return NO;
    }

    BlinkChromiumPopupDebugLog(@"Handing popup externally %@", urlString ?: @"<nil>");
    _didHandOffExternalNavigation = YES;
    BlinkChromiumOpenURLExternally(urlString);

    if (_client != nullptr && _client->HasBrowser()) {
        _isClosingBrowser = YES;
        _client->CloseBrowser();
    } else {
        [self abortPendingPopup];
    }

    return YES;
}

- (BOOL)clientConfigurePopupWithID:(int)popupID
                   targetURLString:(NSString *)targetURLString
                 targetDisposition:(CefLifeSpanHandler::WindowOpenDisposition)targetDisposition
                     popupFeatures:(const CefPopupFeatures&)popupFeatures
                        windowInfo:(CefWindowInfo&)windowInfo
                            client:(CefRefPtr<CefClient>&)client
                          settings:(CefBrowserSettings&)settings {
    __weak BlinkChromiumPopupWindowController *weakSelf = self;
    BlinkChromiumPopupWindowController *popupController =
        [[BlinkChromiumPopupWindowController alloc] initWithInitialURLString:targetURLString
                                                               popupFeatures:popupFeatures
                                                                 onOpenNewTab:_onOpenNewTab
                                                            onDownloadUpdate:_onDownloadUpdate
                                                                    onCreated:^{
                                                                        [weakSelf clearPendingPopupWithID:popupID];
                                                                    }
                                                                     onClosed:^{
                                                                         [weakSelf clearPendingPopupWithID:popupID];
                                                                     }];
    if (popupController == nil) {
        return NO;
    }

    _pendingPopupControllers[@(popupID)] = popupController;
    [popupController configureWindowInfo:windowInfo client:client settings:settings];
    return YES;
}

- (void)clientDidAbortPopupWithID:(int)popupID {
    BlinkChromiumPopupWindowController *popupController = _pendingPopupControllers[@(popupID)];
    if (popupController == nil) {
        return;
    }

    [_pendingPopupControllers removeObjectForKey:@(popupID)];
    [popupController abortPendingPopup];
}

- (void)clearPendingPopupWithID:(int)popupID {
    [_pendingPopupControllers removeObjectForKey:@(popupID)];
}

- (BOOL)windowShouldClose:(id)sender {
    if (_client != nullptr && _client->HasBrowser() && !_isClosingBrowser) {
        _isClosingBrowser = YES;
        _client->CloseBrowser();
        return NO;
    }

    return YES;
}

- (void)windowWillClose:(NSNotification *)notification {
    [self finishClosing];
}

- (void)finishClosing {
    if (_didFinishClosing) {
        return;
    }

    _didFinishClosing = YES;
    [self cancelPendingResizeWorkItem];
    NSArray<BlinkChromiumPopupWindowController *> *pendingPopups = _pendingPopupControllers.allValues;
    [_pendingPopupControllers removeAllObjects];
    for (BlinkChromiumPopupWindowController *popupController in pendingPopups) {
        [popupController abortPendingPopup];
    }

    if (_onClosed != nil) {
        _onClosed();
        _onClosed = nil;
    }
    _onCreated = nil;

    [BlinkChromiumActivePopupControllers() removeObject:self];
}

@end

@implementation BlinkChromiumBrowserStateSnapshot

- (instancetype)initWithURLString:(NSString *)urlString
                            title:(NSString *)title
                        canGoBack:(BOOL)canGoBack
                     canGoForward:(BOOL)canGoForward
                        isLoading:(BOOL)isLoading {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _urlString = [urlString copy];
    _title = [title copy];
    _canGoBack = canGoBack;
    _canGoForward = canGoForward;
    _isLoading = isLoading;
    return self;
}

@end

@implementation BlinkChromiumDownloadSnapshot

- (instancetype)initWithDownloadIdentifier:(NSString *)downloadIdentifier
                                 urlString:(NSString *)urlString
                         suggestedFileName:(NSString *)suggestedFileName
                                  fullPath:(NSString *)fullPath
                             receivedBytes:(int64_t)receivedBytes
                                totalBytes:(int64_t)totalBytes
                           percentComplete:(NSInteger)percentComplete
                              currentSpeed:(int64_t)currentSpeed
                              isInProgress:(BOOL)isInProgress
                                isComplete:(BOOL)isComplete
                                isCanceled:(BOOL)isCanceled
                             isInterrupted:(BOOL)isInterrupted {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _downloadIdentifier = [downloadIdentifier copy];
    _urlString = [urlString copy];
    _suggestedFileName = [suggestedFileName copy];
    _fullPath = [fullPath copy];
    _receivedBytes = receivedBytes;
    _totalBytes = totalBytes;
    _percentComplete = percentComplete;
    _currentSpeed = currentSpeed;
    _isInProgress = isInProgress;
    _isComplete = isComplete;
    _isCanceled = isCanceled;
    _isInterrupted = isInterrupted;
    return self;
}

@end

@implementation BlinkChromiumBrowserHost {
@private
    NSString *_tabIdentifier;
    NSString *_workspaceIdentifier;
    BOOL _browserCreationPending;
    BOOL _isInvalidated;
    BOOL _isInLiveResize;
    NSSize _lastReportedHostSize;
    dispatch_block_t _pendingResizeWorkItem;
    BlinkChromiumHostView *_hostView;
    BlinkChromiumBrowserStateSnapshot *_snapshot;
    NSMutableDictionary<NSNumber *, BlinkChromiumPopupWindowController *> *_pendingPopupControllers;
    CefRefPtr<BlinkChromiumClient> _client;
}

- (instancetype)initWithTabIdentifier:(NSString *)tabIdentifier
                    workspaceIdentifier:(NSString *)workspaceIdentifier
                     initialURLString:(NSString *)initialURLString {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _tabIdentifier = [tabIdentifier copy];
    _workspaceIdentifier = [workspaceIdentifier copy];
    _hostView = [[BlinkChromiumHostView alloc] initWithFrame:NSZeroRect];
    _hostView.owner = self;
    _pendingPopupControllers = [NSMutableDictionary dictionary];
    _client = new BlinkChromiumClient(self);
    [self loadURLString:initialURLString ?: @"about:blank"];
    return self;
}

- (void)dealloc {
    [self invalidate];
}

- (NSView *)hostView {
    return _hostView;
}

- (BlinkChromiumBrowserStateSnapshot *)snapshot {
    return _snapshot;
}

- (void)loadURLString:(NSString *)urlString {
    if (_isInvalidated || _client == nullptr) {
        return;
    }
    _client->LoadURL(BlinkChromiumStartupURL(urlString));
    [self ensureBrowserCreatedIfPossible];
}

- (void)focusBrowserView {
    if (_isInvalidated || _client == nullptr) {
        return;
    }
    if (_hostView.window != nil) {
        [_hostView.window makeFirstResponder:_hostView];
    }
    _client->FocusBrowser();
}

- (void)goBack {
    if (_isInvalidated || _client == nullptr) {
        return;
    }
    _client->GoBack();
}

- (void)goForward {
    if (_isInvalidated || _client == nullptr) {
        return;
    }
    _client->GoForward();
}

- (void)reload {
    if (_isInvalidated || _client == nullptr) {
        return;
    }
    _client->Reload();
}

- (void)toggleDeveloperTools {
    if (_isInvalidated || _client == nullptr) {
        return;
    }
    _client->ToggleDeveloperTools();
}

- (void)invalidate {
    if (_isInvalidated) {
        return;
    }

    _isInvalidated = YES;
    [self cancelPendingResizeWorkItem];
    _browserCreationPending = NO;
    _hostView.owner = nil;
    self.delegate = nil;
    NSArray<BlinkChromiumPopupWindowController *> *pendingPopups = _pendingPopupControllers.allValues;
    [_pendingPopupControllers removeAllObjects];
    for (BlinkChromiumPopupWindowController *popupController in pendingPopups) {
        [popupController abortPendingPopup];
    }

    if (_client != nullptr) {
        _client->DetachHost();
        _client->CloseBrowser();
        _client = nullptr;
    }
}

- (void)hostViewDidMoveToWindow {
    if (_isInvalidated) {
        return;
    }
    _hostView.window.preservesContentDuringLiveResize = YES;
    [self ensureBrowserCreatedIfPossible];
}

- (void)hostViewWillStartLiveResize {
    if (_isInvalidated) {
        return;
    }
    _isInLiveResize = YES;
    [self cancelPendingResizeWorkItem];
}

- (void)hostViewDidEndLiveResize {
    if (_isInvalidated) {
        return;
    }
    _isInLiveResize = NO;
    [self cancelPendingResizeWorkItem];
    [self flushPendingResizeIfNeeded];
}

- (void)hostViewDidLayout {
    if (_isInvalidated) {
        return;
    }
    [self ensureBrowserCreatedIfPossible];
    [self scheduleResizeIfNeeded];
}

- (void)scheduleResizeIfNeeded {
    if (_client == nullptr || !_client->HasBrowser()) {
        return;
    }

    NSSize hostSize = _hostView.bounds.size;
    if (NSEqualSizes(_lastReportedHostSize, hostSize)) {
        return;
    }

    if (_isInLiveResize) {
        return;
    }

    [self flushResizeForSize:hostSize];
}

- (void)flushPendingResizeIfNeeded {
    if (_client == nullptr || !_client->HasBrowser()) {
        return;
    }

    NSSize hostSize = _hostView.bounds.size;
    if (NSEqualSizes(_lastReportedHostSize, hostSize)) {
        return;
    }

    [self flushResizeForSize:hostSize];
}

- (void)flushResizeForSize:(NSSize)hostSize {
    if (hostSize.width <= 0.0 || hostSize.height <= 0.0) {
        return;
    }

    _lastReportedHostSize = hostSize;
    _client->WasResized();
}

- (void)cancelPendingResizeWorkItem {
    if (_pendingResizeWorkItem == nil) {
        return;
    }

    dispatch_block_cancel(_pendingResizeWorkItem);
    _pendingResizeWorkItem = nil;
}

- (void)clientDidCreateBrowser {
    if (_isInvalidated) {
        return;
    }
    _browserCreationPending = NO;
    [self flushPendingResizeIfNeeded];
}

- (void)clientDidCloseBrowser {
    _browserCreationPending = NO;
}

- (void)clientDidReceiveInteraction {
    __weak BlinkChromiumBrowserHost *weakSelf = self;
    BlinkChromiumDispatchToMainQueue(^{
        BlinkChromiumBrowserHost *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        [strongSelf.delegate chromiumBrowserHostDidReceiveInteraction:strongSelf];
    });
}

- (void)clientDidUpdateURLString:(NSString *)urlString
                           title:(NSString *)title
                       canGoBack:(BOOL)canGoBack
                    canGoForward:(BOOL)canGoForward
                       isLoading:(BOOL)isLoading {
    if (_isInvalidated) {
        return;
    }
    _snapshot = [[BlinkChromiumBrowserStateSnapshot alloc] initWithURLString:urlString
                                                                       title:title
                                                                   canGoBack:canGoBack
                                                                canGoForward:canGoForward
                                                                   isLoading:isLoading];
    BlinkChromiumBrowserStateSnapshot *snapshot = _snapshot;
    __weak BlinkChromiumBrowserHost *weakSelf = self;
    BlinkChromiumDispatchToMainQueue(^{
        BlinkChromiumBrowserHost *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        [strongSelf.delegate chromiumBrowserHost:strongSelf didUpdate:snapshot];
    });
}

- (void)clientDidRequestOpenNewTabWithURLString:(NSString *)urlString {
    NSString *resolvedURLString = [urlString copy];
    __weak BlinkChromiumBrowserHost *weakSelf = self;
    BlinkChromiumDispatchToMainQueue(^{
        BlinkChromiumBrowserHost *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        [strongSelf.delegate chromiumBrowserHost:strongSelf didRequestOpenNewTabWithURLString:resolvedURLString];
    });
}

- (void)clientDidUpdateDownloadWithIdentifier:(NSString *)downloadIdentifier
                                    urlString:(NSString *)urlString
                            suggestedFileName:(NSString *)suggestedFileName
                                     fullPath:(NSString *)fullPath
                                receivedBytes:(int64_t)receivedBytes
                                   totalBytes:(int64_t)totalBytes
                              percentComplete:(NSInteger)percentComplete
                                 currentSpeed:(int64_t)currentSpeed
                                 isInProgress:(BOOL)isInProgress
                                   isComplete:(BOOL)isComplete
                                   isCanceled:(BOOL)isCanceled
                                isInterrupted:(BOOL)isInterrupted {
    if (_isInvalidated) {
        return;
    }
    BlinkChromiumDownloadSnapshot *snapshot =
        [[BlinkChromiumDownloadSnapshot alloc] initWithDownloadIdentifier:downloadIdentifier
                                                                urlString:urlString
                                                        suggestedFileName:suggestedFileName
                                                                 fullPath:fullPath
                                                            receivedBytes:receivedBytes
                                                               totalBytes:totalBytes
                                                          percentComplete:percentComplete
                                                             currentSpeed:currentSpeed
                                                             isInProgress:isInProgress
                                                               isComplete:isComplete
                                                               isCanceled:isCanceled
                                                            isInterrupted:isInterrupted];
    __weak BlinkChromiumBrowserHost *weakSelf = self;
    BlinkChromiumDispatchToMainQueue(^{
        BlinkChromiumBrowserHost *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        [strongSelf.delegate chromiumBrowserHost:strongSelf didUpdateDownload:snapshot];
    });
}

- (BOOL)clientHandleExternalNavigationForURLString:(NSString *)urlString {
    return NO;
}

- (BOOL)clientConfigurePopupWithID:(int)popupID
                   targetURLString:(NSString *)targetURLString
                 targetDisposition:(CefLifeSpanHandler::WindowOpenDisposition)targetDisposition
                     popupFeatures:(const CefPopupFeatures&)popupFeatures
                        windowInfo:(CefWindowInfo&)windowInfo
                            client:(CefRefPtr<CefClient>&)client
                          settings:(CefBrowserSettings&)settings {
    __weak BlinkChromiumBrowserHost *weakSelf = self;
    BlinkChromiumPopupWindowController *popupController =
        [[BlinkChromiumPopupWindowController alloc] initWithInitialURLString:targetURLString
                                                               popupFeatures:popupFeatures
                                                                 onOpenNewTab:^(NSString *urlString) {
                                                                     [weakSelf clientDidRequestOpenNewTabWithURLString:urlString];
                                                                 }
                                                            onDownloadUpdate:^(NSString *downloadIdentifier,
                                                                               NSString *urlString,
                                                                               NSString *suggestedFileName,
                                                                               NSString *fullPath,
                                                                               int64_t receivedBytes,
                                                                               int64_t totalBytes,
                                                                               NSInteger percentComplete,
                                                                               int64_t currentSpeed,
                                                                               BOOL isInProgress,
                                                                               BOOL isComplete,
                                                                               BOOL isCanceled,
                                                                               BOOL isInterrupted) {
                                                                [weakSelf clientDidUpdateDownloadWithIdentifier:downloadIdentifier
                                                                                                     urlString:urlString
                                                                                             suggestedFileName:suggestedFileName
                                                                                                      fullPath:fullPath
                                                                                                 receivedBytes:receivedBytes
                                                                                                    totalBytes:totalBytes
                                                                                               percentComplete:percentComplete
                                                                                                  currentSpeed:currentSpeed
                                                                                                  isInProgress:isInProgress
                                                                                                    isComplete:isComplete
                                                                                                    isCanceled:isCanceled
                                                                                                 isInterrupted:isInterrupted];
                                                            }
                                                                    onCreated:^{
                                                                        [weakSelf clearPendingPopupWithID:popupID];
                                                                    }
                                                                     onClosed:^{
                                                                         [weakSelf clearPendingPopupWithID:popupID];
                                                                     }];
    if (popupController == nil) {
        return NO;
    }

    _pendingPopupControllers[@(popupID)] = popupController;
    [popupController configureWindowInfo:windowInfo client:client settings:settings];
    return YES;
}

- (void)clientDidAbortPopupWithID:(int)popupID {
    BlinkChromiumPopupWindowController *popupController = _pendingPopupControllers[@(popupID)];
    if (popupController == nil) {
        return;
    }

    [_pendingPopupControllers removeObjectForKey:@(popupID)];
    [popupController abortPendingPopup];
}

- (void)clearPendingPopupWithID:(int)popupID {
    [_pendingPopupControllers removeObjectForKey:@(popupID)];
}

- (void)ensureBrowserCreatedIfPossible {
    if (_isInvalidated || _client == nullptr ||
        _browserCreationPending || _client->HasBrowser() || _hostView.window == nil ||
        NSIsEmptyRect(_hostView.bounds)) {
        return;
    }

    BlinkChromiumRequestContext *requestContext =
        [[BlinkChromiumRuntime sharedRuntime] requestContextForWorkspaceIdentifier:_workspaceIdentifier];
    if (requestContext == nil) {
        return;
    }
    if (![requestContext isReady]) {
        __weak BlinkChromiumBrowserHost *weakSelf = self;
        [requestContext whenReady:^{
            [weakSelf ensureBrowserCreatedIfPossible];
        }];
        return;
    }

    CefWindowInfo windowInfo;
    windowInfo.SetAsChild(
        (__bridge CefWindowHandle)_hostView,
        CefRect(0, 0, _hostView.bounds.size.width, _hostView.bounds.size.height)
    );
    windowInfo.runtime_style = CEF_RUNTIME_STYLE_ALLOY;

    CefBrowserSettings settings;
    _browserCreationPending = CefBrowserHost::CreateBrowser(
        windowInfo,
        _client,
        BlinkChromiumStartupURL(_snapshot.urlString ?: @"about:blank"),
        settings,
        nullptr,
        [requestContext requestContext]
    );
}

@end
