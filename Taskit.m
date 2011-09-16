//  Taskit
//  Written by Alex Gordon on 09/09/2011.
//  Licensed under the WTFPL: http://sam.zoy.org/wtfpl/

#import "Taskit.h"

@implementation Taskit

@synthesize launchPath;
@synthesize arguments;
@synthesize environment;
@synthesize workingDirectory;

@synthesize input;
@synthesize inputString;
//TODO: @synthesize usesAuthorization;

@synthesize receivedOutputData;
@synthesize receivedOutputString;
@synthesize receivedErrorData;
@synthesize receivedErrorString;
//TODO: @synthesize processExited;

+ (id)task {
    return [[[[self class] alloc] init] autorelease];
}

- (id)init {
    self = [super init];
    if (!self)
        return nil;
    
    arguments = [[NSMutableArray alloc] init];
    environment = [[NSMutableDictionary alloc] init];
    
    self.workingDirectory = [[NSFileManager defaultManager] currentDirectoryPath];
    
    inPipe = [[NSPipe alloc] init];
    outPipe = [[NSPipe alloc] init];
    errPipe = [[NSPipe alloc] init];
    
    return self;
}

static const char* CHAllocateCopyString(NSString *str) {
    const char* __strong originalString = [str fileSystemRepresentation];
    if (!originalString)
        return NULL;
    
    size_t copysize = ([str length] + 1) * sizeof(char);
    char* newString = (const char*)calloc(copysize, 1);
    if (!newString)
        return NULL;
    
    memcpy(newString, originalString, copysize);
    return newString;
}

- (void)populateWithCurrentEnvironment {
    [environment setDictionary:[[NSProcessInfo processInfo] environment]];
}

