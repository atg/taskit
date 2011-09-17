#import "Taskit.h"
#import "TaskitTest.h"

@implementation TaskitTest

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSLog(@"Performing first test");
    [self test_echo];
    [self test_echo2];
    
    [self test_env];
    [self test_env2];
    
    [self test_cat];
    [self test_cat2];
    
    [self test_pwd];
    [self test_pwd2];
    
//    [self test_python];
    NSLog(@"Finished tests");
}
- (void)test_echo {
    
    NSLog(@"[[echo]]");
    Taskit *task = [Taskit task];
    task.launchPath = @"/bin/echo";
    [task.arguments addObject:@"Hello World"];
    
    [task launch];
    NSLog(@"[echo:output] '%@'", [task waitForOutputString]);
}
- (void)test_echo2 {
    
    NSLog(@"[[echo nonblock]]");
    Taskit *task = [Taskit task];
    task.launchPath = @"/bin/echo";
    [task.arguments addObject:@"Hello World"];
    
    task.receivedOutputString = ^void(NSString *output) {
        NSLog(@"[echo nonblock:output] '%@'", output);
    };
    
    [task launch];
}

- (void)test_pwd {
    
    NSLog(@"[[pwd]]");
    Taskit *task = [Taskit task];
    task.launchPath = @"/bin/pwd";
    task.workingDirectory = @"/Library/";
    
    [task launch];
    NSLog(@"[pwd:output] '%@'", [task waitForOutputString]);
}
- (void)test_pwd2 {
    
    NSLog(@"[[pwd nonblock]]");
    Taskit *task = [Taskit task];
    task.launchPath = @"/bin/pwd";
    task.workingDirectory = @"/Library/";
    
    task.receivedOutputString = ^void(NSString *output) {
        NSLog(@"[pwd nonblock:output] '%@'", output);
    };
    
    [task launch];
}

- (void)test_env {
    
    NSLog(@"[[env]]");
    Taskit *task = [Taskit task];
    task.launchPath = @"/usr/bin/env";
    
    [task.environment setValue:@"BACON" forKey:@"CRISPY"];
    
    [task launch];
    NSLog(@"[env:output] '%@'", [task waitForOutputString]);
}
- (void)test_env2 {
    
    NSLog(@"[[env nonblock]]");
    Taskit *task = [Taskit task];
    task.launchPath = @"/usr/bin/env";
    
    [task populateWithCurrentEnvironment];
    [task.environment setValue:@"BACON" forKey:@"CRISPY"];
    
    task.receivedOutputString = ^void(NSString *output) {
        NSLog(@"[env nonblock:output] '%@'", output);
    };
    
    [task launch];
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
- (void)test_cat2 {
    NSLog(@"[[cat nonblock]]");
    Taskit *task = [Taskit task];
    task.launchPath = @"/bin/cat";
    task.inputString = @"testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat testing cat ";
    
    task.receivedOutputString = ^void(NSString *output) {
        NSLog(@"[cat nonblock]: %@", output);
    };
    
    [task launch];
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

@end
