//
//  Observation.m
//  iNaturalist
//
//  Created by Ken-ichi Ueda on 2/15/12.
//  Copyright (c) 2012 iNaturalist. All rights reserved.
//

#import "Observation.h"
#import "ObservationFieldValue.h"
#import "ObservationField.h"
#import "Taxon.h"
#import "Comment.h"
#import "Identification.h"
#import "ObservationPhoto.h"
#import "DeletedRecord.h"
#import "ProjectObservation.h"

static RKManagedObjectMapping *defaultMapping = nil;
static RKObjectMapping *defaultSerializationMapping = nil;

@implementation Observation

@dynamic speciesGuess;
@dynamic taxonID;
@dynamic inatDescription;
@dynamic latitude;
@dynamic longitude;
@dynamic positionalAccuracy;
@dynamic observedOn;
@dynamic localObservedOn;
@dynamic observedOnString;
@dynamic timeObservedAt;
@dynamic userID;
@dynamic placeGuess;
@dynamic idPlease;
@dynamic iconicTaxonID;
@dynamic iconicTaxonName;
@dynamic privateLatitude;
@dynamic privateLongitude;
@dynamic privatePositionalAccuracy;
@dynamic geoprivacy;
@dynamic qualityGrade;
@dynamic positioningMethod;
@dynamic positioningDevice;
@dynamic outOfRange;
@dynamic license;
@dynamic observationPhotos;
@dynamic observationFieldValues;
@dynamic projectObservations;
@dynamic taxon;
@dynamic commentsCount;
@dynamic identificationsCount;
@dynamic hasUnviewedActivity;
@dynamic comments;
@dynamic identifications;
@dynamic sortable;
@dynamic uuid;

+ (NSArray *)all
{
    return [self objectsWithFetchRequest:self.defaultDescendingSortedFetchRequest];
}

+ (Observation *)stub
{
    NSArray *speciesGuesses = [[NSArray alloc] initWithObjects:
                               @"House Sparrow", 
                               @"Mourning Dove", 
                               @"Amanita muscaria", 
                               @"Homo sapiens", nil];
    NSArray *placeGuesses = [[NSArray alloc] initWithObjects:
                             @"Berkeley, CA", 
                             @"Clinton, CT", 
                             @"Mount Diablo State Park, Contra Costa County, CA, USA", 
                             @"somewhere in nevada", nil];    
    Observation *o = [Observation object];
    o.speciesGuess = [speciesGuesses objectAtIndex:rand() % speciesGuesses.count];
    o.localObservedOn = [NSDate date];
    o.observedOnString = [Observation.jsDateFormatter stringFromDate:o.localObservedOn];
    o.placeGuess = [placeGuesses objectAtIndex:rand() % [placeGuesses count]];
    o.latitude = [NSNumber numberWithInt:rand() % 89];
    o.longitude = [NSNumber numberWithInt:rand() % 179];
    o.positionalAccuracy = [NSNumber numberWithInt:rand() % 500];
    o.inatDescription = @"Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.";
    return o;
}

