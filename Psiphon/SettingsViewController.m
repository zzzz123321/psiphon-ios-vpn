/*
 * Copyright (c) 2017, Psiphon Inc.
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#import "SettingsViewController.h"
#import "AppDelegate.h"
#import "IAPStoreHelper.h"
#import "IAPViewController.h"
#import "PsiCashOnboardingViewController.h"
#import "RACSignal.h"
#import "RACCompoundDisposable.h"
#import "RACReplaySubject.h"
#import "RACSignal+Operations.h"
#import "VPNManager.h"

// Specifier keys for cells in settings menu
// These keys are defined in Psiphon/InAppSettings.bundle/Root.inApp.plist
NSString * const SettingsSubscriptionCellSpecifierKey = @"settingsSubscription";
NSString * const SettingsPsiCashCellSpecifierKey = @"settingsPsiCash";
NSString * const SettingsReinstallVPNConfigurationKey = @"settingsReinstallVPNConfiguration";

@interface SettingsViewController ()

@property (assign) BOOL hasActiveSubscription;
@property (assign) VPNStatus vpnStatus;

@property (nonatomic) RACCompoundDisposable *compoundDisposable;

@end

@implementation SettingsViewController {

    // Subscription row
    UITableViewCell *subscriptionTableViewCell;

    UITableViewCell *reinstallVPNProfileCell;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _compoundDisposable = [RACCompoundDisposable compoundDisposable];
    }
    return self;
}

- (void)dealloc {
    [self.compoundDisposable dispose];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    __weak SettingsViewController *weakSelf = self;

    __block RACDisposable *subscriptionStatusDisposable = [[AppDelegate sharedAppDelegate].subscriptionStatus
      subscribeNext:^(NSNumber *value) {
          UserSubscriptionStatus s = (UserSubscriptionStatus) [value integerValue];

          weakSelf.hasActiveSubscription = (s == UserSubscriptionActive);
          [self updateSubscriptionCell];
          [weakSelf updateHiddenKeys];

      } error:^(NSError *error) {
          [weakSelf.compoundDisposable removeDisposable:subscriptionStatusDisposable];
      } completed:^{
          [weakSelf.compoundDisposable removeDisposable:subscriptionStatusDisposable];
      }];

    [self.compoundDisposable addDisposable:subscriptionStatusDisposable];

    __block RACDisposable *tunnelStatusDisposable =
      [[VPNManager sharedInstance].lastTunnelStatus
        subscribeNext:^(NSNumber *statusObject) {
            weakSelf.vpnStatus = (VPNStatus) [statusObject integerValue];
            [weakSelf updateReinstallVPNProfileCell];
            [weakSelf updateHiddenKeys];
        }];

    [self.compoundDisposable addDisposable:tunnelStatusDisposable];
}

- (void)updateHiddenKeys {
    NSMutableSet *hiddenKeys = [NSMutableSet setWithSet:self.hiddenKeys];
     if(![IAPStoreHelper canMakePayments]) {
         [hiddenKeys addObject:SettingsSubscriptionCellSpecifierKey];
     }

    if (self.hasActiveSubscription) {
        [hiddenKeys addObject:SettingsPsiCashCellSpecifierKey];
    }

    // If the VPN is not active, don't show the force reconnect button.
    if (![VPNManager mapIsVPNActive:self.vpnStatus]) {
        [hiddenKeys addObject:kForceReconnect];
        [hiddenKeys addObject:kForceReconnectFooter];
    } else {
        [hiddenKeys removeObject:kForceReconnect];
        [hiddenKeys removeObject:kForceReconnectFooter];
    }

    self.hiddenKeys = hiddenKeys;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    // Navigation bar may have been customized, revert
    self.navigationController.navigationBar.barTintColor = nil;
    self.navigationController.navigationBar.tintColor = nil;
    [self.navigationController.navigationBar setTitleTextAttributes:nil];
}

#pragma mark - UI update methods

- (void)updateSubscriptionCell {
    NSString *subscriptionCellTitle;
    if (self.hasActiveSubscription) {
        subscriptionCellTitle = NSLocalizedStringWithDefaultValue(@"SETTINGS_SUBSCRIPTION_ACTIVE",
          nil,
          [NSBundle mainBundle],
          @"Subscriptions",
          @"Subscriptions item title in the app settings when user has an active subscription. Clicking this item opens subscriptions view");
    } else {
        subscriptionCellTitle = NSLocalizedStringWithDefaultValue(@"SETTINGS_SUBSCRIPTION_NOT_ACTIVE",
          nil,
          [NSBundle mainBundle],
          @"Go premium!",
          @"Subscriptions item title in the app settings when user does not have an active subscription. Clicking this item opens subscriptions view. If “Premium” doesn't easily translate, please choose a term that conveys “Pro” or “Extra” or “Better” or “Elite”.");
    }

    [subscriptionTableViewCell.textLabel setText:subscriptionCellTitle];
}

- (void)updateReinstallVPNProfileCell {
    if (reinstallVPNProfileCell) {
        BOOL enableReinstallVPNProfileCell = self.vpnStatus == VPNStatusDisconnected || self.vpnStatus == VPNStatusInvalid;
        reinstallVPNProfileCell.userInteractionEnabled = enableReinstallVPNProfileCell;
        reinstallVPNProfileCell.textLabel.enabled = enableReinstallVPNProfileCell;
        reinstallVPNProfileCell.detailTextLabel.enabled = enableReinstallVPNProfileCell;
    }
}

#pragma mark - Table constuctor methods

- (void)settingsViewController:(IASKAppSettingsViewController*)sender tableView:(UITableView *)tableView didSelectCustomViewSpecifier:(IASKSpecifier*)specifier {
    [super settingsViewController:self tableView:tableView didSelectCustomViewSpecifier:specifier];
    if ([specifier.key isEqualToString:SettingsSubscriptionCellSpecifierKey]) {
        [self openIAPViewController];
    } else if ([specifier.key isEqualToString:SettingsPsiCashCellSpecifierKey]) {
        [self openPsiCashViewController];
    } else if ([specifier.key isEqualToString:SettingsReinstallVPNConfigurationKey]) {
        [[VPNManager sharedInstance] reinstallVPNConfiguration];
        [self settingsViewControllerDidEnd:nil];
    }
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForSpecifier:(IASKSpecifier*)specifier {
    UITableViewCell *cell = nil;
    if (![specifier.key isEqualToString:SettingsPsiCashCellSpecifierKey]
        && ![specifier.key isEqualToString:SettingsReinstallVPNConfigurationKey]
        && ![specifier.key isEqualToString:SettingsSubscriptionCellSpecifierKey]) {
        cell = [super tableView:tableView cellForSpecifier:specifier];
        return cell;
    }

    if ([specifier.key isEqualToString:SettingsSubscriptionCellSpecifierKey]) {

        cell = [super tableView:tableView cellForSpecifier:specifier];
        [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
        subscriptionTableViewCell = cell;
        [self updateSubscriptionCell];

    } else if ([specifier.key isEqualToString:SettingsReinstallVPNConfigurationKey]) {

        cell = [super tableView:tableView cellForSpecifier:specifier];
        [cell setAccessoryType:UITableViewCellAccessoryNone];
        [cell.textLabel setText:NSLocalizedStringWithDefaultValue(@"SETTINGS_REINSTALL_VPN_CONFIGURATION_CELL_TITLE",
                                                                  nil,
                                                                  [NSBundle mainBundle],
                                                                  @"Reinstall VPN profile",
                                                                  @"Title of cell in settings menu which, when pressed, reinstalls the user's VPN profile for Psiphon")];
        reinstallVPNProfileCell = cell;
        [self updateReinstallVPNProfileCell];

    } else if ([specifier.key isEqualToString:SettingsPsiCashCellSpecifierKey]) {

        cell = [super tableView:tableView cellForSpecifier:specifier];
        [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
        [cell.textLabel setText:@"PsiCash"];

    }

    assert(cell != nil);
    return cell;
}

- (void)openIAPViewController {
    IAPViewController *iapViewController = [[IAPViewController alloc]init];
    iapViewController.openedFromSettings = YES;
    [self.navigationController pushViewController:iapViewController animated:YES];
}

#pragma mark - PsiCash

- (void)openPsiCashViewController {
    PsiCashOnboardingViewController *onboarding = [[PsiCashOnboardingViewController alloc] init];
    [self presentViewController:onboarding animated:NO completion:nil];
}

@end
