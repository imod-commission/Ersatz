// EZAppListViewController.m
#import "EZAppListViewController.h"
#import "EZAddPhraseViewController.h"
#import "EZLocalization.h"
#import <objc/runtime.h>

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allApplications;
- (NSArray *)allInstalledApplications;
@end

@interface LSApplicationProxy : NSObject
- (NSString *)applicationIdentifier;
- (NSString *)localizedName;
@end

@implementation EZAppListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = EZLoc(@"APP_SCOPE_TITLE");

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = EZLoc(@"SEARCH_APPS_PLACEHOLDER");
    if (@available(iOS 11.0, *)) {
        self.navigationItem.searchController = self.searchController;
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
    } else {
        self.tableView.tableHeaderView = self.searchController.searchBar;
    }
    self.definesPresentationContext = YES;

    if (self.parentPhrase) {
        NSMutableArray *sel = [self.parentPhrase.apps mutableCopy];
        if (!sel) sel = [NSMutableArray array];
        self.selectedApps = sel;

        NSString *mode = self.parentPhrase.filterMode;
        if (!mode) mode = @"all";
        self.filterMode = mode;
    } else {
        self.selectedApps = [NSMutableArray array];
        self.filterMode = @"all";
    }

    [self loadApps];
}

- (void)loadApps {
    NSMutableArray *result = [NSMutableArray array];

    Class workspaceClass = objc_getClass("LSApplicationWorkspace");
    if (workspaceClass) {
        id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
        NSArray *allApps = nil;
        if ([workspace respondsToSelector:@selector(allInstalledApplications)]) {
            allApps = [workspace performSelector:@selector(allInstalledApplications)];
        }
        if (allApps == nil && [workspace respondsToSelector:@selector(allApplications)]) {
            allApps = [workspace performSelector:@selector(allApplications)];
        }

        for (id proxy in allApps) {
            NSString *bundleID = nil;
            NSString *name = nil;
            if ([proxy respondsToSelector:@selector(applicationIdentifier)]) {
                bundleID = [proxy performSelector:@selector(applicationIdentifier)];
            }
            if ([proxy respondsToSelector:@selector(localizedName)]) {
                name = [proxy performSelector:@selector(localizedName)];
            }
            if (bundleID && bundleID.length > 0) {
                if (name == nil || name.length == 0) name = bundleID;
                [result addObject:@{@"bundleID": bundleID, @"name": name}];
            }
        }
    }

    [result sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];

    self.apps = result;
    self.filteredApps = result;
    [self.tableView reloadData];
}

- (void)saveToParent {
    if (self.parentPhrase) {
        self.parentPhrase.filterMode = self.filterMode;
        self.parentPhrase.apps = [self.selectedApps copy];
    }
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *text = searchController.searchBar.text;
    if (text == nil) text = @"";

    if (text.length == 0) {
        self.filteredApps = self.apps;
    } else {
        NSString *lower = [text lowercaseString];
        NSMutableArray *filtered = [NSMutableArray array];
        for (NSDictionary *app in self.apps) {
            NSString *name = app[@"name"];
            NSString *bid = app[@"bundleID"];
            if ([[name lowercaseString] containsString:lower] ||
                [[bid lowercaseString] containsString:lower]) {
                [filtered addObject:app];
            }
        }
        self.filteredApps = filtered;
    }
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3;
    return self.filteredApps.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return EZLoc(@"MODE_SECTION_TITLE");
    return EZLocFormat(@"APPS_LIST_SECTION_FMT", (unsigned long)self.selectedApps.count);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        if ([self.filterMode isEqualToString:@"all"]) {
            return EZLoc(@"MODE_FOOTER_ALL");
        } else if ([self.filterMode isEqualToString:@"whitelist"]) {
            return EZLoc(@"MODE_FOOTER_WHITELIST");
        } else {
            return EZLoc(@"MODE_FOOTER_BLACKLIST");
        }
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        static NSString *modeCellID = @"ModeCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:modeCellID];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:modeCellID];
        }
        NSArray *modes = @[@"all", @"whitelist", @"blacklist"];
        NSArray *labels = @[
            EZLoc(@"MODE_ALL"),
            EZLoc(@"MODE_WHITELIST"),
            EZLoc(@"MODE_BLACKLIST")
        ];
        cell.textLabel.tag = 317;
        cell.textLabel.text = labels[indexPath.row];
        if ([self.filterMode isEqualToString:modes[indexPath.row]]) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
        } else {
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
        return cell;
    }

    static NSString *appCellID = @"AppCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:appCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:appCellID];
    }
    NSDictionary *app = self.filteredApps[indexPath.row];
    cell.textLabel.tag = 317;
    cell.textLabel.text = app[@"name"];
    cell.detailTextLabel.tag = 317;
    cell.detailTextLabel.text = app[@"bundleID"];

    BOOL selected = [self.selectedApps containsObject:app[@"bundleID"]];
    if ([self.filterMode isEqualToString:@"all"]) {
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else {
        cell.textLabel.textColor = [UIColor labelColor];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        NSArray *modes = @[@"all", @"whitelist", @"blacklist"];
        self.filterMode = modes[indexPath.row];
        [self saveToParent];
        [tableView reloadData];
        return;
    }

    if ([self.filterMode isEqualToString:@"all"]) {
        return;
    }

    NSDictionary *app = self.filteredApps[indexPath.row];
    NSString *bid = app[@"bundleID"];
    if ([self.selectedApps containsObject:bid]) {
        [self.selectedApps removeObject:bid];
    } else {
        [self.selectedApps addObject:bid];
    }
    [self saveToParent];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self saveToParent];
}

@end