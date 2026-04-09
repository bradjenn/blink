#import "BlinkChromiumRuntime.h"

#import <AppKit/AppKit.h>

#include <atomic>
#include <climits>
#include <memory>

#include "include/base/cef_logging.h"
#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser_process_handler.h"
#include "include/cef_command_line.h"
#include "include/cef_cookie.h"
#include "include/cef_request_context.h"
#include "include/cef_render_process_handler.h"
#include "include/cef_v8.h"
#include "include/internal/cef_types_content_settings.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"

namespace {

NSString *const BlinkChromiumRuntimeErrorDomain = @"BlinkChromiumRuntime";
const int32_t BlinkChromiumTimerDelayPlaceholder = INT_MAX;
const int64_t BlinkChromiumMaxTimerDelay = 1000 / 30;
NSString *const BlinkMainWorkspaceWindowIdentifier = @"BlinkMainWorkspaceWindow";
NSString *const BlinkChromiumPopupWindowIdentifier = @"BlinkChromiumPopupWindow";
NSString *const BlinkChromiumDisabledPasskeyFeatures =
    @"WebAuthentication,"
    @"WebAuthenticationBle,"
    @"WebAuthenticationCable,"
    @"AutofillReintroduceHybridPasskeyDropdownItem,"
    @"WebAuthenticationCableExtensionAnywhere,"
    @"WebAuthnUsePasskeyFromAnotherDeviceInContextMenu,"
    @"WebAuthenticationHybridLinking,"
    @"WebAuthenticationEnclaveAuthenticator,"
    @"WebAuthenticationICloudKeychainForGoogle,"
    @"WebAuthenticationICloudKeychainForActiveWithDrive,"
    @"WebAuthenticationICloudKeychainForActiveWithoutDrive,"
    @"WebAuthenticationICloudKeychainForInactiveWithDrive,"
    @"WebAuthenticationICloudKeychainForInactiveWithoutDrive,"
    @"WebAuthenticationAmbientSignin,"
    @"WebAuthenticationImmediateGet,"
    @"WebAuthenticationImmediateGetAutoselect,"
    @"PasswordManagerPasskeysEnabled,"
    @"WebAuthenticationPasskeyUpgrade,"
    @"CreatePasskeysInICloudKeychain,"
    @"DigitalCredentialsHybridLinking,"
    @"HybridPlatform,"
    @"HybridPlatform2,"
    @"BrowserProvidedPasskeysAvailable";
NSString *const BlinkChromiumDisabledBlinkFeatures =
    @"WebAuth,"
    @"WebAuthenticationAmbient,"
    @"WebAuthenticationChallengeUrl,"
    @"WebAuthenticationConditionalCreate,"
    @"WebAuthenticationRemoteDesktopSupport";
NSString *const BlinkChromiumDisableWebAuthnScript =
    @"(() => {"
    @"  const unsupported = () => new DOMException('WebAuthn is disabled in Blink.', 'NotSupportedError');"
    @"  const rejectUnsupported = () => Promise.reject(unsupported());"
    @"  const resolveFalse = () => Promise.resolve(false);"
    @"  const resolveEmptyObject = () => Promise.resolve({});"
    @"  const patchValue = (target, name, value) => {"
    @"    if (!target) return;"
    @"    try {"
    @"      Object.defineProperty(target, name, {"
    @"        configurable: true,"
    @"        enumerable: false,"
    @"        writable: true,"
    @"        value"
    @"      });"
    @"    } catch (_) {}"
    @"  };"
    @"  const patchGlobal = (target) => {"
    @"    if (!target) return;"
    @"    try {"
    @"      Object.defineProperty(target, 'PublicKeyCredential', {"
    @"        configurable: true,"
    @"        enumerable: false,"
    @"        get() { return undefined; }"
    @"      });"
    @"    } catch (_) {}"
    @"  };"
    @"  const patchCredentialMethods = (target) => {"
    @"    if (!target) return;"
    @"    patchValue(target, 'get', function(options) {"
    @"      if (options && (Object.prototype.hasOwnProperty.call(options, 'publicKey') || options.mediation === 'conditional')) {"
    @"        return rejectUnsupported();"
    @"      }"
    @"      return Promise.reject(unsupported());"
    @"    });"
    @"    patchValue(target, 'create', function(options) {"
    @"      if (options && Object.prototype.hasOwnProperty.call(options, 'publicKey')) {"
    @"        return rejectUnsupported();"
    @"      }"
    @"      return Promise.reject(unsupported());"
    @"    });"
    @"  };"
    @"  const patchPublicKeyCredentialStatics = (target) => {"
    @"    if (!target) return;"
    @"    patchValue(target, 'isConditionalMediationAvailable', resolveFalse);"
    @"    patchValue(target, 'isUserVerifyingPlatformAuthenticatorAvailable', resolveFalse);"
    @"    patchValue(target, 'getClientCapabilities', resolveEmptyObject);"
    @"  };"
    @"  const patchCredentialsContainer = () => {"
    @"    const credentials = navigator && navigator.credentials;"
    @"    patchCredentialMethods(credentials);"
    @"    patchCredentialMethods(globalThis.CredentialsContainer && globalThis.CredentialsContainer.prototype);"
    @"    patchValue(globalThis.Navigator && globalThis.Navigator.prototype, 'credentials', credentials);"
    @"  };"
    @"  const patchBluetooth = () => {"
    @"    if (typeof navigator === 'undefined') return;"
    @"    try {"
    @"      Object.defineProperty(navigator, 'bluetooth', {"
    @"        configurable: true,"
    @"        enumerable: false,"
    @"        get() { return undefined; }"
    @"      });"
    @"    } catch (_) {}"
    @"  };"
    @"  patchGlobal(globalThis);"
    @"  if (typeof window !== 'undefined') patchGlobal(window);"
    @"  if (typeof self !== 'undefined') patchGlobal(self);"
    @"  patchPublicKeyCredentialStatics(globalThis.PublicKeyCredential);"
    @"  patchCredentialsContainer();"
    @"  patchBluetooth();"
    @"})();";

BOOL BlinkChromiumIsPopupWindow(NSWindow *window) {
    if (window == nil) {
        return NO;
    }

    return [window.identifier isEqualToString:BlinkChromiumPopupWindowIdentifier];
}

BOOL BlinkChromiumIsCloseShortcutMenuItem(id sender) {
    if (![sender isKindOfClass:[NSMenuItem class]]) {
        return NO;
    }

    NSMenuItem *menuItem = (NSMenuItem *)sender;
    NSEventModifierFlags modifiers = menuItem.keyEquivalentModifierMask & NSEventModifierFlagDeviceIndependentFlagsMask;
    return [menuItem.keyEquivalent.lowercaseString isEqualToString:@"w"] &&
        modifiers == NSEventModifierFlagCommand;
}

NSString *BlinkChromiumApplicationName(void) {
    NSString *displayName = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if (displayName.length > 0) {
        return displayName;
    }

    NSString *bundleName = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"];
    if (bundleName.length > 0) {
        return bundleName;
    }

    return @"Blink";
}

NSString *BlinkChromiumFrameworkPath(void) {
    NSURL *frameworksURL = NSBundle.mainBundle.privateFrameworksURL;
    if (frameworksURL == nil) {
        return nil;
    }

    NSString *frameworkBundlePath = [frameworksURL.path
        stringByAppendingPathComponent:@"Chromium Embedded Framework.framework"];
    return [frameworkBundlePath stringByAppendingPathComponent:@"Chromium Embedded Framework"];
}

NSString *BlinkChromiumFrameworkBundlePath(void) {
    NSURL *frameworksURL = NSBundle.mainBundle.privateFrameworksURL;
    if (frameworksURL == nil) {
        return nil;
    }

    return [frameworksURL.path stringByAppendingPathComponent:@"Chromium Embedded Framework.framework"];
}

NSString *BlinkChromiumFrameworkResourcesPath(void) {
    NSString *frameworkBundlePath = BlinkChromiumFrameworkBundlePath();
    if (frameworkBundlePath.length == 0) {
        return nil;
    }

    return [frameworkBundlePath stringByAppendingPathComponent:@"Resources"];
}

NSString *BlinkChromiumHelperPath(void) {
    NSURL *frameworksURL = NSBundle.mainBundle.privateFrameworksURL;
    if (frameworksURL == nil) {
        return nil;
    }

    NSString *appName = BlinkChromiumApplicationName();
    NSString *helperName = [appName stringByAppendingString:@" Helper"];
    NSString *relativePath = [NSString stringWithFormat:@"%@.app/Contents/MacOS/%@", helperName, helperName];
    return [frameworksURL.path stringByAppendingPathComponent:relativePath];
}

NSString *BlinkChromiumSupportRootPath(void) {
    NSURL *baseURL = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                          inDomains:NSUserDomainMask].firstObject;
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier ?: @"com.blink.app";
    NSURL *rootURL = [[baseURL URLByAppendingPathComponent:@"Blink" isDirectory:YES]
        URLByAppendingPathComponent:bundleIdentifier isDirectory:YES];
    return [rootURL URLByAppendingPathComponent:@"Chromium" isDirectory:YES].path;
}

