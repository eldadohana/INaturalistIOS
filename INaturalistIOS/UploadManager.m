//
//  UploadManager.m
//  iNaturalist
//
//  Created by Ken-ichi Ueda on 3/20/12.
//  Copyright (c) 2012 iNaturalist. All rights reserved.
//

#import "UploadManager.h"
#import "INatModel.h"
#import "DeletedRecord.h"
#import "Observation.h"
#import "Analytics.h"

@interface UploadManager ()
@property (nonatomic, strong) NSMutableArray *queue;
@property (nonatomic, weak) id <UploadManagerNotificationDelegate> delegate;
@property (nonatomic, strong) RKObjectLoader *loader;
@property (nonatomic, assign) BOOL started;
@property NSOperationQueue *uploadWorkQueue;
@end

@implementation UploadManager

- (id)initWithDelegate:(id)delegate
{
    self = [super init];
    if (self) {
        self.delegate = delegate;
        self.queue = [[NSMutableArray alloc] init];
        
        self.uploadWorkQueue = [[NSOperationQueue alloc] init];
        self.uploadWorkQueue.maxConcurrentOperationCount = 1;
    }
    return self;
}

- (void)dealloc {
    [[[RKClient sharedClient] requestQueue] cancelRequestsWithDelegate:self];   
}

- (void)addModel:(id)model
{
    [self addModel:model syncSelector:nil];
}

- (void)addModel:(id)model syncSelector:(SEL)syncSelector
{
    NSMutableDictionary *d = [@{
                                @"model": model,
                                @"needingSyncCount": @([model needingSyncCount]),
                                @"syncedCount": @(0),
                                @"deletedRecordCount": @([model deletedRecordCount]),
                                } mutableCopy];
    if (syncSelector)
        d[@"syncSelector"] = NSStringFromSelector(syncSelector);
    
    [self.queue addObject:d];
}

- (void)start
{
    [RKObjectManager.sharedManager.client setAuthenticationType: RKRequestAuthenticationTypeNone];
//RKRequestAuthenticationTypeHTTPBasic;
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    if (self.queue.count == 0) {
        [self finish];
        return;
    }
    self.started = YES;
    NSMutableDictionary *current = self.queue.firstObject;
    if (!current) {
        [self stop];
        return;
    }

    id model = [current objectForKey:@"model"];
    
    NSInteger deletedRecordCount = [[current objectForKey:@"deletedRecordCount"] intValue];
    NSArray *recordsToSync = [model needingSync];
    
    [[Analytics sharedClient] debugLog:[NSString stringWithFormat:@"SYNC start %@, %ld to upload, %ld to delete",
                                        model, (long)recordsToSync.count, (long)deletedRecordCount]];

    // delete objects first
    if (deletedRecordCount > 0) {
        [self startDelete];
        return;
    }
    
    if (recordsToSync.count == 0) {
        [[Analytics sharedClient] debugLog:[NSString stringWithFormat:@"SYNC finished %@", model]];
        [self.queue removeObject:current];
        [self start];
        return;
    }
    
    [[Analytics sharedClient] debugLog:[NSString stringWithFormat:@"SYNC start uploading %@", model]];
    
    // manually applying mappings b/c PUT and POST responses return JSON without a root element, 
    // e.g. {foo: 'bar'} instead of observation: {foo: 'bar'}, which RestKit apparently can't 
    // deal with using the name of the model it just posted.
    for (INatModel *record in recordsToSync) {
        if ([current objectForKey:@"syncSelector"]) {
            
            [[Analytics sharedClient] debugLog:[NSString stringWithFormat:@"SYNC upload one %@ via syncSelector", model]];
            
            SEL syncSelector = NSSelectorFromString([current objectForKey:@"syncSelector"]);
            if ([self.delegate respondsToSelector:syncSelector]) {
                [self.delegate performSelector:syncSelector withObject:record];
            }
        } else {
            if (record.syncedAt) {
                [[Analytics sharedClient] debugLog:[NSString stringWithFormat:@"SYNC upload one %@ via PUT", model]];

                [[RKObjectManager sharedManager] putObject:record mapResponseWith:[model mapping] delegate:self];
            } else {
                [[Analytics sharedClient] debugLog:[NSString stringWithFormat:@"SYNC upload one %@ via POST", model]];

                [[RKObjectManager sharedManager] postObject:record mapResponseWith:[model mapping] delegate:self];
            }
        }
    }
}

