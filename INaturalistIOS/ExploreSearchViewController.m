//
//  ExploreSearchViewController.m
//  iNaturalist
//
//  Created by Alex Shepard on 11/10/14.
//  Copyright (c) 2014 iNaturalist. All rights reserved.
//

#import <FontAwesomeKit/FAKFoundationIcons.h>
#import <FontAwesomeKit/FAKIonIcons.h>
#import <BlocksKit/BlocksKit.h>
#import <SVProgressHUD/SVProgressHUD.h>
#import <SDWebImage/UIImageView+WebCache.h>
#import <CoreLocation/CoreLocation.h>

#import "ExploreSearchViewController.h"

#import "ExploreMapViewController.h"
#import "ExploreGridViewController.h"
#import "ExploreListViewController.h"
#import "ExploreObservationsController.h"
#import "ExploreActiveSearchView.h"
#import "ExploreLocation.h"
#import "ExploreMappingProvider.h"
#import "ExploreProject.h"
#import "ExplorePerson.h"
#import "UIColor+ExploreColors.h"
#import "Analytics.h"
#import "Taxon.h"
#import "TaxonPhoto.h"
#import "UIFont+ExploreFonts.h"
#import "UIImage+ExploreIconicTaxaImages.h"
#import "ExploreDisambiguator.h"
#import "ExploreSearchController.h"
#import "ExploreSearchView.h"
#import "AutocompleteSearchItem.h"
#import "ShortcutSearchItem.h"
#import "ExploreLeaderboardViewController.h"
#import "INaturalistAppDelegate+TransitionAnimators.h"
#import "SignupSplashViewController.h"
#import "UIColor+INaturalist.h"
#import "GolanProjectUtil.h"

@interface ExploreSearchViewController () <CLLocationManagerDelegate, ActiveSearchTextDelegate> {
    ExploreObservationsController *observationsController;
    
    ExploreSearchView *searchMenu;
    
    CLLocationManager *locationManager;
    
    NSTimer *locationFetchTimer;
    BOOL hasFulfilledLocationFetch;
    BOOL isFetchingLocation;
    
    ExploreMapViewController *mapVC;
    ExploreGridViewController *gridVC;
    ExploreListViewController *listVC;
    
    ExploreSearchController *searchController;
    
    UIBarButtonItem *leaderboardItem;
    UIBarButtonItem *spinnerItem;
    UIActivityIndicatorView *spinner;
    // Reference to the golan proejct, used for quick filter by project.
    ExploreProject *golanExploreProject;
}

@end


@implementation ExploreSearchViewController

