#import "ObjCGuard.h"

BOOL MGRunCatching(void (^block)(void)) {
    @try {
        block();
        return YES;
    } @catch (NSException *e) {
        NSLog(@"[MacGlow] caught ObjC exception: %@ — %@", e.name, e.reason);
        return NO;
    }
}
