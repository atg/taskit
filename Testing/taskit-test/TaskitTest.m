#import "Taskit.h"
#import "TaskitTest.h"

@implementation TaskitTest

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSLog(@"Performing first test");
    [self test_echo];
    NSLog(@"Finished tests");
}
- (void)test_echo {
    Taskit *task = [Taskit task];
    task.launchPath = @"/bin/echo";
    [task.arguments addObject:@"Hello World"];
    task.receivedOutputString = ^void(NSString *output) {
        NSLog(@"[echo]: %@", output);
    };
    
    [task launch];
}

@end