// since we're coming out of a storyboard, -initWithCoder: is the initializer
- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super initWithCoder:aDecoder]) {
        
        self.navigationController.tabBarItem.image = ({
            FAKIcon *worldOutline = [FAKIonIcons iosWorldOutlineIconWithSize:35];
            [worldOutline addAttribute:NSForegroundColorAttributeName value:[UIColor inatInactiveGreyTint]];
            [[worldOutline imageWithSize:CGSizeMake(34, 45)] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        });
        
        self.navigationController.tabBarItem.selectedImage =({
            FAKIcon *worldFilled = [FAKIonIcons iosWorldIconWithSize:35];
            [worldFilled addAttribute:NSForegroundColorAttributeName value:[UIColor whiteColor]];
            [worldFilled imageWithSize:CGSizeMake(34, 45)];
        });
        
        self.navigationController.tabBarItem.title = NSLocalizedString(@"Explore", nil);
        
        UIBarButtonItem *search = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSearch
                                                                                target:self
                                                                                action:@selector(searchPressed)];
        self.navigationItem.leftBarButtonItem = search;
        
        leaderboardItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Stats", @"Title for button in the explore tab that leads to the stats leaderboard.")
                                                           style:UIBarButtonItemStylePlain
                                                          target:self
                                                          action:@selector(leaderboardPressed)];
        self.navigationItem.rightBarButtonItem = leaderboardItem;
        
        spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        spinnerItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];

        
        observationsController = [[ExploreObservationsController alloc] init];
        observationsController.notificationDelegate = self;
        
        searchController = [[ExploreSearchController alloc] init];
        
        [self searchForGolanProject];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    searchMenu = ({
        ExploreSearchView *view = [[ExploreSearchView alloc] initWithFrame:CGRectZero];
        view.translatesAutoresizingMaskIntoConstraints = NO;
          
        // autocomplete items
        AutocompleteSearchItem *critters = [AutocompleteSearchItem itemWithPredicate:NSLocalizedString(@"organisms", nil)
                                                                              action:^(NSString *searchText) {
                                                                                  [self searchForTaxon:searchText];
                                                                                  [searchMenu hideOptionSearch];
                                                                                  if (observationsController.activeSearchPredicates.count > 0)
                                                                                      [searchMenu showActiveSearch];
                                                                              }];
        AutocompleteSearchItem *people = [AutocompleteSearchItem itemWithPredicate:NSLocalizedString(@"people", nil)
                                                                            action:^(NSString *searchText) {
                                                                                [self searchForPerson:searchText];
                                                                                [searchMenu hideOptionSearch];
                                                                                if (observationsController.activeSearchPredicates.count > 0)
                                                                                    [searchMenu showActiveSearch];
                                                                            }];
        AutocompleteSearchItem *locations = [AutocompleteSearchItem itemWithPredicate:NSLocalizedString(@"locations", nil)
                                                                               action:^(NSString *searchText) {
                                                                                   [self searchForLocation:searchText];
                                                                                   [searchMenu hideOptionSearch];
                                                                                   if (observationsController.activeSearchPredicates.count > 0)
                                                                                       [searchMenu showActiveSearch];
                                                                               }];
        AutocompleteSearchItem *projects = [AutocompleteSearchItem itemWithPredicate:NSLocalizedString(@"projects", nil)
                                                                              action:^(NSString *searchText) {
                                                                                  [self searchForProject:searchText];
                                                                                  [searchMenu hideOptionSearch];
                                                                                  if (observationsController.activeSearchPredicates.count > 0)
                                                                                      [searchMenu showActiveSearch];
                                                                              }];
        view.autocompleteItems = @[critters, people, locations, projects];
        
        // non-autocomplete shortcut items
        ShortcutSearchItem *nearMe = [ShortcutSearchItem itemWithTitle:NSLocalizedString(@"Find observations near me", nil)
                                                                action:^{
                                                                    [self searchForNearbyObservations];
                                                                    [searchMenu hideOptionSearch];
                                                                    if (observationsController.activeSearchPredicates.count > 0)
                                                                        [searchMenu showActiveSearch];
                                                                }];
        
        ShortcutSearchItem *mine = [ShortcutSearchItem itemWithTitle:NSLocalizedString(@"Find my observations", nil)
                                                              action:^{
                                                                  if ([[NSUserDefaults standardUserDefaults] objectForKey:INatUsernamePrefKey]) {
                                                                      [self searchForMyObservations];
                                                                      [searchMenu hideOptionSearch];
                                                                      if (observationsController.activeSearchPredicates.count > 0)
                                                                          [searchMenu showActiveSearch];
                                                                  } else {
                                                                      [[Analytics sharedClient] event:kAnalyticsEventNavigateSignupSplash
                                                                                       withProperties:@{ @"From": @"Explore Search My Obs" }];

                                                                      SignupSplashViewController *splash = [[SignupSplashViewController alloc] initWithNibName:nil
                                                                                                                                                        bundle:nil];
                                                                      UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:splash];
                                                                      nav.delegate = (INaturalistAppDelegate *)[UIApplication sharedApplication].delegate;
                                                                      splash.animateIn = NO;
                                                                      splash.skippable = NO;
                                                                      splash.cancellable = YES;
                                                                      splash.reason = NSLocalizedString(@"You must be logged in to do that.",
                                                                                                        @"Unspecific signup prompt reason.");
                                                                      [self presentViewController:nav animated:YES completion:nil];
                                                                  }
                                                              }];
        view.shortcutItems = @[nearMe, mine];
        
        view.activeSearchFilterView.userInteractionEnabled = NO;
        [view.activeSearchFilterView.removeActiveSearchButton addTarget:self
                                                                 action:@selector(removeSearchPressed)
                                                       forControlEvents:UIControlEventTouchUpInside];
        view.activeSearchTextDelegate = self;
        
        view;
    });
    [self.view addSubview:searchMenu];
    
    // the search view overlays on top of all of the stuff in the container view
    self.overlayView = searchMenu;
    
    if ([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    
    // set up the map|grid|list selector
    mapVC = [[ExploreMapViewController alloc] initWithNibName:nil bundle:nil];
    mapVC.observationDataSource = observationsController;
    gridVC = [[ExploreGridViewController alloc] initWithNibName:nil bundle:nil];
    gridVC.observationDataSource = observationsController;
    listVC = [[ExploreListViewController alloc] initWithNibName:nil bundle:nil];
    listVC.observationDataSource = observationsController;
    self.viewControllers = @[mapVC, gridVC, listVC];
    
    // configure the segmented control
    [self.viewControllers bk_each:^(UIViewController *vc) {
        if ([vc conformsToProtocol:@protocol(ExploreViewControllerControlIcon)]) {
            [self.segmentedControl insertSegmentWithImage:[((id <ExploreViewControllerControlIcon>)vc) controlIcon]
                          atIndex:[self.viewControllers indexOfObject:vc]
                                                 animated:NO];
        }
    }];
    
    // display first item
    [self.segmentedControl setSelectedSegmentIndex:0];
    [self displayContentController:mapVC];
    
    NSDictionary *views = @{
                            @"searchMenu": searchMenu,
                            @"topLayoutGuide": self.topLayoutGuide,
                            @"bottomLayoutGuide": self.bottomLayoutGuide,
                            };
    
    
    // Configure the Active Search UI
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"|-0-[searchMenu]-0-|"
                                                                      options:0
                                                                      metrics:0
                                                                        views:views]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-0-[topLayoutGuide]-0-[searchMenu]-0-[bottomLayoutGuide]-0-|"
                                                                      options:0
                                                                      metrics:0
                                                                        views:views]];
}

