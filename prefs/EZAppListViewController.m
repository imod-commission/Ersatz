// EZAppListViewController.m
#import "EZAppListViewController.h"
#import "EZAddPhraseViewController.h"
#include <roothide.h>
#include <objc/runtime.h>

// 从插件自身的 bundle 加载本地化
#define EZ_L(key) NSLocalizedStringFromTableInBundle(key, @"Localizable", [NSBundle bundleForClass:[self class]], nil)

#pragma mark - 私有 API 声明

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allApplications;
- (NSArray *)allInstalledApplications;
@end

@interface LSApplicationProxy : NSObject
- (NSString *)applicationIdentifier;
- (NSString *)localizedName;
@end

#pragma mark -

@implementation EZAppListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = EZ_L(@"APP_SCOPE_TITLE");

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

    // 搜索框
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = EZ_L(@"SEARCH_APPS_PLACEHOLDER");
    if (@available(iOS 11.0, *)) {
        self.navigationItem.searchController = self.searchController;
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
    } else {
        self.tableView.tableHeaderView = self.searchController.searchBar;
    }
    self.definesPresentationContext = YES;

    // 从 parent 取当前值
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

#pragma mark - 加载应用列表

// 从 .app 目录读取 Info.plist 得到 bundleID + 名称
- (NSDictionary *)appInfoAtBundlePath:(NSString *)path {
    NSString *infoPath = [path stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    if (![info isKindOfClass:[NSDictionary class]]) return nil;

    NSString *bid = info[@"CFBundleIdentifier"];
    if (![bid isKindOfClass:[NSString class]] || bid.length == 0) return nil;

    // 名称优先级：DisplayName > Name > bundleID
    NSString *name = nil;

    id displayName = info[@"CFBundleDisplayName"];
    if ([displayName isKindOfClass:[NSString class]] && [(NSString *)displayName length] > 0) {
        name = (NSString *)displayName;
    }

    if (name == nil) {
        id bundleName = info[@"CFBundleName"];
        if ([bundleName isKindOfClass:[NSString class]] && [(NSString *)bundleName length] > 0) {
            name = (NSString *)bundleName;
        }
    }

    if (name == nil) name = bid;

    return @{@"bundleID": bid, @"name": name};
}

// 扫描一个目录下所有 .app bundle
- (void)scanAppDirectory:(NSString *)dir intoDict:(NSMutableDictionary *)dict {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *contents = [fm contentsOfDirectoryAtPath:dir error:nil];
    if (contents == nil) return;

    for (NSString *entry in contents) {
        if (![entry.pathExtension isEqualToString:@"app"]) continue;

        NSString *fullPath = [dir stringByAppendingPathComponent:entry];
        NSDictionary *info = [self appInfoAtBundlePath:fullPath];
        if (info == nil) continue;

        NSString *bid = info[@"bundleID"];
        if (dict[bid] == nil) {
            dict[bid] = info;
        }
    }
}

- (void)loadApps {
    NSMutableDictionary *byID = [NSMutableDictionary dictionary];

    // === 1. LSApplicationWorkspace ===
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
                if (byID[bundleID] == nil) {
                    byID[bundleID] = @{@"bundleID": bundleID, @"name": name};
                }
            }
        }
    }

    // === 2. 文件系统补充系统 App / SpringBoard / Daemon ===
    NSArray *systemDirs = @[
        jbroot(@"/Applications"),
        jbroot(@"/System/Library/CoreServices"),
        jbroot(@"/System/Library/PrivateFrameworks"),
        jbroot(@"/System/Applications"),
        jbroot(@"/var/stash/Applications"),
        @"/Applications",
        @"/System/Library/CoreServices",
        @"/System/Applications",
    ];
    for (NSString *dir in systemDirs) {
        [self scanAppDirectory:dir intoDict:byID];
    }

    // === 3. 兜底：SpringBoard ===
    if (byID[@"com.apple.springboard"] == nil) {
        byID[@"com.apple.springboard"] = @{@"bundleID": @"com.apple.springboard", @"name": @"SpringBoard"};
    }

    // === 4. 排序 ===
    NSMutableArray *result = [[byID allValues] mutableCopy];
    [result sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];

    self.apps = result;
    self.filteredApps = result;
    [self.tableView reloadData];
}

#pragma mark - 保存到 parent

- (void)saveToParent {
    if (self.parentPhrase) {
        self.parentPhrase.filterMode = self.filterMode;
        self.parentPhrase.apps = [self.selectedApps copy];
    }
}

#pragma mark - UISearchResultsUpdating

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

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3;
    return self.filteredApps.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return EZ_L(@"MODE_SECTION_TITLE");
    return [NSString stringWithFormat:EZ_L(@"APPS_LIST_SECTION_FMT"),
            (unsigned long)self.selectedApps.count];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        if ([self.filterMode isEqualToString:@"all"]) {
            return EZ_L(@"MODE_FOOTER_ALL");
        } else if ([self.filterMode isEqualToString:@"whitelist"]) {
            return EZ_L(@"MODE_FOOTER_WHITELIST");
        } else {
            return EZ_L(@"MODE_FOOTER_BLACKLIST");
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
            EZ_L(@"MODE_ALL"),
            EZ_L(@"MODE_WHITELIST"),
            EZ_L(@"MODE_BLACKLIST"),
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

    if ([self.filterMode isEqualToString:@"all"]) return;

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