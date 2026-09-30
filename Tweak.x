// Ersatz - Replace any text system-wide!
// By Skitty

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <roothide.h>
#include <stdlib.h>
#include <substrate.h>

static NSString *bundleIdentifier = @"xyz.skitty.ersatz";
#define settingsPath jbroot(@"/var/mobile/Library/Preferences/")

static BOOL enabled = YES;
static NSMutableDictionary *settings;
static NSMutableDictionary *keyedSettings;
static NSDictionary *strings;
static NSArray *orderedFinds;

#pragma mark - 参数

#define kTimeLimit      0.05
#define kBreakTime      0.5
#define kAttrMaxIter    100
#define kSlowMs         8.0
#define kMaxTextLen     1000
#define kMaxAttrLen     1000
#define kMinExpandRatio 0.55
#define kMaxLogSize     (512 * 1024)
#define kLogCheckEvery  200
#define NOW_SEC()       ((double)[NSDate timeIntervalSinceReferenceDate])

static double gBreakUntil = 0;

#pragma mark - 日志

static dispatch_queue_t gLogQueue;
static NSFileHandle *gLogFileHandle;
static NSString *gLogPath;
static NSUInteger gLogWriteCount = 0;

static NSString *safeTruncate(NSString *s, NSUInteger maxChars) {
    if (s == nil) return @"";
    if (s.length <= maxChars) return s;
    NSRange r = [s rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, maxChars)];
    NSString *out = [s substringWithRange:r];
    return [out stringByAppendingString:@"…"];
}

static void rotateLogIfNeeded(void) {
    if (!gLogPath) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:gLogPath error:nil];
    unsigned long long size = [attrs fileSize];
    if (size < kMaxLogSize) return;

    if (gLogFileHandle) {
        [gLogFileHandle closeFile];
        gLogFileHandle = nil;
    }

    NSString *oldPath = [gLogPath stringByAppendingString:@".old"];
    [fm removeItemAtPath:oldPath error:nil];
    [fm moveItemAtPath:gLogPath toPath:oldPath error:nil];

    [fm createFileAtPath:gLogPath contents:nil attributes:nil];
    gLogFileHandle = [NSFileHandle fileHandleForWritingAtPath:gLogPath];
}

static void logInit(void) {
    gLogQueue = dispatch_queue_create("xyz.skitty.ersatz.log", DISPATCH_QUEUE_SERIAL);
    gLogPath = [jbroot(@"/var/mobile/Library/Logs/Ersatz.log") copy];
    NSString *dir = [gLogPath stringByDeletingLastPathComponent];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSDictionary *attrs = [fm attributesOfItemAtPath:gLogPath error:nil];
    if ([attrs fileSize] >= kMaxLogSize) {
        NSString *oldPath = [gLogPath stringByAppendingString:@".old"];
        [fm removeItemAtPath:oldPath error:nil];
        [fm moveItemAtPath:gLogPath toPath:oldPath error:nil];
    }

    if (![fm fileExistsAtPath:gLogPath]) {
        [fm createFileAtPath:gLogPath contents:nil attributes:nil];
    }
    gLogFileHandle = [NSFileHandle fileHandleForWritingAtPath:gLogPath];

    if (gLogFileHandle) {
        [gLogFileHandle seekToEndOfFile];
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        NSString *line = [NSString stringWithFormat:@"\n===== session %@ =====\n", [df stringFromDate:[NSDate date]]];
        [gLogFileHandle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    }
}

static void elog(NSString *fmt, ...) {
    if (!gLogFileHandle) return;
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"HH:mm:ss.SSS";
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [df stringFromDate:[NSDate date]], msg];

    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) data = [line dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
    if (data == nil) return;

    dispatch_async(gLogQueue, ^{
        @try {
            [gLogFileHandle writeData:data];
            gLogWriteCount++;
            if (gLogWriteCount >= kLogCheckEvery) {
                gLogWriteCount = 0;
                rotateLogIfNeeded();
            }
        } @catch (NSException *e) {}
    });
}

