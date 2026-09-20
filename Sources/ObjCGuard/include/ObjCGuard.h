#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` inside an @try/@catch. Returns YES if it completed without an
/// Objective-C exception, NO if one was raised (Swift can't catch these itself).
BOOL MGRunCatching(void (^_Nonnull block)(void));

NS_ASSUME_NONNULL_END