- (BOOL)launch {
    
    if (![launchPath length])
        return NO;
    
// Set up
    // Set up launch path, arguments, environment and working directory
    const char* executablePath = CHAllocateCopyString(launchPath);
    if (!executablePath)
        return NO;
    
    const char* workingDirectoryPath = CHAllocateCopyString(workingDirectory);
    if (!workingDirectoryPath)
        return NO;
    
    const char** argumentsArray = (const char**)calloc([arguments count] + 1, sizeof(char*));
    NSInteger argCounter = 0;
    for (NSString *argument in arguments) {
        argumentsArray[argCounter] = CHAllocateCopyString(argument);
        if (argumentsArray[argCounter])
            argCounter++;
    }
    
    const char **environmentArray = (const char**)calloc(([environment count] * 2) + 1, sizeof(char*));
    NSInteger envCounter = 0;
    for (NSString *environmentKey in environment) {
        NSString *environmentValue = [environment valueForKey:environmentKey];
        if (![environmentKey length] || !environmentValue)
            continue;
        
        environmentArray[envCounter] = CHAllocateCopyString(environmentKey);
        environmentArray[envCounter + 1] = CHAllocateCopyString(environmentValue);
        envCounter += 2;
    }
    
    int new_in = [[inPipe fileHandleForReading] fileDescriptor];
    int new_out = [[outPipe fileHandleForWriting] fileDescriptor];
    int new_err = [[errPipe fileHandleForWriting] fileDescriptor];

// Execution
    pid_t p = fork();
    if (p == 0) {
        
        // Set up stdin, stdout and stderr
        dup2(new_in, STDIN_FILENO);
        dup2(new_out, STDOUT_FILENO);
        dup2(new_err, STDERR_FILENO);
        
        chdir(workingDirectoryPath);
        
        execve(executablePath, (char * const *)argumentsArray, (char * const *)environmentArray);
        
        // Uh oh, we shouldn't be here
        abort();
        return NO;
    }
    else if (p == -1) {
        // Error
        return NO;
    }
    else {
        pid = p;
    }
    
    isRunning = YES;
    
// Clean up
    free((void *)executablePath);
    free((void *)workingDirectoryPath);
    
    for (size_t i = 0; i < argCounter; i++) free((void *)argumentsArray[i]);
    free(argumentsArray);
    
    for (size_t i = 0; i < envCounter; i++) free((void *)environmentArray[i]);
    free(environmentArray);
    

// Backgrounding
    // We want to open stdin on p and write our input
    NSData *inputData = input ?: [inputString dataUsingEncoding:NSUTF8StringEncoding];
    if (inputData)
        [[inPipe fileHandleForWriting] writeData:inputData];
    [[inPipe fileHandleForWriting] closeFile];
    
    if (receivedOutputData || receivedOutputString) {
        
        // *retain* ourself, since the notification center won't
        CFRetain(self);
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fileHandleDidReadToEndofFile:) name:NSFileHandleReadToEndOfFileCompletionNotification object:[outPipe fileHandleForReading]];
        
        [[outPipe fileHandleForReading] readToEndOfFileInBackgroundAndNotify];
    }
    
    if (receivedErrorData || receivedErrorString) {
        
        CFRetain(self);
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fileHandleDidReadToEndofFile:) name:NSFileHandleReadToEndOfFileCompletionNotification object:[errPipe fileHandleForReading]];
        
        [[errPipe fileHandleForReading] readToEndOfFileInBackgroundAndNotify];
    }
        
    return YES;
}
- (void)fileHandleDidReadToEndOfFile:(NSNotification *)notif {
    
    NSData *data = [[notif userInfo] valueForKey:NSFileHandleNotificationDataItem];

    if ([[notif object] isEqual:[outPipe fileHandleForReading]]) {
        
        if (receivedOutputData)
            receivedOutputData(data);
        if (receivedOutputString)
            receivedOutputString([[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
    }
    else if ([[notif object] isEqual:[errPipe fileHandleForReading]]) {
        
        if (receivedErrorData)
            receivedErrorData(data);
        if (receivedErrorString)
            receivedErrorString([[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
    }
    
    CFRelease(self);
}


- (BOOL)isRunning {
    
    if (!isRunning)
        return NO;
    
    waitpid_status = 0;
    pid_t wp = waitpid(pid, &waitpid_status, WNOHANG);
    if (!wp)
        return YES;
    
    // if wp == -1, fail safely: act as though the process exited normally
    if (wp == -1)
        waitpid_status = 0;
    
    isRunning = NO;
    return isRunning;
}
- (int)processIdentifier {
    return pid;
}
- (int)terminationStatus {
    if (WIFEXITED(waitpid_status))
        return WEXITSTATUS(waitpid_status);
    
    return 1; // lie
}
- (NSTaskTerminationReason)terminationReason {    
    if (WIFEXITED(waitpid_status))
        return NSTaskTerminationReasonExit;
    
    if (WIFSIGNALED(waitpid_status))
        return NSTaskTerminationReasonUncaughtSignal;
    
    return 0;
}
- (int)terminationSignal {
    if (WIFSIGNALED(waitpid_status))
        return WTERMSIG(waitpid_status);
    
    return 0;
}



#pragma mark Blocking methods

- (void)waitUntilExit {
    
    NSRunLoop *runloop = [NSRunLoop currentRunLoop];
    NSTimeInterval delay = 0.01;
    
    while ([self isRunning]) {
        
        [runloop runMode:@"taskit" beforeDate:[NSDate dateWithTimeIntervalSinceNow:delay]];
        
        delay *= 2;
        if (delay >= 1.0)
            delay = 1.0;
    }
}

- (NSData *)waitForOutput {
    
    NSData *data = [[outPipe fileHandleForReading] readDataToEndOfFile];
    [[outPipe fileHandleForReading] closeFile];
    
    return data;
}
- (NSString *)waitForOutputString {
    
    NSData *data = [self waitForOutput];
    if (!data)
        return nil;
    return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
}
- (NSData *)waitForError {
    
    NSData *data = [[errPipe fileHandleForReading] readDataToEndOfFile];
    [[errPipe fileHandleForReading] closeFile];
    
    return data;
}
- (NSString *)waitForErrorString {
    
    NSData *data = [self waitForError];
    if (!data)
        return nil;
    return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
}



#pragma mark Goodbye!

- (void)dealloc {
    
    [launchPath release];
    [arguments release];
    [environment release];
    [workingDirectory release];
    
    [input release];
    [inputString release];
        
    [inPipe release];
    [outPipe release];
    [errPipe release];
    
    [receivedOutputData release];
    [receivedOutputString release];
    
    [receivedErrorData release];
    [receivedErrorString release];
    
    [super dealloc];
}

@end
