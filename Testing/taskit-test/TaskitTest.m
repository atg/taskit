#import "Taskit.h"
#import "TaskitTest.h"

@implementation TaskitTest

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSLog(@"Performing first test");
    [self test_echo];
    [self test_env];
    //[self test_env2];
    [self test_cat];
//    [self test_python];
    NSLog(@"Finished tests");
}
- (void)test_echo {
    NSLog(@"[[echo]]");
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

- (void)test_cat {
    NSLog(@"[[cat]]");
    Taskit *task = [Taskit task];
    task.launchPath = @"/bin/cat";
    //[task.arguments addObject:@"Hello World"];
    task.inputString = @"testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat ";
    /*task.receivedErrorString = ^void(NSString *output) {
     NSLog(@"[echo]: %@", output);
     };*/
    
    [task launch];
    NSLog(@"[cat:out] '%@'", [task waitForOutputString]);
}
#if 0
- (void)test_python {
    NSLog(@"[[python]]");
    
    Taskit *task = [Taskit task];
    task.launchPath = @"/usr/bin/python2.7";
    [task.arguments addObject:@"-c"];
    [task.arguments addObject:@"print('testing cat')"];
//    task.inputString = @"print('testing cat')";
    /*task.receivedErrorString = ^void(NSString *output) {
     NSLog(@"[echo]: %@", output);
     };*/
    
    [task launch];
    NSLog(@"[python:out] '%@'", [task waitForErrorString]);
}
#endif
- (void)test_env {
    NSLog(@"[[env]]");
    Taskit *task = [Taskit task];
    task.launchPath = @"/usr/bin/env";
    [task.environment setValue:@"BACON" forKey:@"CRISPY"];    
    [task launch];
    NSLog(@"[env:out] '%@'", [task waitForOutputString]);
}
- (void)test_env2 {
    NSLog(@"[[env2]]");
    Taskit *task = [Taskit task];
    task.launchPath = @"/usr/bin/env";
    [task populateWithCurrentEnvironment];
    [task.environment setValue:@"BACON" forKey:@"CRISPY"];
    task.receivedErrorString = ^void(NSString *output) {
        NSLog(@"[env:async:out] '%@'", output);
    };
    
    [task launch];
    [task waitUntilExit];
}

@end