/// Find which controller is being displayed and update predicate accordingly
- (void)displayContentController:(UIViewController*)content {
    [super displayContentController:content];
    // check first if the user isn't activly searching for something.
    if(!searchMenu.isDuringSearch) {
        if([content isKindOfClass:[ExploreMapViewController class]]) {
            if(golanExploreProject) {
                [observationsController removeSearchPredicate:[ExploreSearchPredicate predicateForProject:golanExploreProject]];
            }
            [observationsController removeAllSearchPredicatesUpdatingObservations:NO];
            [searchMenu hideActiveSearch];
            [mapVC mapShouldZoomToCoordinates:locationManager.location.coordinate showUserLocation:YES];
        }
        else if([content isKindOfClass:[ExploreGridViewController class]] || [content isKindOfClass:[ExploreListViewController class]]) {
            // clear any stashed objects
            observationsController.observations = [NSOrderedSet orderedSet];
            // observations controller will fetch observations using this predicate
            if(golanExploreProject) {
                // Clean previous predicates
                [observationsController removeAllSearchPredicatesUpdatingObservations:NO];
                // Set the region for Golan
                ExploreRegion *region = [[ExploreRegion alloc] init];
                region.swCoord = CLLocationCoordinate2DMake(32.538696864360602, 35.302336202911135);
                region.neCoord = CLLocationCoordinate2DMake(33.583818694791482, 36.179391797088897);
                observationsController.limitingRegion = region;
                [observationsController addSearchPredicate:[ExploreSearchPredicate predicateForProject:golanExploreProject]];
                [searchMenu showActiveSearch];
            }
        }
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    [self startLookingForCurrentLocationNotify:NO];
}


#pragma mark - UIControl targets

- (void)leaderboardPressed {
    ExploreLeaderboardViewController *vc = [[ExploreLeaderboardViewController alloc] initWithNibName:nil bundle:nil];
    vc.observationsController = observationsController;
    
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)removeSearchPressed {
    [searchMenu hideActiveSearch];
    
    [observationsController removeAllSearchPredicates];
}

- (void)searchPressed {
    if ([searchMenu optionSearchIsActive]) {
        if (observationsController.activeSearchPredicates.count > 0) {
            [searchMenu showActiveSearch]; // implicitly hides option search
        } else {
            [searchMenu hideOptionSearch];
        }
    } else {
        [searchMenu showOptionSearch];
    }
}

#pragma mark - iNat API Calls

- (void)searchForMyObservations {

    if (![[[RKClient sharedClient] reachabilityObserver] isNetworkReachable]) {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Network unavailable, cannot search iNaturalist.org", nil)];
        return;
    }

    // clear all active search predicates
    // since it's not built to remove them one at a time yet
    [observationsController removeAllSearchPredicatesUpdatingObservations:NO];
    
    [SVProgressHUD showWithStatus:NSLocalizedString(@"Fetching...", nil)];
    
    [searchController searchForLogin:[[NSUserDefaults standardUserDefaults] valueForKey:INatUsernamePrefKey] completionHandler:^(NSArray *results, NSError *error) {
        if (error) {
            
        } else {
            
            [[Analytics sharedClient] event:kAnalyticsEventExploreSearchMine];
            
            if (results.count == 0) {
                searchMenu.isDuringSearch = NO;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Can't find your user details. :(", nil)];
                });
            } else if (results.count == 1) {
                // dismiss the HUD
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Found you!", nil)];
                });
                
                // observations controller will fetch observations using this predicate
                [observationsController addSearchPredicate:[ExploreSearchPredicate predicateForPerson:results.firstObject]];
                
                [searchMenu showActiveSearch];

            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Found conflicting user details. :(", nil)];
                });
            }
        }
        
    }];
    
}

