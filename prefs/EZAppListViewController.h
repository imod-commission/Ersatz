// EZAppListViewController.h
#import <Preferences/PSViewController.h>
#import <UIKit/UIKit.h>

@class EZAddPhraseViewController;

@interface EZAppListViewController : PSViewController <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating>

@property (nonatomic, weak) EZAddPhraseViewController *parentPhrase;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;

@property (nonatomic, strong) NSArray *apps;
@property (nonatomic, strong) NSArray *filteredApps;

@property (nonatomic, strong) NSMutableArray *selectedApps;
@property (nonatomic, strong) NSString *filterMode;

@end