NSString *BlinkChromiumSanitizedProfileIdentifier(NSString *profileIdentifier) {
    if (profileIdentifier.length == 0) {
        return @"profile";
    }

    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._"];
    NSMutableString *result = [NSMutableString stringWithCapacity:profileIdentifier.length];

    for (NSUInteger index = 0; index < profileIdentifier.length; index += 1) {
        unichar character = [profileIdentifier characterAtIndex:index];
        if ([allowed characterIsMember:character]) {
            [result appendFormat:@"%C", character];
        } else {
            [result appendString:@"_"];
        }
    }

    return result.length > 0 ? result : @"profile";
}

NSString *BlinkChromiumProfileCachePath(NSString *profileIdentifier) {
    NSString *sanitized = BlinkChromiumSanitizedProfileIdentifier(profileIdentifier);
    return [BlinkChromiumSupportRootPath() stringByAppendingPathComponent:sanitized];
}

NSString *BlinkChromiumLegacyProfileCachePath(NSString *profileIdentifier) {
    NSString *sanitized = BlinkChromiumSanitizedProfileIdentifier(profileIdentifier);
    NSString *profilesRoot = [BlinkChromiumSupportRootPath() stringByAppendingPathComponent:@"profiles"];
    return [profilesRoot stringByAppendingPathComponent:sanitized];
}