#pragma mark - 首字符预过滤

static uint8_t *gFirstCharMap = NULL;

static void rebuildMap(void) {
    if (gFirstCharMap) { free(gFirstCharMap); gFirstCharMap = NULL; }
    if (orderedFinds.count == 0) return;
    gFirstCharMap = (uint8_t *)calloc(65536, 1);
    if (!gFirstCharMap) return;
    for (NSString *p in orderedFinds) {
        if (p.length == 0) continue;
        unichar c = [p characterAtIndex:0];
        gFirstCharMap[c] = 1;
    }
}

static BOOL mayContainAny(NSString *text) {
    if (!gFirstCharMap) return YES;
    NSUInteger len = text.length;
    if (len == 0) return NO;
    for (NSUInteger i = 0; i < len; i++) {
        if (gFirstCharMap[[text characterAtIndex:i]]) return YES;
    }
    return NO;
}

#pragma mark - 缓存

static NSCache<NSString *, NSDictionary *> *gReplaceCache;

static const void *kPendingKey = &kPendingKey;

#pragma mark - Preferences

void refreshPrefs(void) {
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

    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    if (bid == nil) bid = @"";

    for (NSDictionary *obj in settings[@"strings"]) {
        NSString *phrase = obj[@"phrase"];
        if (phrase == nil || phrase.length == 0) continue;

        NSString *mode = obj[@"filterMode"];
        if (mode == nil) mode = @"all";
        NSArray *ruleApps = obj[@"apps"];
        if (ruleApps == nil) ruleApps = @[];

        BOOL ok = YES;
        if ([mode isEqualToString:@"all"]) {
            ok = YES;
        } else if ([mode isEqualToString:@"whitelist"]) {
            ok = (ruleApps.count > 0) && [ruleApps containsObject:bid];
        } else if ([mode isEqualToString:@"blacklist"]) {
            ok = !(ruleApps.count > 0 && [ruleApps containsObject:bid]);
        }
        if (!ok) continue;

        [strings setValue:obj[@"replacement"] forKey:phrase];
        [keyedSettings setValue:obj forKey:phrase];
    }

    orderedFinds = [[strings allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSUInteger la = [a length];
        NSUInteger lb = [b length];
        if (la > lb) return NSOrderedAscending;
        if (la < lb) return NSOrderedDescending;
        return [a localizedCaseInsensitiveCompare:b];
    }];

    [gReplaceCache removeAllObjects];
    rebuildMap();

    elog(@"prefs refresh | bid=%@ | rules=%lu", bid, (unsigned long)orderedFinds.count);
}

static void PrefsChanged(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef u) {
    refreshPrefs();
}

#pragma mark - 替换工具

static BOOL isWordChar(unichar c) {
    if (c == '_') return YES;
    if (c < 128) {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
    }
    return [[NSCharacterSet alphanumericCharacterSet] characterIsMember:c];
}

static NSString *doReplace(NSString *s, NSString *find, NSString *repl, BOOL cs) {
    if (s == nil || find == nil || repl == nil) return s;
    if (cs) return [s stringByReplacingOccurrencesOfString:find withString:repl];
    return [s stringByReplacingOccurrencesOfString:find withString:repl options:NSCaseInsensitiveSearch range:NSMakeRange(0, [s length])];
}

