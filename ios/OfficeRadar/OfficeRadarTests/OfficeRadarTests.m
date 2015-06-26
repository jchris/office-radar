//
//  OfficeRadarTests.m
//  OfficeRadarTests
//
//  Created by Traun Leyden on 6/27/14.
//  Copyright (c) 2014 Couchbase Inc. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <CouchbaseLite/CouchbaseLite.h>
#import "CBLEdgeReduce.h"

@interface OfficeRadarTests : XCTestCase
@end

@implementation OfficeRadarTests{
    CBLDatabase* db;
    CBLEdgeReduce *edge;
}



- (void)setUp
{
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
    
    // make empty db
    NSError *error;
    db = [[CBLManager sharedInstance] databaseNamed:@"test-razor" error:&error];
    
    //    populate with raw data
    NSArray *sources = @[@"a",@"b",@"c",@"d",@"e",@"f",@"g",@"h",@"i",@"j"];
    for (int i = 0; i < 10; i++)
    {
        // two "readings" per source, second is i*i
        CBLDocument *doc = [db documentWithID:[NSString stringWithFormat:@"raw-%d",i]];
        [doc putProperties:@{@"sensed": [NSNumber numberWithInt:i], @"at": sources[i]} error:&error];
        
        CBLDocument *doc2 = [db documentWithID:[NSString stringWithFormat:@"raw2-%d",i]];
        [doc2 putProperties:@{@"sensed": [NSNumber numberWithInt:(i*i)], @"at": sources[i]} error:&error];
    }

    CBLView* view = [db viewNamed: @"test"];
    if (!view.mapBlock) {
        // Register the map function, the first time we access the view:
        [view setMapBlock: MAPBLOCK({
            emit(doc[@"at"], doc[@"sensed"]);
        }) reduceBlock:^id(NSArray *keys, NSArray *values, BOOL rereduce) {
            return [CBLView totalValues: values];  // re-reduce mode adds up counts
        } version: @"9"]; // bump version any time you change the view!
    }
    CBLQuery *q = [view createQuery];
    q.groupLevel = 1;
    // start edge view
    edge = [[CBLEdgeReduce alloc] init];
    edge.query = q;
    edge.target = db;
    edge.viewName = view.name; // this is silly, only b/c no public api from query to view
    edge.sourceID = @"tests";
    [edge start];
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
//    release edge view
    // delete db
    
    [super tearDown];
}

- (void)testSetup
{
    // make sure edge view ran
    XCTAssertNotNil(db, @"Cannot find database instance");
    NSUInteger count = [db documentCount];
    XCTAssertEqualObjects(@20, [NSNumber numberWithUnsignedInteger:count]);
    CBLView* view = [db viewNamed: @"test"];
    XCTAssertNotNil(view, @"Cannot find view instance");
//    XCTFail(@"No implementation for \"%s\"", __PRETTY_FUNCTION__);
}

- (void)testEdgeReduce
{
    // Create an expectation object.
    // This test only has one, but it's possible to wait on multiple expectations.
    XCTestExpectation *edgeReduceExpectation = [self expectationWithDescription:@"edge reduce saved documents"];
    
    
    // this is fillter conetn
    NSURL *URL = [[NSBundle bundleForClass:[self class]]
                  URLForResource:@"TestDocument" withExtension:@"mydoc"];
    UIDocument *doc = [[UIDocument alloc] initWithFileURL:URL];
    [doc openWithCompletionHandler:^(BOOL success) {
        XCTAssert(success);
        // Possibly assert other things here about the document after it has opened...
        
        // Fulfill the expectation-this will cause -waitForExpectation
        // to invoke its completion handler and then return.
        [edgeReduceExpectation fulfill];
    }];
    
    // The test will pause here, running the run loop, until the timeout is hit
    // or all expectations are fulfilled.
    [self waitForExpectationsWithTimeout:1 handler:^(NSError *error) {
        [doc closeWithCompletionHandler:nil];
    }];
}

// test unchanged content results in unchanged rev

// test changing content is reflected in changing document values

// test removing content is reflected in deleted target documents

@end
