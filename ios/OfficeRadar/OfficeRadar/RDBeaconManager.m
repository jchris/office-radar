
#import <Foundation/Foundation.h>
#import "RDBeaconManager.h"
#import "RDConstants.h"
#import "RDBeacon.h"
#import "RDGeofenceEvent.h"
#import "RDUserHelper.h"
#import <CouchbaseLite/CouchbaseLite.h>
#import "RDUserProfile.h"
#import "RDUiHelper.h"

@implementation RDBeaconManager

- (RDBeaconManager *)initWithDatabase:(CBLDatabase *)database
{
    if (self = [super init]) {
        self.database = database;
        self.estimoteBeaconManager = [[ESTBeaconManager alloc] init];
        self.estimoteBeaconManager.delegate = self;
    }
    return self;
}

- (void)observeDatabase {
    
    [[NSNotificationCenter defaultCenter] addObserverForName: kCBLDatabaseChangeNotification
                                                      object: [self database]
                                                       queue: nil
                                                  usingBlock: ^(NSNotification *n) {
                                                      NSArray* changes = n.userInfo[@"changes"];
                                                      for (int i=0; i<changes.count; i++) {
                                                          [self handleDbChange:changes[i]];
                                                      }
                                                  }
     ];
    
}

- (void)createDbViews {
    
    CBLView* view = [[self database] viewNamed: kViewBeacons];
    [view setMapBlock:^(NSDictionary *doc, CBLMapEmitBlock emit) {
        NSString *docType = (NSString *) doc[kDocType];
        if ([docType isEqualToString:kDocTypeBeacon]) {
            NSString *uuid = (NSString *) doc[kFieldUuid];
            NSNumber *major = (NSNumber *) doc[kFieldMajor];
            NSNumber *minor = (NSNumber *) doc[kFieldMinor];
            NSArray *key = [NSArray arrayWithObjects:uuid, major, minor, nil];
            emit(key, doc[@"_id"]);
        }
        
    } version:@"1"];
    
    CBLView* geofenceEventsView = [[self database] viewNamed: kViewGeofenceEvents];
    [geofenceEventsView setMapBlock:^(NSDictionary *doc, CBLMapEmitBlock emit) {
        NSString *docType = (NSString *) doc[kDocType];
        if ([docType isEqualToString:kGeofenceEventDocType]) {
            NSString *createdAtString = doc[kFieldCreatedAt];
            NSDate *createdAt = [CBLJSON dateWithJSONObject:createdAtString];
            NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
            [dateFormat setFormatterBehavior:NSDateFormatterBehavior10_4];
            [dateFormat setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
            NSString *key = [dateFormat stringFromDate:createdAt];
            emit(key, doc[@"_id"]);
        }
    } version:@"7"];
    
    CBLView* lastSeenUsersView = [[self database] viewNamed: kLastSeenUsers];
    [lastSeenUsersView setMapBlock:^(NSDictionary *doc, CBLMapEmitBlock emit) {
        NSString *docType = (NSString *) doc[kDocType];
        if ([docType isEqualToString:kUserProfileDocType]) {
            id latestEventCreatedAt = doc[@"latestEventCreatedAt"];
            if (latestEventCreatedAt != nil) {
                NSArray *compoundKey = @[latestEventCreatedAt, doc[@"name"]];
                emit(compoundKey, doc[@"_id"]);

            }
        }
    } version:@"3"];

    
}


- (void)monitorAllBeacons {
    CBLQuery* query = [[[self database] viewNamed:kViewBeacons] createQuery];
    
    // run query to find document
    CBLDocument *beaconDocument;
    NSError *error;
    CBLQueryEnumerator* result = [query run: &error];
    
    for (CBLQueryRow* row in result) {
        beaconDocument = [[self database] documentWithID:row.value];
        RDBeacon *beacon = [RDBeacon modelForDocument:beaconDocument];
        [self startMonitoringForBeacon:beacon];
    }

}

- (void)startMonitoringForBeacon:(RDBeacon *)beacon {
    
    ESTBeaconRegion *beaconRegion = [beacon regionForBeacon];

    beaconRegion.notifyOnEntry = YES;
    beaconRegion.notifyOnExit = YES;
    
    [self.estimoteBeaconManager startMonitoringForRegion:beaconRegion];
    NSLog(@"Monitoring for beacon region: %@", beaconRegion);

    
}

- (void)handleDbChange:(CBLDatabaseChange *)change {
    
    
    // if it's not type=beacon, ignore it
    CBLDocument *changedDoc = [[self database] documentWithID:[change documentID]];
    NSString *docType = (NSString *)[changedDoc propertyForKey:kDocType];
    
    // if it's not a beacon doc (possibly because it has been deleted and lost its type field)
    // then ignore it
    if (![docType isEqualToString:kDocTypeBeacon]) {
        return;
    }
    NSLog(@"beacon document '%@' changed.", change.documentID);
    
    RDBeacon *beacon = [RDBeacon modelForDocument:changedDoc];
    [self startMonitoringForBeacon:beacon];
    
}

- (void)saveGeofenceForBeacon:(RDBeacon *)beacon action:(NSString *)action {

    NSString *loggedInUserId = [[RDUserHelper sharedInstance] loggedInUserId];
    
    if (loggedInUserId == nil) {
        NSLog(@"No logged in user, not saving geofence event");
        return;
    }
    
    RDUserProfile *profile = [RDUserProfile profileWithUserId:loggedInUserId];
    
    
    
    RDGeofenceEvent *geofenceEvent = [[RDGeofenceEvent alloc] initInDatabase:[self database]
                                                                  withBeacon:beacon
                                                                     profile:profile
                                                                      action:action];
    
    NSError *error;
    BOOL saved = [geofenceEvent save:&error];
    if (!saved) {
        [RDUiHelper showLocalNotificationError:@"OfficeRadar: failed to save geofence event" error:error];
        return;
    }
    
    NSLog(@"Saved geofence event: %@", [geofenceEvent prettyPrint]);
    
    // update profile
    [profile setLatestEvent:geofenceEvent];
    [profile setLatestEventCreatedAt:[geofenceEvent created_at]];
    saved = [profile save:&error];
    if (!saved) {
        [RDUiHelper showLocalNotificationError:@"OfficeRadar: failed to update profile with latest event" error:error];
        return;
    }
        
    // TODO: this should only happen if enabled in settings
    UILocalNotification *notification = [UILocalNotification new];
    notification.alertBody = [geofenceEvent prettyPrint];
    [[UIApplication sharedApplication] presentLocalNotificationNow:notification];
    
}

- (void)saveGeofenceForRegion:(ESTBeaconRegion *)region action:(NSString *)action {
    
    RDBeacon *beacon = [RDBeacon beaconForRegion:region inDatabase:[self database]];
    [self saveGeofenceForBeacon:beacon action:action];
    
}

#pragma mark - ESTBeaconManager delegate

- (void)beaconManager:(ESTBeaconManager *)manager didEnterRegion:(ESTBeaconRegion *)region
{
    [self saveGeofenceForRegion:region action:kActionEntry];
}

- (void)beaconManager:(ESTBeaconManager *)manager didExitRegion:(ESTBeaconRegion *)region
{
    [self saveGeofenceForRegion:region action:kActionExit];
}




@end