static NSString *doReplaceWholeWord(NSString *s, NSString *find, NSString *repl, BOOL cs) {
    if (s == nil || find == nil || repl == nil) return s;
    if (s.length == 0 || find.length == 0) return s;

    NSStringCompareOptions opts = cs ? 0 : NSCaseInsensitiveSearch;
    NSUInteger srcLen = s.length;
    NSMutableString *out = [NSMutableString stringWithCapacity:srcLen];
    NSUInteger lastEnd = 0;
    NSRange searchRange = NSMakeRange(0, srcLen);
    BOOL anyHit = NO;

    while (searchRange.location < srcLen) {
        NSRange r = [s rangeOfString:find options:opts range:searchRange];
        if (r.location == NSNotFound) break;

        BOOL leftOK = YES;
        if (r.location > 0) {
            if (isWordChar([s characterAtIndex:r.location - 1])) leftOK = NO;
        }
        BOOL rightOK = YES;
        NSUInteger rightIdx = r.location + r.length;
        if (rightIdx < srcLen) {
            if (isWordChar([s characterAtIndex:rightIdx])) rightOK = NO;
        }

        if (leftOK && rightOK) {
            [out appendString:[s substringWithRange:NSMakeRange(lastEnd, r.location - lastEnd)]];
            [out appendString:repl];
            lastEnd = r.location + r.length;
            anyHit = YES;
        }

        searchRange.location = r.location + 1;
        if (searchRange.location >= srcLen) break;
        searchRange.length = srcLen - searchRange.location;
    }

    if (!anyHit) return s;
    [out appendString:[s substringWithRange:NSMakeRange(lastEnd, srcLen - lastEnd)]];
    return out;
}

static NSAttributedString *attrReplace(NSAttributedString *orig, NSString *find, NSString *repl) {
    if (orig == nil || find == nil || repl == nil) return orig;
    NSMutableAttributedString *m = [orig mutableCopy];
    BOOL single = [repl containsString:find];
    NSUInteger iter = 0;

    while ([m.mutableString containsString:find]) {
        if (single) {
            if (iter >= 1) break;
        } else {
            if (iter >= kAttrMaxIter) {
                elog(@"ATTR_LOOP_LIMIT | find=\"%@\" repl=\"%@\"", find, repl);
                break;
            }
        }
        iter++;

        NSRange r = [m.mutableString rangeOfString:find];
        NSMutableAttributedString *rs = [[NSMutableAttributedString alloc] initWithString:repl];
        [m enumerateAttributesInRange:r options:0 usingBlock:^(NSDictionary *attrs, NSRange range, BOOL *stop) {
            [rs addAttributes:attrs range:NSMakeRange(0, rs.length)];
        }];
        [m replaceCharactersInRange:r withAttributedString:rs];
    }
    return [m copy];
}

static NSAttributedString *attrReplaceWholeWord(NSAttributedString *orig, NSString *find, NSString *repl, BOOL cs) {
    if (orig == nil || find == nil || repl == nil) return orig;
    if (orig.length == 0 || find.length == 0) return orig;

    NSStringCompareOptions opts = cs ? 0 : NSCaseInsensitiveSearch;
    NSMutableAttributedString *m = [orig mutableCopy];
    NSUInteger srcLen = m.length;
    NSMutableArray *ranges = [NSMutableArray array];
    NSRange searchRange = NSMakeRange(0, srcLen);

    while (searchRange.location < srcLen) {
        NSRange r = [m.string rangeOfString:find options:opts range:searchRange];
        if (r.location == NSNotFound) break;

        BOOL leftOK = YES;
        if (r.location > 0) {
            if (isWordChar([m.string characterAtIndex:r.location - 1])) leftOK = NO;
        }
        BOOL rightOK = YES;
        NSUInteger rightIdx = r.location + r.length;
        if (rightIdx < srcLen) {
            if (isWordChar([m.string characterAtIndex:rightIdx])) rightOK = NO;
        }

        if (leftOK && rightOK) {
            [ranges addObject:[NSValue valueWithRange:r]];
        }

        searchRange.location = r.location + 1;
        if (searchRange.location >= srcLen) break;
        searchRange.length = srcLen - searchRange.location;
    }

    for (NSInteger i = (NSInteger)ranges.count - 1; i >= 0; i--) {
        NSRange r = [(NSValue *)ranges[i] rangeValue];
        NSMutableAttributedString *rs = [[NSMutableAttributedString alloc] initWithString:repl];
        [m enumerateAttributesInRange:r options:0 usingBlock:^(NSDictionary *attrs, NSRange range, BOOL *stop) {
            [rs addAttributes:attrs range:NSMakeRange(0, rs.length)];
        }];
        [m replaceCharactersInRange:r withAttributedString:rs];
    }
    return [m copy];
}