BOOL BlinkChromiumEnsureDirectory(NSString *path, NSError **error) {
    return [NSFileManager.defaultManager createDirectoryAtPath:path
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:error];
}

void BlinkChromiumRemoveItemIfExists(NSString *path) {
    if (path.length == 0) {
        return;
    }

    NSFileManager *fileManager = NSFileManager.defaultManager;
    if (![fileManager fileExistsAtPath:path]) {
        return;
    }

    NSError *error = nil;
    if (![fileManager removeItemAtPath:path error:&error]) {
        NSLog(@"[ChromiumProfile] failed to remove %@: %@", path, error);
        return;
    }

    NSLog(@"[ChromiumProfile] removed %@", path);
}

void BlinkChromiumSetBooleanPreference(CefRefPtr<CefRequestContext> requestContext,
                                       const char *preferenceName,
                                       bool enabled) {
    if (requestContext == nullptr || preferenceName == nullptr) {
        return;
    }

    CefString name(preferenceName);
    if (!requestContext->HasPreference(name) || !requestContext->CanSetPreference(name)) {
        return;
    }

    CefRefPtr<CefValue> value = CefValue::Create();
    value->SetBool(enabled);

    CefString error;
    if (!requestContext->SetPreference(name, value, error) && !error.empty()) {
        NSLog(@"[ChromiumProfile] failed to set preference %s: %s",
              preferenceName,
              error.ToString().c_str());
    }
}