- (void)searchForNearbyObservations {
    
    if (![[[RKClient sharedClient] reachabilityObserver] isNetworkReachable]) {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Network unavailable, cannot search iNaturalist.org", nil)];
        return;
    }
    
    hasFulfilledLocationFetch = NO;
    
    [[Analytics sharedClient] event:kAnalyticsEventExploreSearchNearMe];
    
    // clear all active search predicates
    // since it's not built to remove them one at a time yet
    [observationsController removeAllSearchPredicatesUpdatingObservations:NO];
    
    // no predicates, so hide the active search UI
    [searchMenu hideActiveSearch];
    
    // get observations near current location
    switch ([CLLocationManager authorizationStatus]) {
        case kCLAuthorizationStatusNotDetermined:
            [self startLookingForCurrentLocationNotify:YES];
            break;
        case kCLAuthorizationStatusAuthorizedAlways:
        case kCLAuthorizationStatusAuthorizedWhenInUse:
            [self startLookingForCurrentLocationNotify:YES];
            break;
            
        case kCLAuthorizationStatusDenied:
        case kCLAuthorizationStatusRestricted:
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Permission denied", nil)
                                        message:NSLocalizedString(@"We don't have permission from iOS to use your location.", nil)
                                       delegate:nil
                              cancelButtonTitle:NSLocalizedString(@"OK", nil)
                              otherButtonTitles:nil] show];
        default:
            break;
    }
}

- (void)searchForTaxon:(NSString *)text {
    
    if (![[[RKClient sharedClient] reachabilityObserver] isNetworkReachable]) {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Network unavailable, cannot search iNaturalist.org", nil)];
        return;
    }

    [SVProgressHUD showWithStatus:NSLocalizedString(@"Searching for organisms...", nil)];
    
    [searchController searchForTaxon:text completionHandler:^(NSArray *results, NSError *error) {
        if (error) {
            [SVProgressHUD showErrorWithStatus:error.localizedDescription];
        } else {
            
            [[Analytics sharedClient] event:kAnalyticsEventExploreSearchCritters];

            if (results.count == 0) {
                searchMenu.isDuringSearch = NO;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"No such organisms found. :(", nil)];
                });
            } else if (results.count == 1) {
                // dismiss the HUD
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Found one!", nil)];
                });
                
                // observations controller will fetch observations using this predicate
                [observationsController addSearchPredicate:[ExploreSearchPredicate predicateForTaxon:results.firstObject]];
                
                [searchMenu showActiveSearch];
                
            } else {
                
                // allow the user to disambiguate the search results
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SVProgressHUD dismiss];
                });
                
                ExploreDisambiguator *disambiguator = [[ExploreDisambiguator alloc] init];
                disambiguator.title = NSLocalizedString(@"Which organism?", nil);
                disambiguator.searchOptions = results;
                
                __weak typeof(self)weakSelf = self;
                disambiguator.chosenBlock = ^void(id choice) {
                    // observations controller will fetch observations using this taxon
                    [observationsController addSearchPredicate:[ExploreSearchPredicate predicateForTaxon:(Taxon *)choice]];
                    
                    __strong typeof(weakSelf)strongSelf = weakSelf;
                    [strongSelf->searchMenu showActiveSearch];
                };
                
                // dispatch after a bit to allow SVPRogressHUD to finish animating dismissal
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [disambiguator presentDisambiguationAlert];
                });
            }
        }
    }];
    
}