// 完全匹配判定：整个文本与短语相等（是否区分大小写）
static BOOL textMatchesExact(NSString *text, NSString *find, BOOL cs) {
    if (text == nil || find == nil) return NO;
    if (text.length != find.length) return NO;
    if (cs) return [text isEqualToString:find];
    return [text caseInsensitiveCompare:find] == NSOrderedSame;
}

#pragma mark - 规则应用

static NSString *applyCached(NSString *text, BOOL *outShouldCompress) {
    if (outShouldCompress) *outShouldCompress = NO;
    if (text == nil || text.length == 0) return text;
    if (text.length > kMaxTextLen) return text;

    if (NOW_SEC() < gBreakUntil) return text;

    NSDictionary *cached = [gReplaceCache objectForKey:text];
    if (cached) {
        if (outShouldCompress) *outShouldCompress = [cached[@"c"] boolValue];
        return cached[@"t"];
    }

    if (!mayContainAny(text)) {
        [gReplaceCache setObject:@{@"t": text, @"c": @NO} forKey:text];
        return text;
    }

    double t0 = NOW_SEC();
    NSString *out = text;
    BOOL shouldCompress = NO;
    NSMutableArray *hits = [NSMutableArray array];
    NSUInteger counter = 0;

    for (NSString *find in orderedFinds) {
        if ((++counter & 0x1F) == 0) {
            if (NOW_SEC() - t0 > kTimeLimit) {
                elog(@"TIMEOUT %.1fms | in=\"%@\" | hits: %@",
                     (NOW_SEC() - t0) * 1000.0, safeTruncate(text, 60),
                     [hits componentsJoinedByString:@", "]);
                gBreakUntil = NOW_SEC() + kBreakTime;
                if (outShouldCompress) *outShouldCompress = NO;
                return text;
            }
        }

        NSString *repl = [strings objectForKey:find];
        NSDictionary *rule = [keyedSettings objectForKey:find];
        BOOL cs = [[rule objectForKey:@"caseSensitive"] boolValue];
        BOOL wholeWord = [[rule objectForKey:@"wholeWord"] boolValue];
        BOOL exactMatch = [[rule objectForKey:@"exactMatch"] boolValue];

        // 完全匹配：基于原始 text 判断，不是当前的 out
        if (exactMatch) {
            if (!textMatchesExact(text, find, cs)) continue;
            // 完全匹配时，直接整体替换
            NSString *before = out;
            out = repl;
            if (![before isEqualToString:out]) {
                if ([[rule objectForKey:@"compress"] boolValue]) shouldCompress = YES;
                [hits addObject:[NSString stringWithFormat:@"%@>%@(E)", find, repl]];
            }
            continue;
        }

        // 非完全匹配才需要先看子串是否存在
        if ([out rangeOfString:find].location == NSNotFound) continue;

        NSString *before = out;
        if (wholeWord) {
            out = doReplaceWholeWord(out, find, repl, cs);
        } else {
            out = doReplace(out, find, repl, cs);
        }

        if (![before isEqualToString:out]) {
            if ([[rule objectForKey:@"compress"] boolValue]) shouldCompress = YES;
            [hits addObject:[NSString stringWithFormat:@"%@>%@%@", find, repl, wholeWord ? @"(W)" : @""]];
        }
    }

    double totalMs = (NOW_SEC() - t0) * 1000.0;
    if (hits.count > 0 || totalMs > kSlowMs) {
        elog(@"%.2fms | in=\"%@\" | out=\"%@\" | hits(%lu): %@",
             totalMs, safeTruncate(text, 60), safeTruncate(out, 60),
             (unsigned long)hits.count,
             hits.count > 0 ? [hits componentsJoinedByString:@", "] : @"(none)");
    }

    [gReplaceCache setObject:@{@"t": out, @"c": @(shouldCompress)} forKey:text];
    if (outShouldCompress) *outShouldCompress = shouldCompress;
    return out;
}