void BlinkChromiumBlockContentSetting(CefRefPtr<CefRequestContext> requestContext,
                                      cef_content_setting_types_t contentType) {
    if (requestContext == nullptr) {
        return;
    }

    requestContext->SetContentSetting("",
                                      "",
                                      contentType,
                                      CEF_CONTENT_SETTING_VALUE_BLOCK);
}

void BlinkChromiumMigrateLegacyProfileCachePathIfNeeded(NSString *profileIdentifier) {
    NSString *cachePath = BlinkChromiumProfileCachePath(profileIdentifier);
    NSString *legacyPath = BlinkChromiumLegacyProfileCachePath(profileIdentifier);
    NSFileManager *fileManager = NSFileManager.defaultManager;
    BOOL cacheExists = [fileManager fileExistsAtPath:cachePath];
    BOOL legacyExists = [fileManager fileExistsAtPath:legacyPath];
    if (cacheExists || !legacyExists) {
        return;
    }

    NSError *error = nil;
    NSString *rootPath = BlinkChromiumSupportRootPath();
    if (!BlinkChromiumEnsureDirectory(rootPath, &error)) {
        NSLog(@"[ChromiumProfile] failed to prepare root cache path %@: %@", rootPath, error);
        return;
    }

    if ([fileManager moveItemAtPath:legacyPath toPath:cachePath error:&error]) {
        NSLog(@"[ChromiumProfile] migrated profile cache %@ -> %@", legacyPath, cachePath);
    } else {
        NSLog(@"[ChromiumProfile] failed to migrate profile cache %@ -> %@: %@",
              legacyPath,
              cachePath,
              error);
    }
}

class BlinkChromiumApp final : public CefApp,
                               public CefBrowserProcessHandler,
                               public CefRenderProcessHandler {
public:
    explicit BlinkChromiumApp(BlinkChromiumRuntime *runtime)
        : runtime_(runtime) {}

    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override {
        return this;
    }

    CefRefPtr<CefRenderProcessHandler> GetRenderProcessHandler() override {
        return this;
    }

    void OnBeforeCommandLineProcessing(
        const CefString& process_type,
        CefRefPtr<CefCommandLine> command_line
    ) override {
        if (command_line == nullptr) {
            return;
        }

        command_line->AppendSwitch("disable-web-bluetooth");
        command_line->AppendSwitchWithValue("disable-features",
                                            BlinkChromiumDisabledPasskeyFeatures.UTF8String);
        command_line->AppendSwitchWithValue("disable-blink-features",
                                            BlinkChromiumDisabledBlinkFeatures.UTF8String);

        if (process_type.empty()) {
            command_line->AppendSwitch("use-mock-keychain");
        }
    }

    void OnContextCreated(CefRefPtr<CefBrowser> browser,
                          CefRefPtr<CefFrame> frame,
                          CefRefPtr<CefV8Context> context) override {
        CEF_REQUIRE_RENDERER_THREAD();

        if (frame == nullptr || context == nullptr || !frame->IsValid()) {
            return;
        }

        CefRefPtr<CefV8Value> retval;
        CefRefPtr<CefV8Exception> exception;
        if (!context->Eval(BlinkChromiumDisableWebAuthnScript.UTF8String,
                           "blink://disable-webauthn.js",
                           1,
                           retval,
                           exception) &&
            exception != nullptr) {
            NSLog(@"[ChromiumProfile] failed to disable WebAuthn in renderer: %s",
                  exception->GetMessage().ToString().c_str());
        }
    }

    void OnScheduleMessagePumpWork(int64_t delay_ms) override;

private:
    BlinkChromiumRuntime *runtime_;

    IMPLEMENT_REFCOUNTING(BlinkChromiumApp);
    DISALLOW_COPY_AND_ASSIGN(BlinkChromiumApp);
};