- (void)searchForPerson:(NSString *)text {
    
    if (![[[RKClient sharedClient] reachabilityObserver] isNetworkReachable]) {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Network unavailable, cannot search iNaturalist.org", nil)];
        return;
    }

    [SVProgressHUD showWithStatus:NSLocalizedString(@"Searching for people...", nil)];

    [searchController searchForPerson:text completionHandler:^(NSArray *results, NSError *error) {
        if (error) {
            [SVProgressHUD showErrorWithStatus:error.localizedDescription];
        } else {
            
            [[Analytics sharedClient] event:kAnalyticsEventExploreSearchPeople];
            
            if (results.count == 0) {
                searchMenu.isDuringSearch = NO;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"No such person found. :(", nil)];
                });
            } else if (results.count == 1) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Found one!", nil)];
                });
                
                // observations controller will fetch observations using this predicate
                [observationsController addSearchPredicate:[ExploreSearchPredicate predicateForPerson:results.firstObject]];
                
                [searchMenu showActiveSearch];
                
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SVProgressHUD dismiss];
                });
                
                ExploreDisambiguator *disambiguator = [[ExploreDisambiguator alloc] init];
                disambiguator.title = NSLocalizedString(@"Which person?", nil);
                disambiguator.searchOptions = results;
                
                __weak typeof(self)weakSelf = self;
                disambiguator.chosenBlock = ^void(id choice) {
                    __strong typeof(weakSelf)strongSelf = weakSelf;

                    // observations controller will fetch observations using this predicate
                    [strongSelf->observationsController addSearchPredicate:[ExploreSearchPredicate predicateForPerson:(ExplorePerson *)choice]];
                    
                    [strongSelf->searchMenu showActiveSearch];
                };
                // dispatch after a bit to allow SVPRogressHUD to finish animating dismissal
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [disambiguator presentDisambiguationAlert];
                });
            }
        }
    }];
}

