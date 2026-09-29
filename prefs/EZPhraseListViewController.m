// EZPhraseListViewController.m
#import <Preferences/PSViewController.h>
#import "EZPhraseListViewController.h"
#import "EZAddPhraseViewController.h"
#import "EZEditPhraseViewController.h"
#include <roothide.h>

#define EZ_L(key) NSLocalizedStringFromTableInBundle(key, @"Localizable", [NSBundle bundleForClass:[self class]], nil)
#define settingsPath jbroot(@"/var/mobile/Library/Preferences/xyz.skitty.ersatz.plist")

@implementation EZPhraseListViewController

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Ersatz";

    UIBarButtonItem *plusButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addPhrase)];
    self.navigationItem.rightBarButtonItem = plusButton;

    self.tableView = [[UITableView alloc] init];
    self.tableView.frame = self.view.bounds;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

    // 搜索框
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = EZ_L(@"SEARCH_PHRASES_PLACEHOLDER");
    if (@available(iOS 11.0, *)) {
        self.navigationItem.searchController = self.searchController;
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
    } else {
        self.tableView.tableHeaderView = self.searchController.searchBar;
    }
    self.definesPresentationContext = YES;

    // 加载偏好
    CFArrayRef keyList = CFPreferencesCopyKeyList(CFSTR("xyz.skitty.ersatz"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (keyList) {
        _settings = (NSMutableDictionary *)CFBridgingRelease(CFPreferencesCopyMultiple(keyList, CFSTR("xyz.skitty.ersatz"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
        CFRelease(keyList);
    } else {
        _settings = [[NSMutableDictionary alloc] initWithContentsOfFile:settingsPath];
    }
    if (!_settings) _settings = [[NSMutableDictionary alloc] init];

    NSMutableArray *mutableStrings = [_settings[@"strings"] mutableCopy];
    if (mutableStrings) {
        _settings[@"strings"] = mutableStrings;
    } else {
        _settings[@"strings"] = [[NSMutableArray alloc] init];
    }

    [self sortSettings];
}

#pragma mark - 保存

- (void)updateSettings {
    CFPreferencesSetAppValue((CFStringRef)@"strings", (CFPropertyListRef)_settings[@"strings"], CFSTR("xyz.skitty.ersatz"));

    if (@available(iOS 11.0, *)) {
        [_settings writeToURL:[NSURL fileURLWithPath:settingsPath] error:nil];
    } else {
        [_settings writeToFile:settingsPath atomically:YES];
    }

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("xyz.skitty.ersatz.prefschanged"), nil, nil, true);
}

#pragma mark - 构建显示数据

- (void)sortSettings {
    _strings = [[NSMutableDictionary alloc] init];
    for (NSDictionary *obj in _settings[@"strings"]) {
        NSString *phrase = obj[@"phrase"];
        NSString *replacement = obj[@"replacement"];
        if (replacement == nil) replacement = @"";
        if (phrase) [_strings setValue:replacement forKey:phrase];
    }
    [self applyCurrentFilter];
}

- (void)applyCurrentFilter {
    NSString *searchText = self.searchController.searchBar.text;
    if (searchText == nil) searchText = @"";
    [self filterContentForSearchText:searchText];
}

- (void)buildSortedStringsFromArray:(NSArray *)array {
    _sortedStrings = [[NSMutableDictionary alloc] init];

    NSMutableArray *keys = [NSMutableArray array];
    for (NSDictionary *obj in array) {
        NSString *phrase = obj[@"phrase"];
        if (phrase) [keys addObject:phrase];
    }
    NSArray *sortedKeys = [keys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    for (NSString *temp in sortedKeys) {
        NSString *first = [temp substringToIndex:1].uppercaseString;
        if (![_sortedStrings objectForKey:first]) {
            [_sortedStrings setValue:[[NSMutableArray alloc] init] forKey:first];
        }
        [[_sortedStrings objectForKey:first] addObject:temp];
    }
}

- (void)filterContentForSearchText:(NSString *)searchText {
    if (searchText.length == 0) {
        [self buildSortedStringsFromArray:_settings[@"strings"]];
    } else {
        NSString *lower = [searchText lowercaseString];
        NSMutableArray *filtered = [NSMutableArray array];
        for (NSDictionary *obj in _settings[@"strings"]) {
            NSString *phrase = obj[@"phrase"];
            NSString *replacement = obj[@"replacement"];
            if (phrase == nil) phrase = @"";
            if (replacement == nil) replacement = @"";
            if ([[phrase lowercaseString] containsString:lower] ||
                [[replacement lowercaseString] containsString:lower]) {
                [filtered addObject:obj];
            }
        }
        [self buildSortedStringsFromArray:filtered];
    }
    [self.tableView reloadData];
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *text = searchController.searchBar.text;
    if (text == nil) text = @"";
    [self filterContentForSearchText:text];
}

#pragma mark - 增删改

- (void)addPhrase {
    EZAddPhraseViewController *addController = [[EZAddPhraseViewController alloc] init];
    addController.parent = self;
    [[self navigationController] pushViewController:addController animated:YES];
}

- (void)addPhrase:(NSString *)phrase
      replacement:(NSString *)replacement
    caseSensitive:(BOOL)caseSensitive
         compress:(BOOL)compress
        wholeWord:(BOOL)wholeWord
       filterMode:(NSString *)filterMode
             apps:(NSArray *)apps {

    if (!_settings[@"shownPrompt"]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:EZ_L(@"NOTICE_TITLE")
                                                                       message:EZ_L(@"RESPRING_NOTICE_MESSAGE")
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:EZ_L(@"OK")
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        _settings[@"shownPrompt"] = @YES;
    }

    if (!filterMode) filterMode = @"all";
    if (!apps) apps = @[];

    [_settings[@"strings"] addObject:@{
        @"phrase": phrase,
        @"replacement": replacement,
        @"caseSensitive": @(caseSensitive),
        @"compress": @(compress),
        @"wholeWord": @(wholeWord),
        @"filterMode": filterMode,
        @"apps": apps
    }];

    [self updateSettings];
    [self sortSettings];
}

- (void)editPhrase:(NSString *)phrase
         newPhrase:(NSString *)newPhrase
       replacement:(NSString *)replacement
     caseSensitive:(BOOL)caseSensitive
          compress:(BOOL)compress
         wholeWord:(BOOL)wholeWord
        filterMode:(NSString *)filterMode
              apps:(NSArray *)apps {

    NSDictionary *remove = nil;
    for (NSDictionary *obj in _settings[@"strings"]) {
        if ([obj[@"phrase"] isEqualToString:phrase]) {
            remove = obj;
            break;
        }
    }

    if (remove) {
        [_settings[@"strings"] removeObject:remove];
        NSMutableDictionary *newObj = [remove mutableCopy];
        newObj[@"phrase"] = newPhrase;
        newObj[@"replacement"] = replacement;
        newObj[@"caseSensitive"] = @(caseSensitive);
        newObj[@"compress"] = @(compress);
        newObj[@"wholeWord"] = @(wholeWord);
        newObj[@"filterMode"] = filterMode ? filterMode : @"all";
        newObj[@"apps"] = apps ? apps : @[];
        [_settings[@"strings"] addObject:newObj];
    }

    [self updateSettings];
    [self sortSettings];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [[_sortedStrings allKeys] count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSArray *sectionKeys = [[_sortedStrings allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSString *key = [sectionKeys objectAtIndex:section];
    return [[_sortedStrings objectForKey:key] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSArray *sectionKeys = [[_sortedStrings allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    return [sectionKeys objectAtIndex:section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellIdentifier];
    }

    NSArray *sectionKeys = [[_sortedStrings allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSString *sectionKey = [sectionKeys objectAtIndex:indexPath.section];
    NSString *phrase = [[_sortedStrings objectForKey:sectionKey] objectAtIndex:indexPath.row];

    cell.textLabel.tag = 317;
    cell.textLabel.text = phrase;
    cell.detailTextLabel.tag = 317;
    NSString *replacement = [_strings objectForKey:phrase];
    if (replacement == nil) replacement = @"";
    cell.detailTextLabel.text = replacement;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *sectionKeys = [[_sortedStrings allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSString *sectionKey = [sectionKeys objectAtIndex:indexPath.section];
    NSString *phrase = [[_sortedStrings objectForKey:sectionKey] objectAtIndex:indexPath.row];

    NSDictionary *dict = nil;
    for (NSDictionary *obj in _settings[@"strings"]) {
        if ([obj[@"phrase"] isEqualToString:phrase]) {
            dict = obj;
            break;
        }
    }

    if (!dict) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }

    EZEditPhraseViewController *editController = [[EZEditPhraseViewController alloc] initWithDictionary:dict];
    editController.parent = self;
    [[self navigationController] pushViewController:editController animated:YES];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - Swipe to delete

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *sectionKeys = [[_sortedStrings allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSString *sectionKey = [sectionKeys objectAtIndex:indexPath.section];
    NSString *phrase = [[_sortedStrings objectForKey:sectionKey] objectAtIndex:indexPath.row];

    NSDictionary *remove = nil;
    for (NSDictionary *obj in _settings[@"strings"]) {
        if ([obj[@"phrase"] isEqualToString:phrase]) {
            remove = obj;
            break;
        }
    }

    if (remove) [_settings[@"strings"] removeObject:remove];
    NSInteger rows = [self tableView:self.tableView numberOfRowsInSection:indexPath.section];

    [tableView beginUpdates];
    [self updateSettings];
    [self sortSettings];
    if (rows == 1) {
        [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:indexPath.section] withRowAnimation:UITableViewRowAnimationAutomatic];
    } else {
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
    [tableView endUpdates];
}

@end