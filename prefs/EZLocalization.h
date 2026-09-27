// EZLocalization.h
#ifndef EZLocalization_h
#define EZLocalization_h

#import <Foundation/Foundation.h>

@interface EZLocalization : NSObject
@end

NSBundle *EZPrefsBundle(void);
NSString *EZLoc(NSString *key);
NSString *EZLocFormat(NSString *key, ...);

#endif