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
#import "ObservationPhoto.h"
#import "ObservationFieldValue.h"
#import "ProjectObservation.h"
#import "INaturalistAppDelegate.h"

@interface NSArray (FP)
- (id)head;
- (instancetype)tail;
@end

@implementation NSArray (FP)
- (id)head {
    return self.firstObject;
}
- (instancetype)tail {
    if (self.count == 0) { return [[self.class alloc] init]; }
    if (self.count == 1) { return [[self.class alloc] init]; }
    
    NSRange tailRange;
    tailRange.location = 1;
    tailRange.length = [self count] - 1;
    return [self subarrayWithRange:tailRange];
}
@end

@interface UploadManager () {
    BOOL _cancelled;
}
@property (nonatomic, strong) NSMutableArray *queue;
@property (nonatomic, weak) id <UploadManagerNotificationDelegate> delegate;
@property (nonatomic, assign) BOOL started;
@property NSMutableArray *objectLoaders;
@end

@implementation UploadManager

- (id)initWithDelegate:(id)delegate
{
    self = [super init];
    if (self) {
        self.delegate = delegate;
        self.queue = [[NSMutableArray alloc] init];
        
        // workaround a restkit bug where the object loader isn't retained in the
        // event that a request fails by stashing all objectloaders
        self.objectLoaders = [NSMutableArray array];
    }
    return self;
}

- (void)uploadDeletes:(NSArray *)deletedRecords completion:(void (^)())deletesCompletion {
    if (deletedRecords.count == 0) {
        NSError *saveError = nil;
        [[NSManagedObjectContext defaultContext] save:&saveError];
        if (saveError) {
            [self.delegate deleteFailedFor:nil error:saveError];
        } else {
            [self.delegate deleteSessionFinished];
            deletesCompletion();
        }
    } else {
        if (self.cancelled) {
            deletesCompletion();
            return;
        }
        
        DeletedRecord *head = [deletedRecords head];
        [self.delegate deleteStartedFor:head];

        NSString *deletePath = [NSString stringWithFormat:@"/%@/%d", head.modelName.underscore.pluralize, head.recordID.intValue];
        [[RKClient sharedClient] delete:deletePath
                             usingBlock:^(RKRequest *request) {
                                 request.onDidFailLoadWithError = ^(NSError *error) {
                                     [self.delegate deleteFailedFor:head error:error];
                                 };
                                 request.onDidLoadResponse = ^(RKResponse *response) {
                                     [self.delegate deleteSuccessFor:head];
                                     [[Analytics sharedClient] debugLog:[NSString stringWithFormat:@"SYNC deleted %@", head]];
                                     [head deleteEntity];

                                     [self uploadDeletes:[deletedRecords tail]
                                              completion:deletesCompletion];
                                 };
                             }];
    }
}

- (void)uploadObservations:(NSArray *)observations completion:(void (^)())uploadCompletion {
    if (observations.count == 0) {
        self.started = NO;
        [self.delegate uploadSessionFinished];
        if (uploadCompletion) {
            uploadCompletion();
        }
    } else {
        if (self.cancelled) {
            uploadCompletion();
            return;
        }
        
        if (!self.started) {
            self.started = YES;
        }
        
        // upload head
        Observation *head = [observations head];
        NSArray *tail = [observations tail];
        
        __weak typeof(self)weakSelf = self;
        [self uploadRecordsForObservation:head
                               completion:^(NSError *error) {
                                   __strong typeof(weakSelf) strongSelf = weakSelf;
                                   if (error) {
                                       bool jsonParsingError = [error.domain isEqualToString:@"JKErrorDomain"] && error.code == -1;
                                       bool authFailure = [error.domain isEqualToString:@"NSURLErrorDomain"] && error.code == -1012;
                                       
                                       if (jsonParsingError || authFailure) {
                                           [strongSelf.delegate uploadSessionAuthRequired];
                                       } else {
                                           [strongSelf.delegate uploadFailedFor:head error:error];
                                       }
                                   } else {
                                       [weakSelf uploadObservations:tail completion:uploadCompletion];
                                   }
                               }];
    }
}