- (void)searchForLocation:(NSString *)text {
    
    if (![[[RKClient sharedClient] reachabilityObserver] isNetworkReachable]) {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Network unavailable, cannot search iNaturalist.org", nil)];
        return;
    }

    [SVProgressHUD showWithStatus:NSLocalizedString(@"Searching for place...", nil)];
    
    [searchController searchForLocation:text completionHandler:^(NSArray *results, NSError *error) {
        if (error) {
            [SVProgressHUD showErrorWithStatus:error.localizedDescription];
        } else {
            
            [[Analytics sharedClient] event:kAnalyticsEventExploreSearchPlaces];

            // filter out garbage locations
            NSArray *validPlaces = [results bk_select:^BOOL(ExploreLocation *location) {
                // all administrative places are valid
                if (location.adminLevel) { return YES; }
                // all open spaces (parks) are valid
                if (location.type == 100) { return YES; }
                // everything else is invalid
                return NO;
            }];
            
            if (validPlaces.count == 0) {
                CLGeocoder *geocoder = [[CLGeocoder alloc] init];
                [geocoder geocodeAddressString:text
                                      inRegion:nil  // if we're auth'd for location svcs, uses the user's location as the region
                             completionHandler:^(NSArray *placemarks, NSError *error) {
                                 if (error.code == kCLErrorNetwork) {
                                     [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Please try again in a few moments.",
                                                                                          @"Error message for the user, when the geocoder is telling us to slow down.")];
                                 } else {
                                     if (placemarks.count == 0) {
                                         [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"No such place found. :(", nil)];
                                     } else {
                                         CLPlacemark *place = placemarks.firstObject;
                                         [SVProgressHUD showSuccessWithStatus:place.name];
                                         [mapVC mapShouldZoomToCoordinates:place.location.coordinate showUserLocation:YES];
                                     }
                                 }
                             }];
            } else if (validPlaces.count == 1) {
                // dismiss the HUD
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Found one!", nil)];
                });
                
                // observations controller will fetch observations using this predicate
                [observationsController addSearchPredicate:[ExploreSearchPredicate predicateForLocation:(ExploreLocation *)validPlaces.firstObject]];
                
                [searchMenu showActiveSearch];
                
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SVProgressHUD dismiss];
                });
                
                ExploreDisambiguator *disambiguator = [[ExploreDisambiguator alloc] init];
                disambiguator.title = NSLocalizedString(@"Which place?", nil);
                disambiguator.searchOptions = results;
                
                __weak typeof(self)weakSelf = self;
                disambiguator.chosenBlock = ^void(id choice) {
                    __strong typeof(weakSelf)strongSelf = weakSelf;

                    // observations controller will fetch observations using this predicate
                    [strongSelf->observationsController addSearchPredicate:[ExploreSearchPredicate predicateForLocation:(ExploreLocation *)choice]];

                    [strongSelf->searchMenu showActiveSearch];
                };
                // dispatch after a bit to allow SVPRogressHUD to finish animating dismissal
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [disambiguator presentDisambiguationAlert];
                });
            }
        }
    }];
    
}

- (void)searchForProject:(NSString *)text {
    
    if (![[[RKClient sharedClient] reachabilityObserver] isNetworkReachable]) {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Network unavailable, cannot search iNaturalist.org", nil)];
        return;
    }

    [SVProgressHUD showWithStatus:NSLocalizedString(@"Searching for project...", nil)];
    
    [searchController searchForProject:text completionHandler:^(NSArray *results, NSError *error) {
        if (error) {
            [SVProgressHUD showErrorWithStatus:error.localizedDescription];
        } else {
            [[Analytics sharedClient] event:kAnalyticsEventExploreSearchProjects];
            
            if (results.count == 0) {
                searchMenu.isDuringSearch = NO;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"No such project found. :(", nil)];
                });
            } else if (results.count == 1) {
                // dismiss the HUD
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Found one!", nil)];
                });
                
                // observations controller will fetch observations using this predicate
                [observationsController addSearchPredicate:[ExploreSearchPredicate predicateForProject:results.firstObject]];
                
                [searchMenu showActiveSearch];

            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SVProgressHUD dismiss];
                });
                
                ExploreDisambiguator *disambiguator = [[ExploreDisambiguator alloc] init];
                disambiguator.title = NSLocalizedString(@"Which project?", nil);
                disambiguator.searchOptions = results;
                
                __weak typeof(self)weakSelf = self;
                disambiguator.chosenBlock = ^void(id choice) {
                    __strong typeof(weakSelf)strongSelf = weakSelf;

                    // observations controller will fetch observations using this predicate
                    [strongSelf->observationsController addSearchPredicate:[ExploreSearchPredicate predicateForProject:(ExploreProject *)choice]];

                    [strongSelf->searchMenu showActiveSearch];
                };
                // dispatch after a bit to allow SVPRogressHUD to finish animating dismissal
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [disambiguator presentDisambiguationAlert];
                });
            }
        }
    }];    
}