class BlinkChromiumCompletionCallback final : public CefCompletionCallback {
public:
    BlinkChromiumCompletionCallback() : completed_(false) {}

    void OnComplete() override {
        completed_ = true;
    }

    bool completed() const {
        return completed_;
    }

private:
    std::atomic_bool completed_;

    IMPLEMENT_REFCOUNTING(BlinkChromiumCompletionCallback);
    DISALLOW_COPY_AND_ASSIGN(BlinkChromiumCompletionCallback);
};

}  // namespace

@interface BlinkChromiumApplication : NSApplication <CefAppProtocol> {
@private
    BOOL handlingSendEvent_;
}
@end

@implementation BlinkChromiumApplication

- (BOOL)isHandlingSendEvent {
    return handlingSendEvent_;
}

- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
    handlingSendEvent_ = handlingSendEvent;
}

- (void)sendEvent:(NSEvent *)event {
    if (event.type == NSEventTypeKeyDown) {
        NSEventModifierFlags modifiers = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
        NSString *characters = event.charactersIgnoringModifiers.lowercaseString;
        NSWindow *keyWindow = self.keyWindow;
        if (modifiers == NSEventModifierFlagCommand &&
            [characters isEqualToString:@"w"] &&
            !BlinkChromiumIsPopupWindow(keyWindow)) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"BlinkCloseActiveTabShortcut" object:nil];
            return;
        }
    }

    CefScopedSendingEvent sendingEventScoper;
    [super sendEvent:event];
}

- (BOOL)sendAction:(SEL)action to:(id)target from:(id)sender {
    if (action == @selector(performClose:) &&
        BlinkChromiumIsCloseShortcutMenuItem(sender)) {
        NSWindow *keyWindow = self.keyWindow;
        if (!BlinkChromiumIsPopupWindow(keyWindow)) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"BlinkCloseActiveTabShortcut" object:nil];
            return YES;
        }
    }

    return [super sendAction:action to:target from:sender];
}

@end

@interface BlinkChromiumRequestContext ()
- (instancetype)initWithProfileIdentifier:(NSString *)profileIdentifier;
- (CefRefPtr<CefRequestContext>)requestContext;
- (void)requestContextDidInitialize;
@end

namespace {

class BlinkChromiumRequestContextHandler final : public CefRequestContextHandler {
public:
    explicit BlinkChromiumRequestContextHandler(BlinkChromiumRequestContext *owner)
        : owner_(owner) {}

    void OnRequestContextInitialized(CefRefPtr<CefRequestContext> request_context) override {
        if (owner_ == nil) {
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [owner_ requestContextDidInitialize];
        });
    }

private:
    __weak BlinkChromiumRequestContext *owner_ = nil;

    IMPLEMENT_REFCOUNTING(BlinkChromiumRequestContextHandler);
    DISALLOW_COPY_AND_ASSIGN(BlinkChromiumRequestContextHandler);
};

}  // namespace

@implementation BlinkChromiumRequestContext {
@private
    CefRefPtr<CefRequestContext> _requestContext;
    NSMutableArray<dispatch_block_t> *_readyCallbacks;
    NSString *_profileIdentifier;
    BOOL _ready;
}

- (instancetype)initWithProfileIdentifier:(NSString *)profileIdentifier {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    BlinkChromiumMigrateLegacyProfileCachePathIfNeeded(profileIdentifier);
    NSString *cachePath = BlinkChromiumProfileCachePath(profileIdentifier);
    BlinkChromiumEnsureDirectory(cachePath, nil);
    _readyCallbacks = [NSMutableArray array];
    _profileIdentifier = [profileIdentifier copy];

    CefRequestContextSettings settings;
    CefString(&settings.cache_path) = cachePath.UTF8String;
    settings.persist_session_cookies = true;

    _requestContext = CefRequestContext::CreateContext(
        settings,
        new BlinkChromiumRequestContextHandler(self)
    );
    return self;
}

