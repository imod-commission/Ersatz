// Ersatz - Replace any text system-wide!
// By Skitty

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <roothide.h>
#include <substrate.h>

static NSString *bundleIdentifier = @"xyz.skitty.ersatz";
#define settingsPath jbroot(@"/var/mobile/Library/Preferences/")

static BOOL enabled = YES;
static NSMutableDictionary *settings;
static NSMutableDictionary *keyedSettings;
static NSDictionary *strings;
static NSArray *orderedFinds;

static char kErsatzPendingRefitKey;

// ==================== 偏好加载 ====================
void refreshPrefs() {
    CFArrayRef keyList = CFPreferencesCopyKeyList((CFStringRef)bundleIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (keyList) {
        settings = (NSMutableDictionary *)CFBridgingRelease(CFPreferencesCopyMultiple(keyList, (CFStringRef)bundleIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
        CFRelease(keyList);
    } else {
        settings = nil;
    }

    if (!settings) {
        settings = [[NSMutableDictionary alloc] initWithContentsOfFile:[NSString stringWithFormat:@"%@%@.plist", settingsPath, bundleIdentifier]];
    }

    keyedSettings = [[NSMutableDictionary alloc] init];
    strings = [[NSMutableDictionary alloc] init];

    NSString *selfBundle = [[NSBundle mainBundle] bundleIdentifier];
    if (selfBundle == nil) selfBundle = @"";

    for (NSDictionary *obj in settings[@"strings"]) {
        NSString *phrase = obj[@"phrase"];
        if (phrase == nil || phrase.length == 0) continue;

        NSString *mode = obj[@"filterMode"];
        if (mode == nil) mode = @"all";
        NSArray *ruleApps = obj[@"apps"];
        if (ruleApps == nil) ruleApps = @[];

        BOOL applies = YES;
        if ([mode isEqualToString:@"all"]) {
            applies = YES;
        } else if ([mode isEqualToString:@"whitelist"]) {
            applies = (ruleApps.count > 0) && [ruleApps containsObject:selfBundle];
        } else if ([mode isEqualToString:@"blacklist"]) {
            applies = !(ruleApps.count > 0 && [ruleApps containsObject:selfBundle]);
        }

        if (!applies) continue;

        [strings setValue:obj[@"replacement"] forKey:phrase];
        [keyedSettings setValue:obj forKey:phrase];
    }

    orderedFinds = [[strings allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSUInteger lenA = [a length];
        NSUInteger lenB = [b length];
        if (lenA > lenB) return NSOrderedAscending;
        if (lenA < lenB) return NSOrderedDescending;
        return [a localizedCaseInsensitiveCompare:b];
    }];
}

static void PreferencesChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    refreshPrefs();
}

// ==================== 单条替换 ====================
NSString *stringWithReplacement(NSString *origString, NSString *find, NSString *replace, BOOL caseSensitive) {
    if (origString == nil || find == nil || replace == nil) return origString;
    if (caseSensitive) {
        return [origString stringByReplacingOccurrencesOfString:find withString:replace];
    } else {
        return [origString stringByReplacingOccurrencesOfString:find withString:replace options:NSCaseInsensitiveSearch range:NSMakeRange(0, [origString length])];
    }
}

NSAttributedString *attributedStringWithReplacement(NSAttributedString *origString, NSString *find, NSString *replace) {
    if (origString == nil || find == nil || replace == nil) return origString;
    NSMutableAttributedString *newString = [origString mutableCopy];
    while ([newString.mutableString containsString:find]) {
        NSRange range = [newString.mutableString rangeOfString:find];
        NSMutableAttributedString *replaceString = [[NSMutableAttributedString alloc] initWithString:replace];
        [newString enumerateAttributesInRange:range options:0 usingBlock:^(NSDictionary *attrs, NSRange range, BOOL *stop) {
            [replaceString addAttributes:attrs range:NSMakeRange(0, replaceString.length)];
        }];
        [newString replaceCharactersInRange:range withAttributedString:replaceString];
    }
    return [newString copy];
}

// ==================== 应用全部规则（含 compress 判定） ====================
static NSString *applyRulesForString(NSString *text, BOOL *outShouldCompress) {
    if (text == nil) {
        if (outShouldCompress) *outShouldCompress = NO;
        return nil;
    }
    NSString *newText = text;
    BOOL shouldCompress = NO;

    for (NSString *find in orderedFinds) {
        NSDictionary *rule = [keyedSettings objectForKey:find];
        if (rule == nil) continue;

        NSString *before = newText;
        newText = stringWithReplacement(newText, find, [strings objectForKey:find], [[rule objectForKey:@"caseSensitive"] boolValue]);

        if (![before isEqualToString:newText]) {
            if ([[rule objectForKey:@"compress"] boolValue]) shouldCompress = YES;
        }
    }

    if (outShouldCompress) *outShouldCompress = shouldCompress;
    return newText;
}

static NSAttributedString *applyRulesForAttributedString(NSAttributedString *attr, BOOL *outShouldCompress) {
    if (attr == nil) {
        if (outShouldCompress) *outShouldCompress = NO;
        return nil;
    }
    NSAttributedString *newText = attr;
    BOOL shouldCompress = NO;

    for (NSString *find in orderedFinds) {
        NSDictionary *rule = [keyedSettings objectForKey:find];
        if (rule == nil) continue;

        NSAttributedString *before = newText;
        newText = attributedStringWithReplacement(newText, find, [strings objectForKey:find]);

        if (![before.string isEqualToString:newText.string]) {
            if ([[rule objectForKey:@"compress"] boolValue]) shouldCompress = YES;
        }
    }

    if (outShouldCompress) *outShouldCompress = shouldCompress;
    return newText;
}

// ==================== 宽度 & 压缩 ====================
static CGFloat availableWidthForLabel(UILabel *label) {
    CGFloat w = label.bounds.size.width;
    if (w <= 0) w = label.preferredMaxLayoutWidth;
    if (w <= 0) w = label.frame.size.width;
    return w;
}

static NSAttributedString *fittedAttributedStringForLabel(NSString *text, UILabel *label, BOOL *outWidthKnown) {
    if (outWidthKnown) *outWidthKnown = NO;
    if (text.length == 0) return nil;

    CGFloat availableWidth = availableWidthForLabel(label);
    if (availableWidth <= 0) return nil; // 宽度未知
    if (outWidthKnown) *outWidthKnown = YES;

    UIFont *font = label.font;
    if (font == nil) font = [UIFont systemFontOfSize:17];

    NSAttributedString *natural = [[NSAttributedString alloc] initWithString:text
                                                                   attributes:@{NSFontAttributeName: font}];
    CGFloat naturalWidth = [natural size].width;

    if (naturalWidth <= availableWidth) return nil; // 放得下

    NSMutableAttributedString *m = [natural mutableCopy];
    NSInteger count = (NSInteger)text.length;

    CGFloat maxKernPerChar = font.pointSize * 0.12;
    CGFloat neededReduction = naturalWidth - availableWidth;
    CGFloat maxTotalKernReduction = (count > 1) ? (maxKernPerChar * (count - 1)) : 0.0;

    if (maxTotalKernReduction > 0) {
        CGFloat kernReduction = MIN(neededReduction, maxTotalKernReduction);
        CGFloat kern = -kernReduction / (CGFloat)(count - 1);
        [m addAttribute:NSKernAttributeName value:@(kern) range:NSMakeRange(0, m.length)];
    }

    CGFloat afterKern = [m size].width;
    if (afterKern > availableWidth) {
        CGFloat ratio = availableWidth / afterKern;
        if (ratio < 0.55) ratio = 0.55;
        [m addAttribute:NSExpansionAttributeName value:@(ratio - 1.0) range:NSMakeRange(0, m.length)];
    }

    return m;
}

static BOOL isAlreadyAdjusted(NSAttributedString *attr) {
    if (attr.length == 0) return NO;
    __block BOOL hasKern = NO;
    __block BOOL hasExpansion = NO;
    [attr enumerateAttribute:NSKernAttributeName
                     inRange:NSMakeRange(0, attr.length)
                     options:0
                  usingBlock:^(id value, NSRange range, BOOL *stop) {
        if (value != nil) hasKern = YES;
    }];
    [attr enumerateAttribute:NSExpansionAttributeName
                     inRange:NSMakeRange(0, attr.length)
                     options:0
                  usingBlock:^(id value, NSRange range, BOOL *stop) {
        if (value != nil) hasExpansion = YES;
    }];
    return hasKern || hasExpansion;
}

// ==================== Hook: UILabel ====================
%hook UILabel

- (void)setText:(NSString *)text {
    if (enabled && orderedFinds.count > 0 && self.tag != 317) {
        NSString *orig = text;
        BOOL shouldCompress = NO;
        NSString *newText = applyRulesForString(text, &shouldCompress);

        if (orig && newText && ![orig isEqualToString:newText]) {
            if (shouldCompress) {
                BOOL widthKnown = NO;
                NSAttributedString *fitted = fittedAttributedStringForLabel(newText, self, &widthKnown);
                if (fitted) {
                    objc_setAssociatedObject(self, &kErsatzPendingRefitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    [self setAttributedText:fitted];
                    return;
                } else if (!widthKnown) {
                    // 宽度未知，pending 存原文，等 layoutSubviews 再处理
                    objc_setAssociatedObject(self, &kErsatzPendingRefitKey, orig, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                } else {
                    // 宽度已知但放得下，不需要 pending
                    objc_setAssociatedObject(self, &kErsatzPendingRefitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            } else {
                // 匹配的规则都没开 compress
                objc_setAssociatedObject(self, &kErsatzPendingRefitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        } else {
            // 没有规则改了文本，清旧 pending
            objc_setAssociatedObject(self, &kErsatzPendingRefitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        text = newText;
    }
    %orig;
}

- (void)layoutSubviews {
    %orig;

    if (!enabled || orderedFinds.count == 0 || self.tag == 317) return;

    NSString *pending = objc_getAssociatedObject(self, &kErsatzPendingRefitKey);
    if (pending == nil) return;

    BOOL shouldCompress = NO;
    NSString *newText = applyRulesForString(pending, &shouldCompress);

    // 规则不再生效（用户关了开关 / 改了规则）→ 清 pending
    if (!shouldCompress || newText == nil || [pending isEqualToString:newText]) {
        objc_setAssociatedObject(self, &kErsatzPendingRefitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    BOOL widthKnown = NO;
    NSAttributedString *fitted = fittedAttributedStringForLabel(newText, self, &widthKnown);

    if (fitted) {
        // 成功处理 → 清 pending，写入压缩结果
        objc_setAssociatedObject(self, &kErsatzPendingRefitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self setAttributedText:fitted];
    } else if (!widthKnown) {
        // 宽度依然未知 → 保留 pending，等下一次 layoutSubviews 再试
        objc_setAssociatedObject(self, &kErsatzPendingRefitKey, pending, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        // 宽度已知但放得下 → 不需要压
        objc_setAssociatedObject(self, &kErsatzPendingRefitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)setAttributedText:(NSAttributedString *)attributedText {
    if (enabled && orderedFinds.count > 0 && self.tag != 317 && !isAlreadyAdjusted(attributedText)) {
        NSAttributedString *orig = attributedText;
        BOOL shouldCompress = NO;
        NSAttributedString *newText = applyRulesForAttributedString(attributedText, &shouldCompress);

        if (orig && newText && ![orig.string isEqualToString:newText.string]) {
            if (shouldCompress) {
                BOOL widthKnown = NO;
                NSAttributedString *fitted = fittedAttributedStringForLabel(newText.string, self, &widthKnown);
                if (fitted) {
                    objc_setAssociatedObject(self, &kErsatzPendingRefitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    %orig(fitted);
                    return;
                } else if (!widthKnown) {
                    // 宽度未知 → 存 pending（用原文的 string），等 layoutSubviews
                    objc_setAssociatedObject(self, &kErsatzPendingRefitKey, orig.string, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                } else {
                    objc_setAssociatedObject(self, &kErsatzPendingRefitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            } else {
                objc_setAssociatedObject(self, &kErsatzPendingRefitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            %orig(newText);
            return;
        }
    }
    %orig;
}

%end

// ==================== Hook: UITextView ====================
%hook UITextView
- (void)setText:(NSString *)text {
    if (enabled && orderedFinds.count > 0) {
        BOOL unused = NO;
        text = applyRulesForString(text, &unused);
    }
    %orig;
}
- (void)setAttributedText:(NSAttributedString *)attributedText {
    if (enabled && orderedFinds.count > 0) {
        BOOL unused = NO;
        attributedText = applyRulesForAttributedString(attributedText, &unused);
    }
    %orig;
}
%end

// ==================== Hook: SBApplication ====================
%hook SBApplication
- (void)setDisplayName:(id)text {
    if (enabled && orderedFinds.count > 0) {
        BOOL unused = NO;
        text = applyRulesForString(text, &unused);
    }
    %orig;
}
- (id)displayName {
    if (enabled && orderedFinds.count > 0) {
        NSString *text = %orig;
        BOOL unused = NO;
        text = applyRulesForString(text, &unused);
        return text;
    }
    return %orig;
}
%end

// ==================== Hook: SBFolder ====================
%hook SBFolder
- (void)setDisplayName:(id)text {
    if (enabled && orderedFinds.count > 0) {
        BOOL unused = NO;
        text = applyRulesForString(text, &unused);
    }
    %orig;
}
- (id)displayName {
    if (enabled && orderedFinds.count > 0) {
        NSString *text = %orig;
        BOOL unused = NO;
        text = applyRulesForString(text, &unused);
        return text;
    }
    return %orig;
}
%end

%ctor {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback) PreferencesChangedCallback, (CFStringRef)[NSString stringWithFormat:@"%@.prefschanged", bundleIdentifier], NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    refreshPrefs();
}