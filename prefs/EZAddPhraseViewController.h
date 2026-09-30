// EZAddPhraseViewController.h
#import <Preferences/PSViewController.h>
#import "EZPhraseListViewController.h"

@interface EZAddPhraseViewController : PSViewController <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, retain) NSString *target;
@property (nonatomic, retain) NSString *replacement;
@property (nonatomic, assign) BOOL caseSensitive;
@property (nonatomic, assign) BOOL compress;
@property (nonatomic, assign) BOOL wholeWord;         // ← 新增
@property (nonatomic, retain) NSString *filterMode;
@property (nonatomic, retain) NSArray  *apps;
@property (nonatomic, retain) EZPhraseListViewController *parent;
@property (nonatomic, retain) UITableView *tableView;
@property (nonatomic, assign) BOOL exactMatch;   // ← 新增

@end