
#import "RDAppDelegate.h"
#import "RDBeaconManager.h"
#import "RDConstants.h"
#import <FacebookSDK/FacebookSDK.h>
#import "RDDatabaseHelper.h"
#import "RDUserHelper.h"
#import "CBLEdgeReduce.h"


@implementation RDAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Override point for customization after application launch.
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        UISplitViewController *splitViewController = (UISplitViewController *)self.window.rootViewController;
        UINavigationController *navigationController = [splitViewController.viewControllers lastObject];
        splitViewController.delegate = (id)navigationController.topViewController;
    }
    [self initCouchbaseLiteDatabase];
    [self initOfficeRadarBeaconManager];
    [self initCouchbaseEdgeReduce];
    [self initCouchbaseLiteReplications];
    [self registerForPushNotifications];
    
    return YES;
}

- (void)application:(UIApplication *)app didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    
    NSString *str = [NSString stringWithFormat:@"%@",deviceToken];
    NSLog(@"didRegisterForRemoteNotificationsWithDeviceToken, Device token: %@", str);
    
    NSString* deviceTokenCleaned = [[[[deviceToken description]
                                        stringByReplacingOccurrencesOfString: @"<" withString: @""]
                                        stringByReplacingOccurrencesOfString: @">" withString: @""]
                                        stringByReplacingOccurrencesOfString: @" " withString: @""];
    
    [[RDUserHelper sharedInstance] saveDeviceTokenLocalDoc:deviceTokenCleaned];
    [[RDUserHelper sharedInstance] updateProfileWithDeviceToken:deviceTokenCleaned];
    
    
}

- (void)application:(UIApplication *)app didFailToRegisterForRemoteNotificationsWithError:(NSError *)err
{
    NSString *str = [NSString stringWithFormat: @"Error: %@", err];
    NSLog(@"%@", str);
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification
{
    UIApplicationState state = [application applicationState];
    if (state == UIApplicationStateActive) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"OfficeRadar"
                                                        message:notification.alertBody
                                                       delegate:self cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
    }
    
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo
{
    
    NSString *msg = [[[userInfo objectForKey:@"aps"] objectForKey:@"alert"] objectForKey:@"body"];
    if (msg == nil) {
        msg = @"Error";
    }
    UIApplicationState state = [application applicationState];
    if (state == UIApplicationStateActive) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"OfficeRadar"
                                                        message:msg
                                                       delegate:self cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
    }

}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}



// Needed for facebook login 
- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation {
    
    // Call FBAppCall's handleOpenURL:sourceApplication to handle Facebook app responses
    BOOL wasHandled = [FBAppCall handleOpenURL:url sourceApplication:sourceApplication];
    
    // You can add your app-specific url handling code here if needed
    
    return wasHandled;
}

- (void)initCouchbaseLiteDatabase {

    [CBLManager enableLogging: @"Sync"];
    [CBLManager enableLogging: @"ChangeTracker"];
    
    self.manager = [CBLManager sharedInstance];
    self.database = [RDDatabaseHelper database];
    self.intoTarget = [RDDatabaseHelper intoTarget];
    
}

- (void)initCouchbaseEdgeReduce {
    self.edge = [[CBLEdgeReduce alloc] init];
    CBLQuery* query = [self actionCountByHours];
    query.groupLevel = 1;
    self.edge.query = query;
    self.edge.target = self.intoTarget;
    self.edge.prefix = @"radar"; // 90% of the time this will be user id or device id
    [self.edge start];
    CBLReplication * pushReduce = [self.edge.target createPushReplication:[NSURL URLWithString:kSyncURL]];
    [pushReduce setContinuous:YES];
    [pushReduce start];
}