+ (RKManagedObjectMapping *)mapping
{
    if (!defaultMapping) {
        defaultMapping = [RKManagedObjectMapping mappingForClass:[Observation class]
                                            inManagedObjectStore:[RKManagedObjectStore defaultObjectStore]];
        [defaultMapping mapKeyPathsToAttributes:
         @"id", @"recordID",
         @"species_guess", @"speciesGuess",
         @"description", @"inatDescription",
         @"created_at_utc", @"createdAt",
         @"updated_at_utc", @"updatedAt",
         @"observed_on", @"observedOn",
         @"observed_on_string", @"observedOnString",
         @"time_observed_at_utc", @"timeObservedAt",
         @"place_guess", @"placeGuess",
         @"latitude", @"latitude",
         @"longitude", @"longitude",
         @"positional_accuracy", @"positionalAccuracy",
         @"private_latitude", @"privateLatitude",
         @"private_longitude", @"privateLongitude",
         @"private_positional_accuracy", @"privatePositionalAccuracy",
         @"taxon_id", @"taxonID",
         @"iconic_taxon_id", @"iconicTaxonID",
         @"iconic_taxon_name", @"iconicTaxonName",
		 @"comments_count", @"commentsCount",
		 @"identifications_count", @"identificationsCount",
		 @"last_activity_at_utc", @"lastActivityAt",
         @"uuid", @"uuid",
         @"id_please", @"idPlease",
         @"geoprivacy", @"geoprivacy",
         @"user_id", @"userID",
         nil];
        [defaultMapping mapKeyPath:@"taxon" 
                    toRelationship:@"taxon" 
                       withMapping:[Taxon mapping]
                         serialize:NO];
		[defaultMapping mapKeyPath:@"comments"
                    toRelationship:@"comments"
                       withMapping:[Comment mapping]
                         serialize:NO];
		[defaultMapping mapKeyPath:@"identifications"
                    toRelationship:@"identifications"
                       withMapping:[Identification mapping]
                         serialize:NO];
        [defaultMapping mapKeyPath:@"observation_field_values"
                    toRelationship:@"observationFieldValues"
                       withMapping:[ObservationFieldValue mapping]
                         serialize:NO];
		[defaultMapping mapKeyPath:@"observation_photos"
                    toRelationship:@"observationPhotos"
                       withMapping:[ObservationPhoto mapping]
                         serialize:NO];
        [defaultMapping mapKeyPath:@"project_observations"
                    toRelationship:@"projectObservations"
                       withMapping:[ProjectObservation mapping]
                         serialize:NO];
        defaultMapping.primaryKeyAttribute = @"recordID";
    }
    return defaultMapping;
}

+ (RKObjectMapping *)serializationMapping
{
    if (!defaultSerializationMapping) {
        defaultSerializationMapping = [[RKManagedObjectMapping mappingForClass:[Observation class]
                                                          inManagedObjectStore:[RKManagedObjectStore defaultObjectStore]] inverseMapping];
        [defaultSerializationMapping mapKeyPathsToAttributes:
         @"speciesGuess", @"observation[species_guess]",
         @"inatDescription", @"observation[description]",
         @"observedOnString", @"observation[observed_on_string]",
         @"placeGuess", @"observation[place_guess]",
         @"latitude", @"observation[latitude]",
         @"longitude", @"observation[longitude]",
         @"positionalAccuracy", @"observation[positional_accuracy]",
         @"taxonID", @"observation[taxon_id]",
         @"iconicTaxonID", @"observation[iconic_taxon_id]",
         @"idPlease", @"observation[id_please]",
         @"geoprivacy", @"observation[geoprivacy]",
         @"uuid", @"observation[uuid]",
         nil];
    }
    return defaultSerializationMapping;
}

- (void)awakeFromInsert {
    [super awakeFromInsert];
    
    // unsafe to fetch in -awakeFromInsert
    [self performSelector:@selector(computeLocalObservedOn)
               withObject:nil
               afterDelay:0];
}

- (void)awakeFromFetch {
    [super awakeFromFetch];
    
    // safe to use getters & setters in -awakeFromFetch
    [self computeLocalObservedOn];
}

- (void)computeLocalObservedOn {
    if (!self.localObservedOn) {
        if (self.timeObservedAt) self.localObservedOn = self.timeObservedAt;
        else if (self.observedOn) self.localObservedOn = self.observedOn;
    }
}

- (NSArray *)sortedObservationPhotos
{
    NSSortDescriptor *sortDescriptor1 = [[NSSortDescriptor alloc] initWithKey:@"position" ascending:YES];
    NSSortDescriptor *sortDescriptor2 = [[NSSortDescriptor alloc] initWithKey:@"recordID" ascending:YES];
    NSSortDescriptor *sortDescriptor3 = [[NSSortDescriptor alloc] initWithKey:@"localCreatedAt" ascending:YES];
    return [self.observationPhotos 
            sortedArrayUsingDescriptors:
            [NSArray arrayWithObjects:sortDescriptor1, sortDescriptor2, sortDescriptor3, nil]];
}

- (NSArray *)sortedProjectObservations
{
    NSSortDescriptor *titleSort = [[NSSortDescriptor alloc] initWithKey:@"project.title" ascending:YES];
    return [self.projectObservations sortedArrayUsingDescriptors:
            [NSArray arrayWithObjects:titleSort, nil]];
}