- (CefRefPtr<CefRequestContext>)requestContext {
    return _requestContext;
}

- (BOOL)isReady {
    return _ready;
}

- (void)whenReady:(dispatch_block_t)callback {
    if (callback == nil) {
        return;
    }

    if (_ready) {
        dispatch_async(dispatch_get_main_queue(), callback);
        return;
    }

    [_readyCallbacks addObject:[callback copy]];
}

- (void)requestContextDidInitialize {
    if (_ready) {
        return;
    }

    BlinkChromiumSetBooleanPreference(_requestContext, "credentials_enable_passkeys", false);
    BlinkChromiumBlockContentSetting(_requestContext, CEF_CONTENT_SETTING_TYPE_BLUETOOTH_GUARD);
    BlinkChromiumBlockContentSetting(_requestContext, CEF_CONTENT_SETTING_TYPE_BLUETOOTH_SCANNING);

    _ready = YES;
    NSArray<dispatch_block_t> *callbacks = [_readyCallbacks copy];
    [_readyCallbacks removeAllObjects];

    for (dispatch_block_t callback in callbacks) {
        callback();
    }
}

@end

@interface BlinkChromiumRuntime ()
- (void)scheduleMessagePumpWorkAfterDelay:(int64_t)delayMS;
- (void)handleScheduledMessagePumpWork:(NSNumber *)delayMS;
- (void)handleMessagePumpTimer:(NSTimer *)timer;
- (void)performMessageLoopWork;
- (void)drainMessageLoopForDuration:(NSTimeInterval)duration;
- (void)flushCookieStores;
@end

@implementation BlinkChromiumRuntime {
@private
    BOOL _started;
    BOOL _messagePumpActive;
    BOOL _messagePumpReentrancyDetected;
    NSMutableDictionary<NSString *, BlinkChromiumRequestContext *> *_requestContexts;
    NSTimer *_messagePumpTimer;
    std::unique_ptr<CefScopedLibraryLoader> _libraryLoader;
    CefRefPtr<BlinkChromiumApp> _app;
}

+ (instancetype)sharedRuntime {
    static BlinkChromiumRuntime *runtime = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        runtime = [[self alloc] init];
    });
    return runtime;
}

+ (BOOL)canStartInCurrentBundle {
    return [NSFileManager.defaultManager fileExistsAtPath:BlinkChromiumFrameworkPath()] &&
        [NSFileManager.defaultManager
            fileExistsAtPath:[BlinkChromiumFrameworkResourcesPath() stringByAppendingPathComponent:@"icudtl.dat"]] &&
        [NSFileManager.defaultManager
            fileExistsAtPath:[BlinkChromiumFrameworkResourcesPath()
                stringByAppendingPathComponent:@"v8_context_snapshot.arm64.bin"]] &&
        [NSFileManager.defaultManager fileExistsAtPath:BlinkChromiumHelperPath()];
}

+ (void)prepareApplicationIfNeeded {
    if (NSApp == nil) {
        [BlinkChromiumApplication sharedApplication];
    }
}

- (instancetype)init {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _requestContexts = [NSMutableDictionary dictionary];
    return self;
}