static NSAttributedString *applyRulesForAttr(NSAttributedString *attr, BOOL *outShouldCompress) {
    if (outShouldCompress) *outShouldCompress = NO;
    if (attr == nil) return nil;
    if (attr.length == 0) return attr;
    if (attr.length > kMaxAttrLen) return attr;

    NSAttributedString *out = attr;
    BOOL shouldCompress = NO;
    NSMutableArray *hits = [NSMutableArray array];
    NSString *origString = attr.string;

    for (NSString *find in orderedFinds) {
        NSString *repl = [strings objectForKey:find];
        NSDictionary *rule = [keyedSettings objectForKey:find];
        BOOL cs = [[rule objectForKey:@"caseSensitive"] boolValue];
        BOOL wholeWord = [[rule objectForKey:@"wholeWord"] boolValue];
        BOOL exactMatch = [[rule objectForKey:@"exactMatch"] boolValue];

        if (exactMatch) {
            if (!textMatchesExact(origString, find, cs)) continue;
            NSAttributedString *before = out;
            NSMutableAttributedString *rs = [[NSMutableAttributedString alloc] initWithString:repl];
            // 保留原属性
            if (before.length > 0) {
                [before enumerateAttributesInRange:NSMakeRange(0, before.length) options:0 usingBlock:^(NSDictionary *attrs, NSRange range, BOOL *stop) {
                    [rs addAttributes:attrs range:NSMakeRange(0, rs.length)];
                }];
            }
            out = rs;
            if (![before.string isEqualToString:out.string]) {
                if ([[rule objectForKey:@"compress"] boolValue]) shouldCompress = YES;
                [hits addObject:[NSString stringWithFormat:@"%@>%@(E)", find, repl]];
            }
            continue;
        }

        if ([out.string rangeOfString:find].location == NSNotFound) continue;

        NSAttributedString *before = out;
        if (wholeWord) {
            out = attrReplaceWholeWord(out, find, repl, cs);
        } else {
            out = attrReplace(out, find, repl);
        }

        if (![before.string isEqualToString:out.string]) {
            if ([[rule objectForKey:@"compress"] boolValue]) shouldCompress = YES;
            [hits addObject:[NSString stringWithFormat:@"%@>%@%@", find, repl, wholeWord ? @"(W)" : @""]];
        }
    }

    if (hits.count > 0) {
        elog(@"ATTR | in=\"%@\" | out=\"%@\" | hits(%lu): %@",
             safeTruncate(attr.string, 60), safeTruncate(out.string, 60),
             (unsigned long)hits.count,
             [hits componentsJoinedByString:@", "]);
    }

    if (outShouldCompress) *outShouldCompress = shouldCompress;
    return out;
}

#pragma mark - 自适应

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
    if (availableWidth <= 0) return nil;
    if (outWidthKnown) *outWidthKnown = YES;

    UIFont *font = label.font;
    if (font == nil) font = [UIFont systemFontOfSize:17];

    NSAttributedString *natural = [[NSAttributedString alloc] initWithString:text
                                                                   attributes:@{NSFontAttributeName: font}];
    CGFloat naturalWidth = [natural size].width;

    if (naturalWidth <= availableWidth) return nil;

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
        if (ratio < kMinExpandRatio) ratio = kMinExpandRatio;
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

#pragma mark - Hooks

%hook UILabel