- (void)uploadRecordsForObservation:(Observation *)observation completion:(void (^)(NSError *error))observationCompletion {
    
    NSArray *childrenNeedingUpload = [observation childrenNeedingUpload];
    
    __weak typeof(self)weakSelf = self;
    void(^eachCompletion)() = ^void() {
        __strong typeof(weakSelf)strongSelf = weakSelf;
        if (!observation.needsUpload) {
            [strongSelf.delegate uploadSuccessFor:observation];
            observationCompletion(nil);
        }
    };
    
    [self.delegate uploadStartedFor:observation];
    
    if (observation.needsSync) {
        __weak typeof(self)weakSelf = self;
        [self uploadRecord:observation
                completion:^ (NSError *error) {
                    if (error) {
                        observationCompletion(error);
                    } else {
                        eachCompletion();
                        for (INatModel *child in childrenNeedingUpload) {
                            [weakSelf uploadRecord:child
                                        completion:eachCompletion];
                        }
                    }
                }];
    } else {
        for (INatModel *child in childrenNeedingUpload) {
            [self uploadRecord:child
                    completion:eachCompletion];
        }
    }
}


- (void)uploadRecord:(INatModel *)record completion:(void (^)(NSError *error))completion {
    
    RKRequestMethod method = record.syncedAt ? RKRequestMethodPUT : RKRequestMethodPOST;
    
    [[Analytics sharedClient] debugLog:[NSString stringWithFormat:@"SYNC upload one %@ via %d", record, (int)method]];
    RKObjectLoader *loader = [[RKObjectManager sharedManager] loaderForObject:record method:method];
    
    // need to setup params for obs photo uploads here
    // this should go into a protocol
    // and needs to trap for an error getting the additional params
    if ([record respondsToSelector:@selector(fileUploadParameter)]) {
        NSString *path = [record performSelector:@selector(fileUploadParameter)];
        
        INaturalistAppDelegate *appDelegate = (INaturalistAppDelegate *)[UIApplication sharedApplication].delegate;
        RKObjectMapping* serializationMapping = [appDelegate.photoObjectManager.mappingProvider
                                                 serializationMappingForClass:[record class]];
        NSError* error = nil;
        RKObjectSerializer *serializer = [RKObjectSerializer serializerWithObject:record
                                                                          mapping:serializationMapping];
        NSDictionary *dictionary = [serializer serializedObject:&error];
        
        // should really call completion with the error
        if (error) {
            [self.delegate uploadFailedFor:record error:error];
            self.started = NO;
            return;
        }
        
        RKParams* params = [RKParams paramsWithDictionary:dictionary];
        
        [params setFile:path
               forParam:@"file"];
        loader.params = params;
    }
    
    loader.objectMapping = [[record class] mapping];
    
    loader.onDidLoadResponse = ^(RKResponse *response) {
        bool recordDeletedFromServer = (response.statusCode == 404 || response.statusCode == 410)
            && method == RKRequestMethodPUT
            && [record respondsToSelector:@selector(recordID)]
            && [record performSelector:@selector(recordID)] != nil;
        
        if (recordDeletedFromServer) {
            // if it was in the sync queue there were local changes, so post it again
            [record setSyncedAt:nil];
            [record setRecordID:nil];
            [record save];
        }
    };

    loader.onDidLoadObject = ^(INatModel *uploadedObject) {
        uploadedObject.syncedAt = [NSDate date];
        NSError *error = nil;
        [[[RKObjectManager sharedManager] objectStore] save:&error];
        if (error) {
            completion(error);
        } else {
            [[Analytics sharedClient] debugLog:[NSString stringWithFormat:@"SYNC completed upload of %@", record]];
            completion(nil);
        }
    };
    
    loader.onDidFailLoadWithError = ^(NSError *error) {
        completion(error);
    };
    
    loader.onDidFailWithError = ^(NSError *error) {
        completion(error);
    };
    
    [self.objectLoaders addObject:loader];
    [loader sendAsynchronously];
}

- (void)dealloc {
    [self.objectLoaders enumerateObjectsUsingBlock:^(RKObjectLoader *loader, NSUInteger idx, BOOL *stop) {
        [[[RKClient sharedClient] requestQueue] cancelRequest:loader];
    }];
}

- (void)setCancelled:(BOOL)cancelled {
    _cancelled = cancelled;
    
    [self.objectLoaders enumerateObjectsUsingBlock:^(RKObjectLoader *loader, NSUInteger idx, BOOL *stop) {
        [[[RKClient sharedClient] requestQueue] cancelRequest:loader];
    }];
}

- (BOOL)cancelled {
    return _cancelled;
}


@end