- (CBLQuery *) actionCountByHours {
    CBLView* view = [self.database viewNamed: @"hours"];
    NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
    [dateFormat setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
    NSCalendar *calendar = [NSCalendar currentCalendar];

    if (!view.mapBlock) {
        // Register the map function, the first time we access the view:
        [view setMapBlock: MAPBLOCK({
            if ([doc[@"type"] isEqualToString:@"geofence_event"]) {
                NSString* dateString = doc[@"created_at"];
                NSDate *date = [dateFormat dateFromString:dateString];
                if (date != nil) {
                    NSDateComponents *components = [calendar components:(NSHourCalendarUnit) fromDate:date];
                    emit([NSNumber numberWithInteger:[components hour]], doc[@"action"]);
                }
            }
        }) reduceBlock:^id(NSArray *keys, NSArray *values, BOOL rereduce) {
            if (rereduce) {
                return [CBLView totalValues: values];  // re-reduce mode adds up counts
            } else {
                return @(values.count);
            }
        } version: @"8"]; // bump version any time you change the view!
    }
    return [view createQuery];
}

- (void)initOfficeRadarBeaconManager {
    
    self.beaconManager = [[RDBeaconManager alloc] initWithDatabase:[self database]];
    [[self beaconManager] observeDatabase];
    [[self beaconManager] createDbViews];
    [[self beaconManager] monitorAllBeacons];
    

}

- (void)initCouchbaseLiteReplications {
    NSURL *syncUrl = [NSURL URLWithString:kSyncURL];
    CBLReplication *pullReplication = [[self database] createPullReplication:syncUrl];
    CBLReplication *pushReplication = [[self database] createPushReplication:syncUrl];
    
    // websockets disabled until https://github.com/couchbase/couchbase-lite-ios/issues/480 is fixed
    pullReplication.customProperties = @{@"websocket": @NO};
    
    [pullReplication setContinuous:YES];
    [pushReplication setContinuous:YES];
    
    [pullReplication start];
    [pushReplication start];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(replicationProgress:)
                                                 name:kCBLReplicationChangeNotification
                                               object:pullReplication];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(replicationProgress:)
                                                 name:kCBLReplicationChangeNotification
                                               object:pushReplication];
}

- (void)registerForPushNotifications {
    
    NSLog(@"registerForPushNotifications");

    [[UIApplication sharedApplication]
     registerForRemoteNotificationTypes:
     (UIRemoteNotificationTypeAlert |
      UIRemoteNotificationTypeBadge |
      UIRemoteNotificationTypeSound)];

}


-(void)replicationProgress:(NSNotification *)notification {

    CBLReplication *repl = [notification object];
    [self replicationProgress:repl notification:notification];
    
}


-(void)replicationProgress:(CBLReplication *)repl notification:(NSNotification *)notification {
    bool active = false;
    unsigned completed = 0, total = 0;
    CBLReplicationStatus status = kCBLReplicationStopped;
    NSError *error = nil;
    status = MAX(status, repl.status);
    if (!error)
        error = repl.lastError;
    if (repl.status == kCBLReplicationActive) {
        active = true;
        completed += repl.completedChangesCount;
        total += repl.changesCount;
    }
    
    if (error.code == 401) {
        NSLog(@"401 auth error");
    }
    
    if (repl.pull) {
        NSLog(@"Pull: active=%d; status=%d; %u/%u; %@",
              active, status, completed, total, error.localizedDescription);
    } else {
        NSLog(@"Push: active=%d; status=%d; %u/%u; %@",
              active, status, completed, total, error.localizedDescription);
    }
    
    if (repl.pull && repl.status == kCBLReplicationIdle) {
        NSLog(@"Replication is idle");
        // [self dumpDatabase];
    }
    
}

-(void)dumpDatabase {
    CBLQuery *allDocsQuery = [[self database] createAllDocumentsQuery];
    NSError *error;
    
    NSMutableArray *sequences = [NSMutableArray array];
    CBLQueryEnumerator *enumerator = [allDocsQuery run:&error];
    for (CBLQueryRow *row in enumerator) {
        NSLog(@"Seq: %lld Id: %@", [row sequenceNumber], [row documentID]);
        NSNumber *seqNumber = [NSNumber numberWithUnsignedLongLong:[row sequenceNumber]];
        [sequences addObject:seqNumber];
    }
    
    
    [sequences sortUsingSelector:@selector(compare:)];
    
    long lastSeq = 0;
    for (NSNumber *object in sequences) {
        if ([object longValue] != (lastSeq + 1)) {
            // NSLog(@"Non-contiguous: %ld", [object longValue]);
        }
        lastSeq = [object longValue];
        // NSLog(@"%@", object);
    }
    

}

UInt64 compare(const void *first, const void *second)
{
    return *(const UInt64 *)first - *(const UInt64 *)second;
}




@end
