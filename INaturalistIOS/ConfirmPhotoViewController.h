//
//  ConfirmPhotoViewController.h
//  iNaturalist
//
//  Created by Alex Shepard on 2/25/15.
//  Copyright (c) 2015 iNaturalist. All rights reserved.
//

#import <UIKit/UIKit.h>

@class Taxon;
@class Project;

@interface ConfirmPhotoViewController : UIViewController

@property UIImage *image;
@property NSArray *assets;
@property NSDictionary *metadata;
@property BOOL shouldContinueUpdatingLocation;

@property Taxon *taxon;
@property Project *project;

@property (nonatomic, copy) void(^confirmFollowUpAction)(NSArray *confirmedAssets);


@end
