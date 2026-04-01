#import "BlinkChromiumBrowserHost.h"

#import <AppKit/AppKit.h>

#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_display_handler.h"
#include "include/cef_focus_handler.h"
#include "include/cef_frame.h"
#include "include/cef_life_span_handler.h"
#include "include/cef_load_handler.h"
#include "include/cef_request_context.h"
#include "include/wrapper/cef_helpers.h"

#import "BlinkChromiumRuntime.h"

typedef void (^BlinkChromiumOpenNewTabHandler)(NSString *_Nullable urlString);
typedef void (^BlinkChromiumPopupLifecycleHandler)(void);

@protocol BlinkChromiumHostViewOwner <NSObject>

- (void)hostViewDidMoveToWindow;
- (void)hostViewDidLayout;

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
- (void)clientDidRequestOpenNewTabWithURLString:(nullable NSString *)urlString;
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

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self.owner hostViewDidMoveToWindow];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self.owner hostViewDidLayout];
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
                                  public CefDisplayHandler,
                                  public CefLoadHandler,
                                  public CefLifeSpanHandler,
                                  public CefFocusHandler {
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
        if (BlinkChromiumTargetDispositionOpensTab(target_disposition)) {
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
            return false;
        }

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
    BOOL _didFinishClosing;
    BOOL _isClosingBrowser;
    NSWindow *_window;
    BlinkChromiumHostView *_hostView;
    BlinkChromiumBrowserStateSnapshot *_snapshot;
    NSMutableDictionary<NSNumber *, BlinkChromiumPopupWindowController *> *_pendingPopupControllers;
    BlinkChromiumOpenNewTabHandler _onOpenNewTab;
    BlinkChromiumPopupLifecycleHandler _onCreated;
    BlinkChromiumPopupLifecycleHandler _onClosed;
    CefRefPtr<BlinkChromiumClient> _client;
}

- (instancetype)initWithInitialURLString:(NSString *)initialURLString
                           popupFeatures:(const CefPopupFeatures&)popupFeatures
                             onOpenNewTab:(BlinkChromiumOpenNewTabHandler)onOpenNewTab
                                onCreated:(BlinkChromiumPopupLifecycleHandler)onCreated
                                 onClosed:(BlinkChromiumPopupLifecycleHandler)onClosed {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _initialURLString = [initialURLString copy];
    _pendingPopupControllers = [NSMutableDictionary dictionary];
    _onOpenNewTab = [onOpenNewTab copy];
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
    _window.title = BlinkChromiumWindowTitle(nil, _initialURLString);
    _window.contentView = _hostView;

    _client = new BlinkChromiumClient(self);
    [BlinkChromiumActivePopupControllers() addObject:self];

    return self;
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
    [self finishClosing];
    if (_window != nil) {
        [_window orderOut:nil];
        [_window close];
        _window = nil;
    }
}

- (void)hostViewDidMoveToWindow {
}

- (void)hostViewDidLayout {
    if (_client != nullptr && _client->HasBrowser()) {
        _client->WasResized();
    }
}

- (void)clientDidCreateBrowser {
    _didCreateBrowser = YES;
    if (_onCreated != nil) {
        _onCreated();
        _onCreated = nil;
    }
    [_window makeKeyAndOrderFront:nil];
    _client->FocusBrowser();
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
    _snapshot = [[BlinkChromiumBrowserStateSnapshot alloc] initWithURLString:urlString
                                                                       title:title
                                                                   canGoBack:canGoBack
                                                                canGoForward:canGoForward
                                                                   isLoading:isLoading];
    _window.title = BlinkChromiumWindowTitle(title, urlString ?: _initialURLString);
}

- (void)clientDidRequestOpenNewTabWithURLString:(NSString *)urlString {
    if (_onOpenNewTab != nil) {
        _onOpenNewTab(urlString);
    }
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

@implementation BlinkChromiumBrowserHost {
@private
    NSString *_tabIdentifier;
    NSString *_projectIdentifier;
    BOOL _browserCreationPending;
    BlinkChromiumHostView *_hostView;
    BlinkChromiumBrowserStateSnapshot *_snapshot;
    NSMutableDictionary<NSNumber *, BlinkChromiumPopupWindowController *> *_pendingPopupControllers;
    CefRefPtr<BlinkChromiumClient> _client;
}

- (instancetype)initWithTabIdentifier:(NSString *)tabIdentifier
                    projectIdentifier:(NSString *)projectIdentifier
                     initialURLString:(NSString *)initialURLString {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _tabIdentifier = [tabIdentifier copy];
    _projectIdentifier = [projectIdentifier copy];
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
    _client->LoadURL(BlinkChromiumStartupURL(urlString));
    [self ensureBrowserCreatedIfPossible];
}

- (void)focusBrowserView {
    if (_hostView.window != nil) {
        [_hostView.window makeFirstResponder:_hostView];
    }
    _client->FocusBrowser();
}

- (void)goBack {
    _client->GoBack();
}

- (void)goForward {
    _client->GoForward();
}

- (void)reload {
    _client->Reload();
}

- (void)invalidate {
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
    [self ensureBrowserCreatedIfPossible];
}

- (void)hostViewDidLayout {
    [self ensureBrowserCreatedIfPossible];
    if (_client != nullptr && _client->HasBrowser()) {
        _client->WasResized();
    }
}

- (void)clientDidCreateBrowser {
    _browserCreationPending = NO;
}

- (void)clientDidCloseBrowser {
    _browserCreationPending = NO;
}

- (void)clientDidReceiveInteraction {
    [self.delegate chromiumBrowserHostDidReceiveInteraction:self];
}

- (void)clientDidUpdateURLString:(NSString *)urlString
                           title:(NSString *)title
                       canGoBack:(BOOL)canGoBack
                    canGoForward:(BOOL)canGoForward
                       isLoading:(BOOL)isLoading {
    _snapshot = [[BlinkChromiumBrowserStateSnapshot alloc] initWithURLString:urlString
                                                                       title:title
                                                                   canGoBack:canGoBack
                                                                canGoForward:canGoForward
                                                                   isLoading:isLoading];
    [self.delegate chromiumBrowserHost:self didUpdate:_snapshot];
}

- (void)clientDidRequestOpenNewTabWithURLString:(NSString *)urlString {
    [self.delegate chromiumBrowserHost:self didRequestOpenNewTabWithURLString:urlString];
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
    if (_browserCreationPending || _client->HasBrowser() || _hostView.window == nil ||
        NSIsEmptyRect(_hostView.bounds)) {
        return;
    }

    BlinkChromiumRequestContext *requestContext =
        [[BlinkChromiumRuntime sharedRuntime] requestContextForProjectIdentifier:_projectIdentifier];
    if (requestContext == nil) {
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
