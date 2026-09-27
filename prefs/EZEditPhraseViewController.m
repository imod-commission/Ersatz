// EZEditPhraseViewController.m
#import "EZEditPhraseViewController.h"
#import "EZLocalization.h"

@implementation EZEditPhraseViewController

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        self.originalPhrase = dict[@"phrase"];
        self.target = dict[@"phrase"];
        self.replacement = dict[@"replacement"];
        self.caseSensitive = [dict[@"caseSensitive"] boolValue];
        self.compress = [dict[@"compress"] boolValue];

        NSString *mode = dict[@"filterMode"];
        self.filterMode = mode ? mode : @"all";

        NSArray *apps = dict[@"apps"];
        self.apps = apps ? apps : @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = EZLoc(@"EDIT_PHRASE_TITLE");
}

- (void)addPhrase {
    if (!self.filterMode) self.filterMode = @"all";
    if (!self.apps) self.apps = @[];
    [self.parent editPhrase:self.originalPhrase
                  newPhrase:self.target
                replacement:self.replacement
              caseSensitive:self.caseSensitive
                   compress:self.compress
                 filterMode:self.filterMode
                       apps:self.apps];
    [self.navigationController popViewControllerAnimated:YES];
}

@end