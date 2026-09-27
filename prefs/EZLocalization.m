// EZLocalization.m
#import "EZLocalization.h"

@implementation EZLocalization
@end

NSBundle *EZPrefsBundle(void) {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bundle = [NSBundle bundleForClass:[EZLocalization class]];
        if (bundle == nil) bundle = [NSBundle mainBundle];
    });
    return bundle;
}

NSString *EZLoc(NSString *key) {
    if (key == nil) return @"";
    return [EZPrefsBundle() localizedStringForKey:key value:key table:nil];
}

NSString *EZLocFormat(NSString *key, ...) {
    NSString *format = EZLoc(key);
    va_list args;
    va_start(args, key);
    NSString *result = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    return result;
}