//  Taskit
//  Written by Alex Gordon on 09/09/2011.
//  Licensed under the WTFPL: http://sam.zoy.org/wtfpl/

#import "Taskit.h"

@interface Taskit ()

@end

@implementation Taskit

@synthesize launchPath;
@synthesize arguments;
@synthesize environment;
@synthesize workingDirectory;

@synthesize input;
@synthesize inputString;
@synthesize inputPath;
//TODO: @synthesize usesAuthorization;

#ifdef TASKIT_BACKGROUNDING
@synthesize receivedOutputData;
@synthesize receivedOutputString;
@synthesize receivedErrorData;
@synthesize receivedErrorString;
#endif
//TODO: @synthesize processExited;

@synthesize timeoutIfNothing;

// The amount of time to wait for stdout if stderr HAS been read
@synthesize timeoutSinceOutput;

// The amount of time to wait for stderr if stdout HAS been read 
@synthesize timeoutSinceError;

@synthesize priority;


+ (id)task {
    return [[[self class] alloc] init];
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
    
    priority = NSIntegerMax;
    
    shouldSetUpFileHandlesAutomatically = YES;
    
    return self;
}

static const char* CHAllocateCopyString(NSString *str) {
    const char* originalString = [str fileSystemRepresentation];
    if (!originalString)
        return NULL;
    
    size_t copysize = (strlen(originalString) + 1) * sizeof(char);
    char* newString = (char*)calloc(copysize, 1);
    if (!newString)
        return NULL;
    
    memcpy(newString, originalString, copysize);
    return newString;
}

- (void)populateWithCurrentEnvironment {
    [environment addEntriesFromDictionary:[[NSProcessInfo processInfo] environment]];
}

- (BOOL)launch {
    
    if (![launchPath length])
        return NO;
    
    self.launchPath = [launchPath stringByStandardizingPath];
    
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:launchPath])
        return NO;
    
    [arguments insertObject:launchPath atIndex:0];
    
    if ([arguments count] + [environment count] + 2 > ARG_MAX)
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
    
    const char **environmentArray = (const char**)calloc([environment count] + 1, sizeof(char*));
    NSInteger envCounter = 0;
    for (NSString *environmentKey in environment) {
        NSString *environmentValue = [environment valueForKey:environmentKey];
        
        if (![environmentKey length] || !environmentValue)
            continue;
        
        NSString *environmentPair = [NSString stringWithFormat:@"%@=%@", environmentKey, environmentValue];
        
        environmentArray[envCounter] = CHAllocateCopyString(environmentPair);
        envCounter++;
    }
    
// Backgrounding
#ifdef TASKIT_BACKGROUNDING
    if (receivedOutputData || receivedOutputString) {
        
        CFRetain(self);
        hasRetainedForOutput = YES;
        
//        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(asyncFileHandleReadCompletion:) name:NSFileHandleReadCompletionNotification object:[outPipe fileHandleForReading]];
//        [[outPipe fileHandleForReading] readInBackgroundAndNotifyForModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, @"taskitwait", nil]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(asyncFileHandleReadCompletion:) name:NSFileHandleReadToEndOfFileCompletionNotification object:[outPipe fileHandleForReading]];
        [[outPipe fileHandleForReading] readToEndOfFileInBackgroundAndNotifyForModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, @"taskitwait", nil]];
    }
    
    if (receivedErrorData || receivedErrorString) {
                
        CFRetain(self);
        hasRetainedForError = YES;
        
//        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(asyncFileHandleReadCompletion:) name:NSFileHandleReadCompletionNotification object:[errPipe fileHandleForReading]];        
//        [[errPipe fileHandleForReading] readInBackgroundAndNotifyForModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, @"taskitwait", nil]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(asyncFileHandleReadCompletion:) name:NSFileHandleReadToEndOfFileCompletionNotification object:[errPipe fileHandleForReading]];        
        [[errPipe fileHandleForReading] readToEndOfFileInBackgroundAndNotifyForModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, @"taskitwait", nil]];
    }
#endif