- (BOOL)startIfNeeded:(NSError * _Nullable __autoreleasing *)error {
    if (_started) {
        return YES;
    }

    if (![[self class] canStartInCurrentBundle]) {
        if (error != nil) {
            *error = [NSError errorWithDomain:BlinkChromiumRuntimeErrorDomain
                                         code:1
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             @"Chromium framework or helper bundle is missing from the app bundle."
                                     }];
        }
        return NO;
    }

    [[self class] prepareApplicationIfNeeded];

    NSString *rootPath = BlinkChromiumSupportRootPath();
    if (!BlinkChromiumEnsureDirectory(rootPath, error)) {
        return NO;
    }

    _libraryLoader = std::make_unique<CefScopedLibraryLoader>();
    if (!_libraryLoader->LoadInMain()) {
        _libraryLoader.reset();
        if (error != nil) {
            *error = [NSError errorWithDomain:BlinkChromiumRuntimeErrorDomain
                                         code:2
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             @"Failed to load Chromium Embedded Framework from the app bundle."
                                     }];
        }
        return NO;
    }

    CefMainArgs mainArgs;
    _app = new BlinkChromiumApp(self);

    CefSettings settings;
    settings.no_sandbox = true;
    settings.external_message_pump = true;
    settings.persist_session_cookies = true;
    settings.log_severity = LOGSEVERITY_WARNING;
    CefString(&settings.browser_subprocess_path) = [BlinkChromiumHelperPath() UTF8String];
    CefString(&settings.framework_dir_path) = [BlinkChromiumFrameworkBundlePath() UTF8String];
    CefString(&settings.main_bundle_path) = [NSBundle.mainBundle.bundlePath UTF8String];
    CefString(&settings.resources_dir_path) = [BlinkChromiumFrameworkResourcesPath() UTF8String];
    CefString(&settings.locales_dir_path) = [BlinkChromiumFrameworkResourcesPath() UTF8String];
    CefString(&settings.root_cache_path) = [rootPath UTF8String];
    CefString(&settings.cache_path) = [rootPath UTF8String];

    if (!CefInitialize(mainArgs, settings, _app.get(), nullptr)) {
        const int exitCode = CefGetExitCode();
        _app = nullptr;
        _libraryLoader.reset();
        if (error != nil) {
            *error = [NSError errorWithDomain:BlinkChromiumRuntimeErrorDomain
                                         code:3
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             [NSString stringWithFormat:@"CEF initialization failed with exit code %d.", exitCode]
                                     }];
        }
        return NO;
    }

    _started = YES;
    [self handleScheduledMessagePumpWork:@0];
    return YES;
}

- (BOOL)startIfNeeded {
    return [self startIfNeeded:nil];
}

- (void)shutdown {
    if (!_started) {
        return;
    }

    [self drainMessageLoopForDuration:0.25];
    [self flushCookieStores];
    [self drainMessageLoopForDuration:0.25];
    [_requestContexts removeAllObjects];
    [self invalidateMessagePumpTimer];

    CefShutdown();

    _app = nullptr;
    _libraryLoader.reset();
    _started = NO;
}

- (nullable BlinkChromiumRequestContext *)requestContextForProfileIdentifier:(NSString *)profileIdentifier {
    if (![self startIfNeeded:nil]) {
        return nil;
    }

    BlinkChromiumRequestContext *existing = _requestContexts[profileIdentifier];
    if (existing != nil) {
        return existing;
    }

    BlinkChromiumRequestContext *context =
        [[BlinkChromiumRequestContext alloc] initWithProfileIdentifier:profileIdentifier];
    _requestContexts[profileIdentifier] = context;
    return context;
}

- (void)scheduleMessagePumpWorkAfterDelay:(int64_t)delayMS {
    [self performSelectorOnMainThread:@selector(handleScheduledMessagePumpWork:)
                           withObject:@(delayMS)
                        waitUntilDone:NO];
}

- (void)handleScheduledMessagePumpWork:(NSNumber *)delayMS {
    if (!_started) {
        return;
    }

    int64_t delay = delayMS.longLongValue;
    if (delay == BlinkChromiumTimerDelayPlaceholder && _messagePumpTimer != nil) {
        return;
    }

    [self invalidateMessagePumpTimer];

    if (delay <= 0) {
        [self performMessageLoopWork];
        return;
    }

    if (delay > BlinkChromiumMaxTimerDelay) {
        delay = BlinkChromiumMaxTimerDelay;
    }

    NSTimer *timer = [NSTimer timerWithTimeInterval:(double)delay / 1000.0
                                             target:self
                                           selector:@selector(handleMessagePumpTimer:)
                                           userInfo:nil
                                            repeats:NO];
    _messagePumpTimer = timer;

    NSRunLoop *runLoop = NSRunLoop.currentRunLoop;
    [runLoop addTimer:timer forMode:NSRunLoopCommonModes];
    [runLoop addTimer:timer forMode:NSEventTrackingRunLoopMode];
}