- (NSString *)observedOnPrettyString
{
    if (!self.localObservedOn) return @"Unknown";
    return [Observation.prettyDateFormatter stringFromDate:self.localObservedOn];
}

- (NSString *)observedOnShortString
{
    if (!self.localObservedOn) return @"";
    NSDateFormatter *fmt = Observation.shortDateFormatter;
    NSDate *now = [NSDate date];
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *comps = [cal components:NSDayCalendarUnit fromDate:self.localObservedOn toDate:now options:0];
    if (comps.day == 0) {
        fmt.dateStyle = NSDateFormatterNoStyle;
        fmt.timeStyle = NSDateFormatterShortStyle;
    } else {
        fmt.dateStyle = NSDateFormatterShortStyle;
        fmt.timeStyle = NSDateFormatterNoStyle;
    }
    return [fmt stringFromDate:self.localObservedOn];
}

- (UIColor *)iconicTaxonColor
{
    if ([self.iconicTaxonName isEqualToString:@"Animalia"] || 
        [self.iconicTaxonName isEqualToString:@"Actinopterygii"] ||
        [self.iconicTaxonName isEqualToString:@"Amphibia"] ||
        [self.iconicTaxonName isEqualToString:@"Reptilia"] ||
        [self.iconicTaxonName isEqualToString:@"Aves"] ||
        [self.iconicTaxonName isEqualToString:@"Mammalia"]) {
        return [UIColor blueColor];
    } else if ([self.iconicTaxonName isEqualToString:@"Mollusca"] ||
               [self.iconicTaxonName isEqualToString:@"Insecta"] ||
               [self.iconicTaxonName isEqualToString:@"Arachnida"]) {
        return [UIColor orangeColor];
    } else if ([self.iconicTaxonName isEqualToString:@"Plantae"]) {
        return [UIColor greenColor];
    } else if ([self.iconicTaxonName isEqualToString:@"Protozoa"]) {
        return [UIColor purpleColor];
    } else if ([self.iconicTaxonName isEqualToString:@"Fungi"]) {
        return [UIColor redColor];
    } else {
        return [UIColor darkGrayColor];
    }
}

- (NSNumber *)taxonID
{
    [self willAccessValueForKey:@"taxonID"];
    if (!self.primitiveTaxonID || [self.primitiveTaxonID intValue] == 0) {
        [self setPrimitiveTaxonID:self.taxon.recordID];
    }
    [self didAccessValueForKey:@"taxonID"];
    return [self primitiveTaxonID];
}

- (NSNumber *)iconicTaxonName
{
    [self willAccessValueForKey:@"iconicTaxonName"];
    if (!self.primitiveIconicTaxonName) {
        [self setPrimitiveIconicTaxonName:[self.taxon primitiveValueForKey:@"iconicTaxonName"]];
    }
    [self didAccessValueForKey:@"iconicTaxonName"];
    return [self primitiveIconicTaxonName];
}

// TODO when we start storing public observations this needs to check whether the obs belongs
// to the signed in user
- (NSNumber *)visibleLatitude
{
    if (self.privateLatitude) {
        return self.privateLatitude;
    }
    return self.latitude;
}

- (NSNumber *)visibleLongitude
{
    if (self.privateLongitude) {
        return self.privateLongitude;
    }
    return self.longitude;
}

- (NSInteger)activityCount {
    if (self.taxonID) {
        return MAX(0, self.commentsCount.integerValue + self.identificationsCount.integerValue - 1);
    } else {
        return MAX(0, self.commentsCount.integerValue + self.identificationsCount.integerValue);
    }
}

// TODO: try forKey: instead of forKeyPath:
- (BOOL)validateValue:(inout __autoreleasing id *)ioValue forKeyPath:(NSString *)inKeyPath error:(out NSError *__autoreleasing *)outError {
	// for observations which are due to be synced, only update the value if the local value is empty
	if (self.needsSync && self.localUpdatedAt != nil && ![inKeyPath isEqualToString:@"recordID"]) {
		return ([self valueForKeyPath:inKeyPath] == nil);
	}
	return [super validateValue:ioValue forKeyPath:inKeyPath error:outError];
}