//    sleep(5);
    NSFileHandle* inHandle = [inPipe fileHandleForReading];
    if ([inputPath length]) {
        inHandle = [NSFileHandle fileHandleForReadingAtPath:inputPath];
    }
    
    int in_parent = [[inPipe fileHandleForWriting] fileDescriptor];
    int in_child = [inHandle fileDescriptor];
    
    int out_parent = [[outPipe fileHandleForReading] fileDescriptor];
    int out_child = [[outPipe fileHandleForWriting] fileDescriptor];
    
    int err_parent = [[errPipe fileHandleForReading] fileDescriptor];
    int err_child = [[errPipe fileHandleForWriting] fileDescriptor];
    
// Execution
//    return NO;
    pid_t p = fork();
    if (p == 0) {
        
//        setsid();
        
        // Set up stdin, stdout and stderr
        
        //sigprocmask
        close(in_parent);
        dup2(in_child, STDIN_FILENO);
        close(in_child);
        
        close(out_parent);
        dup2(out_child, STDOUT_FILENO);
        close(out_child);
        
        close(err_parent);
        dup2(err_child, STDERR_FILENO);
        close(err_child);
        
        chdir(workingDirectoryPath);
        
        //sleep(1);
        
        int oldpriority = getpriority(PRIO_PROCESS, getpid());
        if (priority < 20 && priority > -20 && priority > oldpriority)
            setpriority(PRIO_PROCESS, getpid(), (int)priority);
        
        // Close any open file handles that are NOT stderr
        for (int i = getdtablesize(); i >= 3; i--) {
            close(i);
        }
        
        execve(executablePath, (char * const *)argumentsArray, (char * const *)environmentArray);
  
        // execve failed for some reason, try to quit gracefullyish
        _exit(0);
        
        // Uh oh, we shouldn't be here
        abort();
        return NO;
    }
    else if (p == -1) {
        // Error
        printf("A forking error occurred\n");
        return NO;
    }
    else {
        pid = p;
        
        close(in_child);
        close(out_child);
        close(err_child);
    }
        
    isRunning = YES;
        
// Clean up
    free((void *)executablePath);
    free((void *)workingDirectoryPath);
    
    for (size_t i = 0; i < argCounter; i++) free((void *)argumentsArray[i]);
    free(argumentsArray);
    
    for (size_t i = 0; i < envCounter; i++) free((void *)environmentArray[i]);
    free(environmentArray);
    
// Writing
    // We want to open stdin on p and write our input
    NSData *inputData = input ?: [inputString dataUsingEncoding:NSUTF8StringEncoding];
    if (inputData)
        [[inPipe fileHandleForWriting] writeData:inputData];
    [[inPipe fileHandleForWriting] closeFile];
    inPipe = nil;
    
    return YES;
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
- (NSInteger)processIdentifier {
    return pid;
}
- (NSInteger)terminationStatus {
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
- (NSInteger)terminationSignal {
    if (WIFSIGNALED(waitpid_status))
        return WTERMSIG(waitpid_status);
    
    return 0;
}

- (void)interrupt // Not always possible. Sends SIGINT.
{
    if ([self isRunning])
        kill(pid, SIGINT);
}
- (void)terminate // Not always possible. Sends SIGTERM.
{
    if ([self isRunning]) {
        kill(pid, SIGTERM);
        [self isRunning];
    }
}
- (void)kill
{
    [self terminate];
    
    if ([self isRunning]) {
        kill(pid, SIGKILL);
        [self isRunning];
    }
}
- (BOOL)suspend
{
    if ([self isRunning])
        kill(pid, SIGSTOP);
    return [self isRunning];
}
- (BOOL)resume
{
    if ([self isRunning])
        kill(pid, SIGCONT);
    return [self isRunning];
}


#pragma mark Blocking methods

- (void)reapOnExit {
    if (pid > 0 && [self isRunning]) {
        dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, pid, DISPATCH_PROC_EXIT, dispatch_get_main_queue());
#if !__has_feature(objc_arc)
        CFRetain(self);
#endif
        if (source) {
            dispatch_source_set_event_handler(source, ^{
#if !__has_feature(objc_arc)
                CFRelease(self);
#endif
                [self isRunning];
                dispatch_source_cancel(source);
                dispatch_release(source);
            });
            dispatch_resume(source);
        }
    }
}
- (void)waitUntilExit {
    
    NSRunLoop *runloop = [NSRunLoop currentRunLoop];
    NSTimeInterval delay = 0.01;
    
    while ([self isRunning]) {
        
        [runloop runMode:@"taskitwait" beforeDate:[NSDate dateWithTimeIntervalSinceNow:delay]];
        
        delay *= 1.5;
        if (delay >= 1.0)
            delay = 1.0;
    }
}
- (BOOL)waitUntilExitWithTimeout:(NSTimeInterval)timeout {
    
    NSRunLoop *runloop = [NSRunLoop currentRunLoop];
    NSTimeInterval delay = 0.01;
    
    NSTimeInterval startTime = [NSDate timeIntervalSinceReferenceDate];
    BOOL hitTimeout = NO;
    
    while ([self isRunning]) {
        
        NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];
        
        if (timeout > 0 && currentTime - startTime > timeout) {
            hitTimeout = YES;
            break;
        }
        
        [runloop runMode:@"taskitwait" beforeDate:[NSDate dateWithTimeIntervalSinceNow:delay]];
        
        delay *= 1.5;
        if (delay >= 1.0)
            delay = 1.0;
    }
            
    if (hitTimeout)
        [self kill];
    return hitTimeout;
}