/// Searching for golan explore project for quick filter.
- (void)searchForGolanProject {
    if (![[[RKClient sharedClient] reachabilityObserver] isNetworkReachable]) {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Network unavailable, cannot search iNaturalist.org", nil)];
        return;
    }
    Project *golanProject = [GolanProjectUtil golanProject];
    if(golanProject) {
        [searchController searchForProject:golanProject.title completionHandler:^(NSArray *results, NSError *error) {
            if (error) {
                [SVProgressHUD showErrorWithStatus:error.localizedDescription];
            } else {
                if(results.count == 1) {
                    golanExploreProject = results.firstObject;
                }
                else {
                    NSLog(@"ERROR: Couldn't find golan explore project.");
                }
                
            }
            
        }];
    }
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    if ([SVProgressHUD isVisible]) {
        [SVProgressHUD showErrorWithStatus:error.localizedDescription];
    }

    isFetchingLocation = NO;
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    if (hasFulfilledLocationFetch)
        return;
    
    isFetchingLocation = NO;
    CLLocation *recentLocation = locations.lastObject;
    
    [locationFetchTimer invalidate];
    
    [locationManager stopUpdatingLocation];
    
    // one location fetch per user interaction with the "find observations near me" menu item
    if (!hasFulfilledLocationFetch) {
        hasFulfilledLocationFetch = YES;
        
        if ([SVProgressHUD isVisible]) {
            [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Found you!", nil)];
        }
        
        [mapVC mapShouldZoomToCoordinates:recentLocation.coordinate showUserLocation:YES];
    }
}

-(void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    if (hasFulfilledLocationFetch)
        return;
    
    switch ([CLLocationManager authorizationStatus]) {
        case kCLAuthorizationStatusNotDetermined:
            return;
            break;
        case kCLAuthorizationStatusAuthorizedAlways:
        case kCLAuthorizationStatusAuthorizedWhenInUse:
            [self startLookingForCurrentLocationNotify:NO];
            break;
        case kCLAuthorizationStatusDenied:
        case kCLAuthorizationStatusRestricted:
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Permission denied", nil)
                                        message:NSLocalizedString(@"We don't have permission from iOS to use your location.", nil)
                                       delegate:nil
                              cancelButtonTitle:NSLocalizedString(@"OK", nil)
                              otherButtonTitles:nil] show];
        default:
            break;
    }
}

#pragma mark - Location Manager helpers

- (void)startLookingForCurrentLocationNotify:(BOOL)shouldNotify {
    if (isFetchingLocation)
        return;
    
    if (hasFulfilledLocationFetch)
        return;
    
    isFetchingLocation = YES;
    locationManager = [[CLLocationManager alloc] init];
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"8.0")) {
        // request will start over
        [locationManager requestWhenInUseAuthorization];
    }
    
    locationManager.delegate = self;
    locationManager.distanceFilter = 1000;
    [locationManager stopUpdatingLocation];
    [locationManager startUpdatingLocation];
    // this may take a moment
    if (shouldNotify) {
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Finding your location...", nil)];
    }
    
    locationFetchTimer = [NSTimer bk_scheduledTimerWithTimeInterval:15.0f
                                                              block:^(NSTimer *timer) {
                                                                  if (shouldNotify) {
                                                                    [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Unable to find location", nil)];
                                                                  }
                                                                  
                                                                  [locationManager stopUpdatingLocation];
                                                                  locationManager = nil;
                                                                  isFetchingLocation = NO;
                                                              }
                                                            repeats:NO];
}



#pragma mark ActiveSearchText delegate

- (NSString *)activeSearchText {
    return observationsController.combinedColloquialSearchPhrase;
}

#pragma mark - ExploreObsNotificationDelegate

- (void)startedObservationFetch {
    [spinner startAnimating];
    self.navigationItem.rightBarButtonItem = spinnerItem;
}

- (void)finishedObservationFetch {
    if (!observationsController.isFetching) {
        // set the right bar button item to the reload button
        self.navigationItem.rightBarButtonItem = leaderboardItem;
        // stop the progress view
        [spinner stopAnimating];
    }
}

- (void)failedObservationFetch:(NSError *)error {
//    if(error.code == -1014 && searchMenu.isDuringSearch)
//        searchMenu.isDuringSearch = NO;
    
    [SVProgressHUD showErrorWithStatus:error.localizedDescription];
    // set the right bar button item to the reload button
    self.navigationItem.rightBarButtonItem = leaderboardItem;
    // stop the progress view
    [spinner stopAnimating];
}

@end
