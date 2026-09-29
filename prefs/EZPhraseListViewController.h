// EZPhraseListViewController.h
#import <Preferences/PSViewController.h>

@interface EZPhraseListViewController : PSViewController <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating> {
    NSMutableDictionary *_settings;
    NSMutableDictionary *_strings;
    NSMutableDictionary *_sortedStrings;
}

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;

- (void)addPhrase:(NSString *)addPhrase
      replacement:(NSString *)replacement
    caseSensitive:(BOOL)caseSensitive
         compress:(BOOL)compress
        wholeWord:(BOOL)wholeWord
       filterMode:(NSString *)filterMode
             apps:(NSArray *)apps;

- (void)editPhrase:(NSString *)phrase
         newPhrase:(NSString *)newPhrase
       replacement:(NSString *)replacement
     caseSensitive:(BOOL)caseSensitive
          compress:(BOOL)compress
         wholeWord:(BOOL)wholeWord
        filterMode:(NSString *)filterMode
              apps:(NSArray *)apps;

@end