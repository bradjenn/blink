#import "BlinkChromiumRuntime.h"

#import <AppKit/AppKit.h>

#include <memory>

#include "include/base/cef_logging.h"
#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser_process_handler.h"
#include "include/cef_command_line.h"
#include "include/cef_request_context.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"

namespace {

NSString *const BlinkChromiumRuntimeErrorDomain = @"BlinkChromiumRuntime";

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

NSString *BlinkChromiumGlobalCachePath(void) {
    return [BlinkChromiumSupportRootPath() stringByAppendingPathComponent:@"global"];
}

NSString *BlinkChromiumSanitizedProjectIdentifier(NSString *projectIdentifier) {
    if (projectIdentifier.length == 0) {
        return @"project";
    }

    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._"];
    NSMutableString *result = [NSMutableString stringWithCapacity:projectIdentifier.length];

    for (NSUInteger index = 0; index < projectIdentifier.length; index += 1) {
        unichar character = [projectIdentifier characterAtIndex:index];
        if ([allowed characterIsMember:character]) {
            [result appendFormat:@"%C", character];
        } else {
            [result appendString:@"_"];
        }
    }

    return result.length > 0 ? result : @"project";
}

NSString *BlinkChromiumProjectCachePath(NSString *projectIdentifier) {
    NSString *sanitized = BlinkChromiumSanitizedProjectIdentifier(projectIdentifier);
    NSString *profilesRoot = [BlinkChromiumSupportRootPath() stringByAppendingPathComponent:@"profiles"];
    return [profilesRoot stringByAppendingPathComponent:sanitized];
}

BOOL BlinkChromiumEnsureDirectory(NSString *path, NSError **error) {
    return [NSFileManager.defaultManager createDirectoryAtPath:path
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:error];
}

class BlinkChromiumApp final : public CefApp, public CefBrowserProcessHandler {
public:
    explicit BlinkChromiumApp(BlinkChromiumRuntime *runtime)
        : runtime_(runtime) {}

    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override {
        return this;
    }

    void OnBeforeCommandLineProcessing(
        const CefString& process_type,
        CefRefPtr<CefCommandLine> command_line
    ) override {
        if (!process_type.empty()) {
            return;
        }

        command_line->AppendSwitch("use-mock-keychain");
    }

    void OnScheduleMessagePumpWork(int64_t delay_ms) override;

private:
    BlinkChromiumRuntime *runtime_;

    IMPLEMENT_REFCOUNTING(BlinkChromiumApp);
    DISALLOW_COPY_AND_ASSIGN(BlinkChromiumApp);
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
    CefScopedSendingEvent sendingEventScoper;
    [super sendEvent:event];
}

@end

@interface BlinkChromiumRequestContext ()
- (instancetype)initWithProjectIdentifier:(NSString *)projectIdentifier;
- (CefRefPtr<CefRequestContext>)requestContext;
@end

@implementation BlinkChromiumRequestContext {
@private
    CefRefPtr<CefRequestContext> _requestContext;
}

- (instancetype)initWithProjectIdentifier:(NSString *)projectIdentifier {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    NSString *cachePath = BlinkChromiumProjectCachePath(projectIdentifier);
    BlinkChromiumEnsureDirectory(cachePath, nil);

    CefRequestContextSettings settings;
    CefString(&settings.cache_path) = cachePath.UTF8String;
    settings.persist_session_cookies = true;

    _requestContext = CefRequestContext::CreateContext(settings, nullptr);
    return self;
}

- (CefRefPtr<CefRequestContext>)requestContext {
    return _requestContext;
}

@end

@interface BlinkChromiumRuntime ()
- (void)scheduleMessagePumpWorkAfterDelay:(int64_t)delayMS;
- (void)performMessageLoopWork;
@end

@implementation BlinkChromiumRuntime {
@private
    BOOL _started;
    NSInteger _messagePumpGeneration;
    NSMutableDictionary<NSString *, BlinkChromiumRequestContext *> *_requestContexts;
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
    NSString *globalCachePath = BlinkChromiumGlobalCachePath();
    if (!BlinkChromiumEnsureDirectory(rootPath, error) ||
        !BlinkChromiumEnsureDirectory(globalCachePath, error)) {
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
    CefString(&settings.cache_path) = [globalCachePath UTF8String];

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
    return YES;
}

- (BOOL)startIfNeeded {
    return [self startIfNeeded:nil];
}

- (void)shutdown {
    if (!_started) {
        return;
    }

    [_requestContexts removeAllObjects];
    _messagePumpGeneration += 1;

    CefShutdown();

    _app = nullptr;
    _libraryLoader.reset();
    _started = NO;
}

- (nullable BlinkChromiumRequestContext *)requestContextForProjectIdentifier:(NSString *)projectIdentifier {
    if (![self startIfNeeded:nil]) {
        return nil;
    }

    BlinkChromiumRequestContext *existing = _requestContexts[projectIdentifier];
    if (existing != nil) {
        return existing;
    }

    BlinkChromiumRequestContext *context =
        [[BlinkChromiumRequestContext alloc] initWithProjectIdentifier:projectIdentifier];
    _requestContexts[projectIdentifier] = context;
    return context;
}

- (void)scheduleMessagePumpWorkAfterDelay:(int64_t)delayMS {
    _messagePumpGeneration += 1;
    NSInteger generation = _messagePumpGeneration;
    uint64_t clampedDelay = delayMS > 0 ? (uint64_t)delayMS : 0;

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)clampedDelay * NSEC_PER_MSEC),
        dispatch_get_main_queue(),
        ^{
            if (generation != self->_messagePumpGeneration || !self->_started) {
                return;
            }

            [self performMessageLoopWork];
        }
    );
}

- (void)performMessageLoopWork {
    if (!_started) {
        return;
    }

    CefDoMessageLoopWork();
}

@end

namespace {

void BlinkChromiumApp::OnScheduleMessagePumpWork(int64_t delay_ms) {
    [runtime_ scheduleMessagePumpWorkAfterDelay:delay_ms];
}

}  // namespace