- (void)setText:(NSString *)text {
    if (enabled && orderedFinds.count > 0 && self.tag != 317 && text.length > 0) {
        NSString *orig = text;
        BOOL shouldCompress = NO;
        NSString *newText = applyCached(text, &shouldCompress);

        if (newText && ![orig isEqualToString:newText]) {
            if (shouldCompress) {
                BOOL widthKnown = NO;
                NSAttributedString *fitted = fittedAttributedStringForLabel(newText, self, &widthKnown);
                if (fitted) {
                    objc_setAssociatedObject(self, kPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    [self setAttributedText:fitted];
                    return;
                } else if (!widthKnown) {
                    objc_setAssociatedObject(self, kPendingKey, orig, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                } else {
                    objc_setAssociatedObject(self, kPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            } else {
                objc_setAssociatedObject(self, kPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        } else {
            objc_setAssociatedObject(self, kPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        text = newText;
    }
    %orig;
}

- (void)layoutSubviews {
    %orig;

    if (!enabled || orderedFinds.count == 0 || self.tag == 317) return;

    NSString *pending = objc_getAssociatedObject(self, kPendingKey);
    if (pending == nil) return;

    BOOL shouldCompress = NO;
    NSString *newText = applyCached(pending, &shouldCompress);

    if (!shouldCompress || newText == nil || [pending isEqualToString:newText]) {
        objc_setAssociatedObject(self, kPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    BOOL widthKnown = NO;
    NSAttributedString *fitted = fittedAttributedStringForLabel(newText, self, &widthKnown);

    if (fitted) {
        objc_setAssociatedObject(self, kPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self setAttributedText:fitted];
    } else if (!widthKnown) {
        // 保留 pending
    } else {
        objc_setAssociatedObject(self, kPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)setAttributedText:(NSAttributedString *)attributedText {
    if (enabled && orderedFinds.count > 0 && self.tag != 317 && attributedText.length > 0 && !isAlreadyAdjusted(attributedText)) {
        BOOL shouldCompress = NO;
        NSAttributedString *newText = applyRulesForAttr(attributedText, &shouldCompress);

        if (newText && ![attributedText.string isEqualToString:newText.string]) {
            if (shouldCompress) {
                BOOL widthKnown = NO;
                NSAttributedString *fitted = fittedAttributedStringForLabel(newText.string, self, &widthKnown);
                if (fitted) {
                    objc_setAssociatedObject(self, kPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    attributedText = fitted;
                    %orig;
                    return;
                } else if (!widthKnown) {
                    objc_setAssociatedObject(self, kPendingKey, attributedText.string, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                } else {
                    objc_setAssociatedObject(self, kPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            } else {
                objc_setAssociatedObject(self, kPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            attributedText = newText;
        }
    }
    %orig;
}

%end

%hook UITextView
- (void)setText:(NSString *)text {
    if (enabled && orderedFinds.count > 0 && text.length > 0) {
        BOOL unused = NO;
        text = applyCached(text, &unused);
    }
    %orig;
}
- (void)setAttributedText:(NSAttributedString *)attributedText {
    if (enabled && orderedFinds.count > 0 && attributedText.length > 0 && attributedText.length <= kMaxAttrLen) {
        BOOL unused = NO;
        attributedText = applyRulesForAttr(attributedText, &unused);
    }
    %orig;
}
%end

%hook SBApplication
- (void)setDisplayName:(id)text {
    if (enabled && orderedFinds.count > 0 && text) {
        for (NSString *find in orderedFinds) {
            NSDictionary *rule = [keyedSettings objectForKey:find];
            BOOL cs = [[rule objectForKey:@"caseSensitive"] boolValue];
            BOOL ww = [[rule objectForKey:@"wholeWord"] boolValue];
            BOOL em = [[rule objectForKey:@"exactMatch"] boolValue];
            if (em) {
                if (textMatchesExact(text, find, cs)) text = [strings objectForKey:find];
            } else if (ww) {
                text = doReplaceWholeWord(text, find, [strings objectForKey:find], cs);
            } else {
                text = doReplace(text, find, [strings objectForKey:find], cs);
            }
        }
    }
    %orig;
}
%end

%hook SBFolder
- (void)setDisplayName:(id)text {
    if (enabled && orderedFinds.count > 0 && text) {
        for (NSString *find in orderedFinds) {
            NSDictionary *rule = [keyedSettings objectForKey:find];
            BOOL cs = [[rule objectForKey:@"caseSensitive"] boolValue];
            BOOL ww = [[rule objectForKey:@"wholeWord"] boolValue];
            BOOL em = [[rule objectForKey:@"exactMatch"] boolValue];
            if (em) {
                if (textMatchesExact(text, find, cs)) text = [strings objectForKey:find];
            } else if (ww) {
                text = doReplaceWholeWord(text, find, [strings objectForKey:find], cs);
            } else {
                text = doReplace(text, find, [strings objectForKey:find], cs);
            }
        }
    }
    %orig;
}
%end

#pragma mark - displayName getter

static id (*orig_app_dn)(id, SEL) = NULL;
static id ersatz_app_dn(id self, SEL _cmd) {
    id text = orig_app_dn(self, _cmd);
    if (enabled && orderedFinds.count > 0 && text) {
        for (NSString *find in orderedFinds) {
            NSDictionary *rule = [keyedSettings objectForKey:find];
            BOOL cs = [[rule objectForKey:@"caseSensitive"] boolValue];
            BOOL ww = [[rule objectForKey:@"wholeWord"] boolValue];
            BOOL em = [[rule objectForKey:@"exactMatch"] boolValue];
            if (em) {
                if (textMatchesExact(text, find, cs)) text = [strings objectForKey:find];
            } else if (ww) {
                text = doReplaceWholeWord(text, find, [strings objectForKey:find], cs);
            } else {
                text = doReplace(text, find, [strings objectForKey:find], cs);
            }
        }
    }
    return text;
}

static id (*orig_folder_dn)(id, SEL) = NULL;
static id ersatz_folder_dn(id self, SEL _cmd) {
    id text = orig_folder_dn(self, _cmd);
    if (enabled && orderedFinds.count > 0 && text) {
        for (NSString *find in orderedFinds) {
            NSDictionary *rule = [keyedSettings objectForKey:find];
            BOOL cs = [[rule objectForKey:@"caseSensitive"] boolValue];
            BOOL ww = [[rule objectForKey:@"wholeWord"] boolValue];
            BOOL em = [[rule objectForKey:@"exactMatch"] boolValue];
            if (em) {
                if (textMatchesExact(text, find, cs)) text = [strings objectForKey:find];
            } else if (ww) {
                text = doReplaceWholeWord(text, find, [strings objectForKey:find], cs);
            } else {
                text = doReplace(text, find, [strings objectForKey:find], cs);
            }
        }
    }
    return text;
}

static void hookGetter(const char *cls, const char *sel, void **orig, void *imp) {
    Class c = objc_getClass(cls);
    if (!c) return;
    Method m = class_getInstanceMethod(c, sel_registerName(sel));
    if (!m) return;
    *orig = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)imp);
}

#pragma mark - Init

%ctor {
    logInit();

    gReplaceCache = [[NSCache alloc] init];
    gReplaceCache.countLimit = 3000;

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        (CFNotificationCallback)PrefsChanged,
        (CFStringRef)[NSString stringWithFormat:@"%@.prefschanged", bundleIdentifier],
        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    refreshPrefs();

    hookGetter("SBApplication", "displayName", (void **)&orig_app_dn, (void *)ersatz_app_dn);
    hookGetter("SBFolder", "displayName", (void **)&orig_folder_dn, (void *)ersatz_folder_dn);
}