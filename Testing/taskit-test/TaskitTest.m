#import "Taskit.h"
#import "TaskitTest.h"

@implementation TaskitTest

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSLog(@"Performing first test");
    [self test_echo];
    [self test_env];
    NSLog(@"Finished tests");
}
- (void)test_echo {
    Taskit *task = [Taskit task];
    task.launchPath = @"/bin/pwd";
    //[task.arguments addObject:@"Hello World"];
    //task.inputString = @"hello";
    /*task.receivedErrorString = ^void(NSString *output) {
        NSLog(@"[echo]: %@", output);
    };*/
    
    [task launch];
    NSLog(@"[echo:err] '%@'", [task waitForErrorString]);
}
- (void)test_env {
    Taskit *task = [Taskit task];
    task.launchPath = @"/usr/bin/env";
    //[task.arguments addObject:@"Hello World"];
    //task.inputString = @"hello";
    [task.environment setValue:@"BACON" forKey:@"CRISPY"];
    //task.receivedErrorString = ^void(NSString *output) {
    // NSLog(@"[env]: %@", output);
    // };
    
    [task launch];
    NSLog(@"[env:out] '%@'", [task waitForOutputString]);
}

@end