+ (NSFetchRequest *)defaultDescendingSortedFetchRequest
{
    NSFetchRequest *request = [self fetchRequest];
    NSSortDescriptor *sd1 = [[NSSortDescriptor alloc] initWithKey:@"sortable" ascending:NO];
    [request setSortDescriptors:[NSArray arrayWithObjects:sd1, nil]];
    return request;
}

+ (NSFetchRequest *)defaultAscendingSortedFetchRequest
{
    NSFetchRequest *request = [self fetchRequest];
    NSSortDescriptor *sd1 = [[NSSortDescriptor alloc] initWithKey:@"sortable" ascending:YES];
    [request setSortDescriptors:[NSArray arrayWithObjects:sd1, nil]];
    return request;
}

- (Observation *)prevObservation
{
    NSFetchRequest *request = [Observation defaultDescendingSortedFetchRequest];
    [request setPredicate:[NSPredicate predicateWithFormat:@"sortable < %@", self.sortable]];
    Observation *prev = [Observation objectWithFetchRequest:request];
    return prev;
}

- (Observation *)nextObservation
{
    NSFetchRequest *request = [Observation defaultAscendingSortedFetchRequest];
    [request setPredicate:[NSPredicate predicateWithFormat:@"sortable > %@", self.sortable]];
    Observation *next = [Observation objectWithFetchRequest:request];
    return next;
}

- (void)willSave
{
    [super willSave];
    NSDate *sortableDate = self.createdAt ? self.createdAt : self.localCreatedAt;
    NSString *sortable = [NSString stringWithFormat:@"%f-%d", sortableDate.timeIntervalSinceReferenceDate, self.recordID.intValue];
    [self setPrimitiveValue:sortable forKey:@"sortable"];
    if (!self.uuid && !self.recordID) {
        [self setPrimitiveValue:[[NSUUID UUID] UUIDString] forKey:@"uuid"];
    }
}

- (void)prepareForDeletion
{
    if (self.syncedAt) {
        DeletedRecord *dr = [DeletedRecord object];
        dr.recordID = self.recordID;
        dr.modelName = NSStringFromClass(self.class);
    }
}

+ (NSArray *)needingUpload {
    // all observations that need sync are upload candidates
    NSMutableSet *needingUpload = [[NSMutableSet alloc] init];
    [needingUpload addObjectsFromArray:[self needingSync]];
    
    // also, all observations whose uploadable children need sync
    
    for (ObservationPhoto *op in [ObservationPhoto needingSync]) {
        if (op.observation) {
            [needingUpload addObject:op.observation];
        } else {
            [op destroy];
        }
    }
    
    for (ObservationFieldValue *ofv in [ObservationFieldValue needingSync]) {
        if (ofv.observation) {
            [needingUpload addObject:ofv.observation];
        } else {
            [ofv destroy];
        }
    }
    
    for (ProjectObservation *po in [ProjectObservation needingSync]) {
        if (po.observation) {
            [needingUpload addObject:po.observation];
        } else {
            [po destroy];
        }
    }
    
    return [[needingUpload allObjects] sortedArrayUsingComparator:^NSComparisonResult(INatModel *o1, INatModel *o2) {
        return [o1.localCreatedAt compare:o2.localCreatedAt];
    }];
}

- (BOOL)needsUpload {
    // needs upload if this obs needs sync, or any children need sync
    if (self.needsSync) { return YES; }
    for (ObservationPhoto *op in self.observationPhotos) {
        if (op.needsSync) { return YES; }
    }
    for (ObservationFieldValue *ofv in self.observationFieldValues) {
        if (ofv.needsSync) { return YES; }
    }
    for (ProjectObservation *po in self.projectObservations) {
        if (po.needsSync) { return YES; }
    }
    return NO;
}

-(NSArray *)childrenNeedingUpload {
    NSMutableArray *recordsToUpload = [NSMutableArray array];
    
    for (ObservationPhoto *op in self.observationPhotos) {
        if (op.needsSync) {
            [recordsToUpload addObject:op];
        }
    }
    for (ObservationFieldValue *ofv in self.observationFieldValues) {
        if (ofv.needsSync) {
            [recordsToUpload addObject:ofv];
        }
    }
    for (ProjectObservation *po in self.projectObservations) {
        if (po.needsSync) {
            [recordsToUpload addObject:po];
        }
    }
    
    return [NSArray arrayWithArray:recordsToUpload];
}

@end