- (void)handleMessagePumpTimer:(NSTimer *)timer {
    if (timer != _messagePumpTimer) {
        return;
    }

    [self invalidateMessagePumpTimer];
    [self performMessageLoopWork];
}

- (void)performMessageLoopWork {
    if (!_started) {
        return;
    }

    if (_messagePumpActive) {
        _messagePumpReentrancyDetected = YES;
        return;
    }

    _messagePumpReentrancyDetected = NO;
    _messagePumpActive = YES;
    CefDoMessageLoopWork();
    _messagePumpActive = NO;

    if (_messagePumpReentrancyDetected) {
        [self scheduleMessagePumpWorkAfterDelay:0];
    } else if (_messagePumpTimer == nil) {
        [self scheduleMessagePumpWorkAfterDelay:BlinkChromiumTimerDelayPlaceholder];
    }
}

- (void)invalidateMessagePumpTimer {
    if (_messagePumpTimer == nil) {
        return;
    }

    [_messagePumpTimer invalidate];
    _messagePumpTimer = nil;
}

- (void)drainMessageLoopForDuration:(NSTimeInterval)duration {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:MAX(0.0, duration)];
    while ([deadline timeIntervalSinceNow] > 0) {
        [self performMessageLoopWork];
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                               beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}

- (void)flushCookieStores {
    NSArray<BlinkChromiumRequestContext *> *contexts = [_requestContexts.allValues copy];
    CefRefPtr<CefRequestContext> globalContext = CefRequestContext::GetGlobalContext();
    auto flushManager = ^(CefRefPtr<CefCookieManager> manager) {
        [self flushCookieManager:manager];
    };

    if (globalContext != nullptr) {
        flushManager(globalContext->GetCookieManager(nullptr));
    }

    for (BlinkChromiumRequestContext *context in contexts) {
        CefRefPtr<CefRequestContext> requestContext = [context requestContext];
        flushManager(requestContext != nullptr ? requestContext->GetCookieManager(nullptr) : nullptr);
    }
}

- (void)flushCookieManager:(CefRefPtr<CefCookieManager>)manager {
    if (manager == nullptr) {
        return;
    }

    CefRefPtr<BlinkChromiumCompletionCallback> callback = new BlinkChromiumCompletionCallback();
    if (!manager->FlushStore(callback)) {
        return;
    }

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
    while (!callback->completed() && [deadline timeIntervalSinceNow] > 0) {
        [self performMessageLoopWork];
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                               beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}

- (void)removeStorageForProfileIdentifier:(NSString *)profileIdentifier {
    if (profileIdentifier.length == 0) {
        return;
    }

    BlinkChromiumRequestContext *context = _requestContexts[profileIdentifier];
    if (context != nil) {
        CefRefPtr<CefRequestContext> requestContext = [context requestContext];
        [self flushCookieManager:requestContext != nullptr ? requestContext->GetCookieManager(nullptr) : nullptr];
        [_requestContexts removeObjectForKey:profileIdentifier];
        if (_started) {
            [self drainMessageLoopForDuration:0.25];
        }
    }

    BlinkChromiumRemoveItemIfExists(BlinkChromiumProfileCachePath(profileIdentifier));
    BlinkChromiumRemoveItemIfExists(BlinkChromiumLegacyProfileCachePath(profileIdentifier));
}

@end

namespace {

void BlinkChromiumApp::OnScheduleMessagePumpWork(int64_t delay_ms) {
    [runtime_ scheduleMessagePumpWorkAfterDelay:delay_ms];
}

}  // namespace
