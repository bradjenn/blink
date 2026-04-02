#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class BlinkChromiumRequestContext;

@interface BlinkChromiumRuntime : NSObject

+ (instancetype)sharedRuntime;
+ (BOOL)canStartInCurrentBundle;
+ (void)prepareApplicationIfNeeded;

- (BOOL)startIfNeeded:(NSError * _Nullable * _Nullable)error;
- (BOOL)startIfNeeded;
- (void)shutdown;
- (nullable BlinkChromiumRequestContext *)requestContextForProjectIdentifier:(NSString *)projectIdentifier;

@end

@interface BlinkChromiumRequestContext : NSObject

- (BOOL)isReady;
- (void)whenReady:(dispatch_block_t)callback;

@end

NS_ASSUME_NONNULL_END
