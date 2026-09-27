// EZAddPhraseViewController.m
#import "EZAddPhraseViewController.h"
#import "EZAppListViewController.h"
#import "EZLocalization.h"
#import <Preferences/PSEditableTableCell.h>
#import <Preferences/PSSwitchTableCell.h>

@interface PSEditableTableCell (Missing)
- (UITextField *)textField;
@end

@implementation EZAddPhraseViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        self.caseSensitive = YES;
        self.compress = NO;
        self.filterMode = @"all";
        self.apps = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = EZLoc(@"ADD_PHRASE_TITLE");

    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(addPhrase)];
    self.navigationItem.rightBarButtonItem = doneButton;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

    [self updateDoneButtonState];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateDoneButtonState];
    [self.tableView reloadData];
}

- (void)updateDoneButtonState {
    BOOL hasTarget = self.target.length > 0;
    BOOL hasReplacement = self.replacement.length > 0;
    BOOL different = ![self.target isEqualToString:self.replacement];
    self.navigationItem.rightBarButtonItem.enabled = (hasTarget && hasReplacement && different);
}

- (void)addPhrase {
    if (!self.filterMode) self.filterMode = @"all";
    if (!self.apps) self.apps = @[];
    [self.parent addPhrase:self.target
               replacement:self.replacement
             caseSensitive:self.caseSensitive
                  compress:self.compress
                filterMode:self.filterMode
                      apps:self.apps];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)setTarget:(NSString *)target {
    _target = target;
    [self updateDoneButtonState];
}

- (void)setReplacement:(NSString *)replacement {
    _replacement = replacement;
    [self updateDoneButtonState];
}

- (void)setTargetValue:(id)value forSpecifier:(PSSpecifier *)specifier {
    self.target = value;
}

- (id)readTargetValue:(PSSpecifier *)specifier {
    return self.target;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2;
        case 1: return 1;
        case 2: return 1;
        case 3: return 1;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 2) return EZLoc(@"COMPRESS_SECTION_TITLE");
    if (section == 3) return EZLoc(@"SCOPE_SECTION_TITLE");
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 2) {
        return EZLoc(@"COMPRESS_FOOTER");
    }
    return nil;
}

- (void)targetTextDidChange:(UITextField *)textField {
    self.target = textField.text;
}

- (void)replacementTextDidChange:(UITextField *)textField {
    self.replacement = textField.text;
}

- (void)caseSwitchDidChange:(UISwitch *)caseSwitch {
    self.caseSensitive = caseSwitch.on;
}

- (void)compressSwitchDidChange:(UISwitch *)compressSwitch {
    self.compress = compressSwitch.on;
}

- (NSString *)appsDescription {
    NSString *mode = self.filterMode;
    if (!mode) mode = @"all";
    NSUInteger count = self.apps ? self.apps.count : 0;

    if ([mode isEqualToString:@"all"]) {
        return EZLoc(@"APPS_DESC_ALL");
    } else if ([mode isEqualToString:@"whitelist"]) {
        if (count == 0) return EZLoc(@"APPS_DESC_WHITELIST_NONE");
        return EZLocFormat(@"APPS_DESC_WHITELIST_FMT", (unsigned long)count);
    } else {
        if (count == 0) return EZLoc(@"APPS_DESC_BLACKLIST_NONE");
        return EZLocFormat(@"APPS_DESC_BLACKLIST_FMT", (unsigned long)count);
    }
}

- (void)openAppPicker {
    EZAppListViewController *vc = [[EZAppListViewController alloc] init];
    vc.parentPhrase = self;
    vc.filterMode = self.filterMode ? self.filterMode : @"all";
    vc.selectedApps = [self.apps mutableCopy] ?: [NSMutableArray array];
    [[self navigationController] pushViewController:vc animated:YES];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && indexPath.row == 0) {
        PSEditableTableCell *cell = [[PSEditableTableCell alloc] initWithStyle:1000 reuseIdentifier:@"EditTextCell"];
        cell.textLabel.tag = 317;
        cell.textLabel.text = EZLoc(@"PHRASE_LABEL");
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textField.text = self.target;
        [cell.textField addTarget:self action:@selector(targetTextDidChange:) forControlEvents:UIControlEventEditingChanged];
        return cell;
    } else if (indexPath.section == 0 && indexPath.row == 1) {
        PSEditableTableCell *cell = [[PSEditableTableCell alloc] initWithStyle:1000 reuseIdentifier:@"EditTextCell"];
        cell.textLabel.tag = 317;
        cell.textLabel.text = EZLoc(@"REPLACEMENT_LABEL");
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textField.text = self.replacement;
        [cell.textField addTarget:self action:@selector(replacementTextDidChange:) forControlEvents:UIControlEventEditingChanged];
        [cell.textField setReturnKeyType:UIReturnKeyDone];
        return cell;
    } else if (indexPath.section == 1 && indexPath.row == 0) {
        PSSwitchTableCell *cell = [[PSSwitchTableCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"CaseSwitchCell" specifier:nil];
        cell.textLabel.tag = 317;
        cell.textLabel.text = EZLoc(@"CASE_SENSITIVE_LABEL");
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [cell setValue:[NSNumber numberWithBool:self.caseSensitive]];
        [cell.control addTarget:self action:@selector(caseSwitchDidChange:) forControlEvents:UIControlEventValueChanged];
        return cell;
    } else if (indexPath.section == 2 && indexPath.row == 0) {
        PSSwitchTableCell *cell = [[PSSwitchTableCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"CompressSwitchCell" specifier:nil];
        cell.textLabel.tag = 317;
        cell.textLabel.text = EZLoc(@"COMPRESS_LABEL");
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [cell setValue:[NSNumber numberWithBool:self.compress]];
        [cell.control addTarget:self action:@selector(compressSwitchDidChange:) forControlEvents:UIControlEventValueChanged];
        return cell;
    } else if (indexPath.section == 3 && indexPath.row == 0) {
        static NSString *appsCellID = @"AppsCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:appsCellID];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:appsCellID];
        }
        cell.textLabel.tag = 317;
        cell.textLabel.text = EZLoc(@"APPS_LABEL");
        cell.detailTextLabel.tag = 317;
        cell.detailTextLabel.text = [self appsDescription];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    return [[UITableViewCell alloc] init];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 3 && indexPath.row == 0) {
        [self openAppPicker];
    }
}

@end