- (void)startDelete
{
    NSMutableDictionary *current = self.queue.firstObject;
    if (!current) {
        [self stop];
        return;
    }
    id model = [current objectForKey:@"model"];
    
    [[Analytics sharedClient] debugLog:[NSString stringWithFormat:@"SYNC start deleting %@", model]];

    NSArray *deletedRecords = [DeletedRecord objectsWithPredicate:
                               [NSPredicate predicateWithFormat:
                                @"modelName = %@", NSStringFromClass(model)]];
    for (DeletedRecord *dr in deletedRecords) {
        [[Analytics sharedClient] debugLog:[NSString stringWithFormat:@"SYNC deleting one %@", model]];

        [[RKClient sharedClient] delete:[NSString stringWithFormat:@"/%@/%d",
                                         dr.modelName.underscore.pluralize, 
                                         dr.recordID.intValue] 
                               delegate:self];
    }

}

- (void)stop
{
    [[Analytics sharedClient] debugLog:@"SYNC stopped"];

    self.started = NO;
    
    // remove all the models from the app
    [self.queue removeAllObjects];
    
    [[[[RKObjectManager sharedManager] client] requestQueue] cancelAllRequests];
    // sleep is ok now
    [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
}

- (void)finish
{
    [[Analytics sharedClient] debugLog:@"SYNC finished"];

    [self stop];
    if ([self.delegate respondsToSelector:@selector(uploadSessionFinished)])
        [self.delegate uploadSessionFinished];

    NSNotification *syncNotification = [NSNotification notificationWithName:INatUserSavedObservationNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotification:syncNotification];
}

- (BOOL)isRunning
{
    return (self.started == YES);
}

#pragma mark RKObjectLoaderDelegate methods
- (void)objectLoader:(RKObjectLoader*)objectLoader didLoadObjects:(NSArray*)objects {
    if (objects.count == 0) return;
    
    NSMutableDictionary *current = self.queue.firstObject;
    if (!current) {
        [self stop];
        return;
    }
    
    [[Analytics sharedClient] debugLog:[NSString stringWithFormat:@"SYNC completed upload of %@", current[@"model"]]];
    
    NSNumber *needingSyncCount = [current objectForKey:@"needingSyncCount"];
    NSNumber *syncedCount = [current objectForKey:@"syncedCount"];
    
    NSDate *now = [NSDate date];
    INatModel *o;
    for (int i = 0; i < objects.count; i++) {
        o = [objects objectAtIndex:i];
        [o setSyncedAt:now];
        
        if ([self.delegate respondsToSelector:@selector(uploadSuccessFor:number:total:)]) {
            NSInteger number = [syncedCount intValue] + 1;
            current[@"syncedCount"] = @(number);
            NSInteger total = [needingSyncCount intValue];
            [self.delegate uploadSuccessFor:o
                                     number:number
                                      total:total];
        }
    }
    
    NSError *error = nil;
    [[[RKObjectManager sharedManager] objectStore] save:&error];
    
    if ([[current objectForKey:@"syncedCount"] intValue] >= needingSyncCount.intValue) {
        [self start];
    }
}

- (void)objectLoader:(RKObjectLoader *)objectLoader didFailWithError:(NSError *)error {
    
    [[Analytics sharedClient] debugLog:[NSString stringWithFormat:@"SYNC failed upload with %@", error.localizedDescription]];
    
    // was running into a bug in release build config where the object loader was 
    // getting deallocated after handling an error.  This is a kludge.
    self.loader = objectLoader;
    bool jsonParsingError = [error.domain isEqualToString:@"JKErrorDomain"] && error.code == -1;
    bool authFailure = [error.domain isEqualToString:@"NSURLErrorDomain"] && error.code == -1012;
    bool recordDeletedFromServer = (objectLoader.response.statusCode == 404 || objectLoader.response.statusCode == 410) &&
        objectLoader.method == RKRequestMethodPUT &&
        [objectLoader.sourceObject respondsToSelector:@selector(recordID)] &&
        [objectLoader.sourceObject performSelector:@selector(recordID)] != nil;

    if (jsonParsingError || authFailure) {
        [self stop];
        if ([self.delegate respondsToSelector:@selector(uploadSessionAuthRequired)]) {
            [self.delegate uploadSessionAuthRequired];
        }
    } else if (recordDeletedFromServer) {
        // if it was in the sync queue there were local changes, so post it again
        INatModel *record = (INatModel *)objectLoader.sourceObject;
        [record setSyncedAt:nil];
        [record setRecordID:nil];
        [record save];
    } else if ([self.delegate respondsToSelector:@selector(uploadFailedFor:error:)]) {
        [self.delegate uploadFailedFor:nil error:error];
    } else {
        [self stop];
    }
    
    // even if it was an error the object was still handled, so update the 
    // counter and move the queue forward if necessary
    [self next];
}

- (void)next
{
    NSMutableDictionary *current = self.queue.firstObject;
    if (!current) {
        [self stop];
        return;
    }
    
    NSNumber *needingSyncCount = [current objectForKey:@"needingSyncCount"];
    NSNumber *syncedCount = [current objectForKey:@"syncedCount"];
    [current setValue:[NSNumber numberWithInt:[syncedCount intValue] + 1]
               forKey:@"syncedCount"];
    if (self.isRunning && [[current objectForKey:@"syncedCount"] intValue] >= needingSyncCount.intValue) {
        [self start];
    }
}

- (void)objectLoaderDidLoadUnexpectedResponse:(RKObjectLoader *)objectLoader
{
    self.loader = objectLoader;
    [self stop];
    if ([self.delegate respondsToSelector:@selector(uploadFailedFor:error:)]) {
        [self.delegate uploadFailedFor:nil error:nil];
    }
}

- (void)request:(RKRequest *)request didFailLoadWithError:(NSError *)error
{
    if (request.method != RKRequestMethodDELETE) return;
    
    [[Analytics sharedClient] debugLog:[NSString stringWithFormat:@"SYNC failed delete with %@", error.localizedDescription]];
    if ([self.delegate respondsToSelector:@selector(uploadFailedFor:error:)]) {
        [self.delegate uploadFailedFor:nil error:error];
    }
    
    [self stop];
}

- (void)request:(RKRequest *)request didLoadResponse:(RKResponse *)response
{
    if (request.method != RKRequestMethodDELETE) return;
    if (!self.started) return;
    
    NSMutableDictionary *current = self.queue.firstObject;
    if (!current) {
        [self stop];
        return;
    }

    id model = [current objectForKey:@"model"];
    
    [[Analytics sharedClient] debugLog:[NSString stringWithFormat:@"SYNC deleted one %@", model]];
    
    NSNumber *deletedRecordCount = [current objectForKey:@"deletedRecordCount"];
    [current setValue:[NSNumber numberWithInt:[deletedRecordCount intValue] - 1] 
               forKey:@"deletedRecordCount"];
    
    // if we're done deleting
    if ([[current objectForKey:@"deletedRecordCount"] intValue] <= 0) {
        
        [[Analytics sharedClient] debugLog:[NSString stringWithFormat:@"SYNC finished deleting %@", model]];
        
        // remove all deleted records
        NSArray *deletedRecords = [DeletedRecord objectsWithPredicate:
                                   [NSPredicate predicateWithFormat:
                                    @"modelName = %@", NSStringFromClass(model)]];
        for (DeletedRecord *dr in deletedRecords) {
            [dr deleteEntity];
        }
        NSError *error = nil;
        [[NSManagedObjectContext defaultContext] save:&error];
        
        // move the queue forward
        [self start];
    }
}

@end
