
#import "RDLoginViewController.h"
#import <CouchbaseLite/CouchbaseLite.h>
#import "RDConstants.h"
#import "RDDatabaseHelper.h"
#import "RDUserHelper.h"

@interface RDLoginViewController ()

@end

@implementation RDLoginViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.radarButton = [[UIBarButtonItem alloc] initWithTitle:@"Radar"
                                                        style:UIBarButtonItemStylePlain
                                                       target:self
                                                       action:@selector(showRadarScreen)];
    
    [self.radarButton setEnabled:NO];
    self.navigationItem.rightBarButtonItem = self.radarButton;
    
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

// This method will be called when the user information has been fetched
- (void)loginViewFetchedUserInfo:(FBLoginView *)loginView
                            user:(id<FBGraphUser>)user {
    
    [[RDUserHelper sharedInstance] facebookUserLoggedIn:user];

}


// Logged-in user experience
- (void)loginViewShowingLoggedInUser:(FBLoginView *)loginView {
    
    [self.radarButton setEnabled:YES];

    [[self activityIndicator] startAnimating];
    
    [self performSelector:@selector(showRadarScreen) withObject:nil afterDelay:1];
    

}

- (void)showRadarScreen {
    [[self activityIndicator] stopAnimating];
    
    [self performSegueWithIdentifier:@"radarScreen" sender:self];

}

// Logged-out user experience
- (void)loginViewShowingLoggedOutUser:(FBLoginView *)loginView {
    
    [self.radarButton setEnabled:NO];

    [[RDUserHelper sharedInstance] facebookUserLoggedOut];

}

// TODO: this method is duplicated, refactoring needed
- (void)showAlertIfError:(NSError *)error withMessage:(NSString *)message {
    if (error != nil) {
        [[[UIAlertView alloc] initWithTitle:@"Error"
                                    message:message
                                   delegate:nil
                          cancelButtonTitle:@"OK"
                          otherButtonTitles:nil] show];
    }
    
}

// Handle possible errors that can occur during login
- (void)loginView:(FBLoginView *)loginView handleError:(NSError *)error {
    
    NSLog(@"FBLoginViewHandleError");

    NSString *alertMessage, *alertTitle;
    
    // If the user should perform an action outside of you app to recover,
    // the SDK will provide a message for the user, you just need to surface it.
    // This conveniently handles cases like Facebook password change or unverified Facebook accounts.
    if ([FBErrorUtility shouldNotifyUserForError:error]) {
        alertTitle = @"Facebook error";
        alertMessage = [FBErrorUtility userMessageForError:error];
        
        // This code will handle session closures that happen outside of the app
        // You can take a look at our error handling guide to know more about it
        // https://developers.facebook.com/docs/ios/errors
    } else if ([FBErrorUtility errorCategoryForError:error] == FBErrorCategoryAuthenticationReopenSession) {
        alertTitle = @"Session Error";
        alertMessage = @"Your current session is no longer valid. Please log in again.";
        
        // If the user has cancelled a login, we will do nothing.
        // You can also choose to show the user a message if cancelling login will result in
        // the user not being able to complete a task they had initiated in your app
        // (like accessing FB-stored information or posting to Facebook)
    } else if ([FBErrorUtility errorCategoryForError:error] == FBErrorCategoryUserCancelled) {
        NSLog(@"user cancelled login");
        
        // For simplicity, this sample handles other errors with a generic message
        // You can checkout our error handling guide for more detailed information
        // https://developers.facebook.com/docs/ios/errors
    } else {
        alertTitle  = @"Something went wrong";
        alertMessage = @"Please try again later.";
        NSLog(@"Unexpected error:%@", error);
    }
    
    if (alertMessage) {
        [[[UIAlertView alloc] initWithTitle:alertTitle
                                    message:alertMessage
                                   delegate:nil
                          cancelButtonTitle:@"OK"
                          otherButtonTitles:nil] show];
    }
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