- (NSData *)waitForOutput {
    
    NSData *ret = nil;
    [self waitForOutputData:&ret errorData:NULL];
    
    return ret;
}
- (NSString *)waitForOutputString {
    
    NSString *ret = nil;
    [self waitForOutputString:&ret errorString:NULL];
    
    return ret;
}
// Want to either wait for it to exit, or for it to EOF
- (NSData *)waitForError {
    
    NSData *ret = nil;
    [self waitForOutputData:NULL errorData:&ret];
    
    return ret;
}
- (NSString *)waitForErrorString {
    
    NSString *ret = nil;
    [self waitForOutputString:NULL errorString:&ret];
    
    return ret;
}

#ifdef TASKIT_BACKGROUNDING
- (void)asyncFileHandleReadCompletion:(NSNotification *)notif {
    
    NSData *data = [[notif userInfo] valueForKey:NSFileHandleNotificationDataItem];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:[notif name] object:[notif object]];
    
    if ([[notif object] isEqual:[outPipe fileHandleForReading]]) {
        
        hasFinishedReadingOutput = YES;
        [[outPipe fileHandleForReading] closeFile];
        
        if (receivedOutputData)
            receivedOutputData(data);
        if (receivedOutputString)
            receivedOutputString([[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
        
        if (hasRetainedForOutput) {
            CFRelease(self);
            hasRetainedForOutput = NO;
        }
    }
    else if ([[notif object] isEqual:[errPipe fileHandleForReading]]) {
        
        hasFinishedReadingError = YES;        
        [[errPipe fileHandleForReading] closeFile];
        
        if (receivedErrorData)
            receivedErrorData(data);
        if (receivedErrorString)
            receivedErrorString([[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);	 	
        
        if (hasRetainedForError) {
            CFRelease(self);
            hasRetainedForError = NO;
        }
    }
}
#endif
- (void)syncFileHandleReadCompletion:(NSNotification *)notif {

    NSData *data = [[notif userInfo] valueForKey:NSFileHandleNotificationDataItem];
    
    if ([[notif object] isEqual:[outPipe fileHandleForReading]]) {
        if (!outputBuffer)
            outputBuffer = [data copy];
       
        hasFinishedReadingOutput = YES;
        [[outPipe fileHandleForReading] closeFile];
    }
    else if ([[notif object] isEqual:[errPipe fileHandleForReading]]) {
        if (!errorBuffer)
            errorBuffer = [data copy];
        
        hasFinishedReadingError = YES;        
        [[errPipe fileHandleForReading] closeFile];
    }
}

- (BOOL)waitForOutputData:(NSData **)output errorData:(NSData **)error {
    
    NSMutableData *outdata = [NSMutableData data];
    NSMutableData *errdata = [NSMutableData data];
    
    BOOL hadWhoopsie = [self waitForIntoOutputData:outdata intoErrorData:errdata];
    
    if (output)
        *output = outdata;
    if (error)
        *error = errdata;
    
    return hadWhoopsie;
}
@synthesize shouldSetUpFileHandlesAutomatically;
- (void)setUpFileHandles {
    int outfd = [[outPipe fileHandleForReading] fileDescriptor];
    int errfd = [[errPipe fileHandleForReading] fileDescriptor];
    
    int outflags = fcntl(outfd, F_GETFL, 0);
    fcntl(outfd, F_SETFL, outflags | O_NONBLOCK);
    
    int errflags = fcntl(errfd, F_GETFL, 0);
    fcntl(errfd, F_SETFL, errflags | O_NONBLOCK);
}
- (BOOL)waitForIntoOutputData:(NSMutableData *)outdata intoErrorData:(NSMutableData *)errdata {
    
//    if (receivedOutputData || receivedOutputString || receivedErrorData || receivedErrorString)
//        @throw [[NSException alloc] initWithName:@"TaskitAsyncSyncCombination" reason:@"-waitForOutputData:errorData: called when async output is in use. These two features are mutually exclusive!" userInfo:[NSDictionary dictionary]];
    
//    return YES;
    
    if (![self isRunning]) {
//        CHDebug(@"not running!");
        return YES;
    }
    
    int outfd = [[outPipe fileHandleForReading] fileDescriptor];
    int errfd = [[errPipe fileHandleForReading] fileDescriptor];
    
    if (shouldSetUpFileHandlesAutomatically)
        [self setUpFileHandles];
    
#define TASKIT_BUFLEN 200
    
    char outbuf[TASKIT_BUFLEN];
    char errbuf[TASKIT_BUFLEN];
    
    BOOL hasFinishedOutput = NO;    
    BOOL hasFinishedError = NO;
    
    BOOL outputHadAWhoopsie = NO;
    BOOL errorHadAWhoopsie = NO;
    
    while (1) {
        if (!hasFinishedOutput) {
            ssize_t outread = read(outfd, &outbuf, TASKIT_BUFLEN);
            const volatile int outerrno = errno;
            if (outread >= 1) {
                [outdata appendBytes:outbuf length:outread];
            }
            else if (outread == 0) {
                hasFinishedOutput = YES;
            }
            else {
//                CHDebug(@"out errno = %d", outerrno);
                if (outerrno != EAGAIN) {
                    hasFinishedOutput = YES;
                    outputHadAWhoopsie = YES;
                }
            }
        }
        
        if (!hasFinishedError) {
            ssize_t errread = read(errfd, &errbuf, TASKIT_BUFLEN);
            const volatile int errerrno = errno;
            
            if (errread >= 1) {
                [errdata appendBytes:errbuf length:errread];
            }
            else if (errread == 0) {
                hasFinishedError = YES;
            }
            else {
//                CHDebug(@"err errno = %d", errerrno);
                if (errerrno != EAGAIN) {
                    hasFinishedError = YES;
                    errorHadAWhoopsie = YES;
                }
            }
        }
        
        if (hasFinishedOutput && hasFinishedError) {
            break;
        }
    }
    
//    CHDebug(@"output = %ld, error = %ld", (long)output, (long)error);
    
    return !outputHadAWhoopsie && !errorHadAWhoopsie;
}
- (void)waitForOutputString:(NSString **)output errorString:(NSString **)error {
    NSData *outputData = nil;
    NSData *errorData = nil;
    
    [self waitForOutputData:output ? &outputData : NULL errorData:error ? &errorData : NULL];
    
    if (outputData)
        *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
    if (errorData)
        *error = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
}



#pragma mark Goodbye!
- (void)end {
    [[outPipe fileHandleForReading] closeFile];
    outPipe = nil;
    [[errPipe fileHandleForReading] closeFile];
    errPipe = nil;
}
- (void)dealloc {
    
    //NSLog(@"Deallocing %@", launchPath);
        
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
