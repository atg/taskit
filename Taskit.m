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
//TODO: @synthesize usesAuthorization;

@synthesize receivedOutputData;
@synthesize receivedOutputString;
@synthesize receivedErrorData;
@synthesize receivedErrorString;
//TODO: @synthesize processExited;

@synthesize timeoutIfNothing;

// The amount of time to wait for stdout if stderr HAS been read
@synthesize timeoutSinceOutput;

// The amount of time to wait for stderr if stdout HAS been read 
@synthesize timeoutSinceError;

@synthesize priority;


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
    
    priority = NSIntegerMax;
    
    return self;
}

static const char* CHAllocateCopyString(NSString *str) {
    const char* __strong originalString = [str fileSystemRepresentation];
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
    if (receivedOutputData || receivedOutputString) {
        
        CFRetain(self);
        hasRetainedForOutput = YES;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(asyncFileHandleReadCompletion:) name:NSFileHandleReadCompletionNotification object:[outPipe fileHandleForReading]];
        [[outPipe fileHandleForReading] readInBackgroundAndNotifyForModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, @"taskitwait", nil]];
    }
    
    if (receivedErrorData || receivedErrorString) {
                
        CFRetain(self);
        hasRetainedForError = YES;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(asyncFileHandleReadCompletion:) name:NSFileHandleReadCompletionNotification object:[errPipe fileHandleForReading]];        
        [[errPipe fileHandleForReading] readInBackgroundAndNotifyForModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, @"taskitwait", nil]];
    }
    
    int in_parent = [[inPipe fileHandleForWriting] fileDescriptor];
    int in_child = [[inPipe fileHandleForReading] fileDescriptor];
    
    int out_parent = [[outPipe fileHandleForReading] fileDescriptor];
    int out_child = [[outPipe fileHandleForWriting] fileDescriptor];
    
    int err_parent = [[errPipe fileHandleForReading] fileDescriptor];
    int err_child = [[errPipe fileHandleForWriting] fileDescriptor];
    
// Execution
    pid_t p = fork();
    if (p == 0) {
        
        // Set up stdin, stdout and stderr
        
        setsid();
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
            setpriority(PRIO_PROCESS, getpid(), priority);
        
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
    if ([self isRunning])
        kill(pid, SIGTERM);
}
- (void)kill
{
    [self terminate];
    
    if ([self isRunning]) {
        kill(pid, SIGKILL);
    }
}
- (BOOL)suspend
{
    if ([self isRunning])
        kill(pid, SIGSTOP);
}
- (BOOL)resume
{
    if ([self isRunning])
        kill(pid, SIGCONT);
}


#pragma mark Blocking methods

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

- (void)waitForOutputData:(NSData **)output errorData:(NSData **)error {
    
    if (receivedOutputData || receivedOutputString || receivedErrorData || receivedErrorString)
        @throw [[NSException alloc] initWithName:@"TaskitAsyncSyncCombination" reason:@"-waitForOutputData:errorData: called when async output is in use. These two features are mutually exclusive!" userInfo:[NSDictionary dictionary]];
    
    if (![self isRunning])
        return;
    
    int outfd = [[outPipe fileHandleForReading] fileDescriptor];
    int errfd = [[errPipe fileHandleForReading] fileDescriptor];
    
    int outflags = fcntl(outfd, F_GETFL, 0);
    fcntl(outfd, F_SETFL, outflags | O_NONBLOCK);
    
    int errflags = fcntl(errfd, F_GETFL, 0);
    fcntl(errfd, F_SETFL, errflags | O_NONBLOCK);
    
#define TASKIT_BUFLEN 200
    
    char outbuf[TASKIT_BUFLEN];
    char errbuf[TASKIT_BUFLEN];
    
    NSMutableData *outdata = [NSMutableData data];
    NSMutableData *errdata = [NSMutableData data];
    
    BOOL hasFinishedOutput = NO;
    BOOL hasFinishedError = NO;
    while (1) {
        if (!hasFinishedOutput) {
            int outread = read(outfd, &outbuf, TASKIT_BUFLEN);
            const volatile int outerrno = errno;
            if (outread >= 1) {
                [outdata appendBytes:outbuf length:outread];
            }
            else if (outread == 0 || outerrno != EAGAIN) {
                hasFinishedOutput = YES;
            }
        }
        
        if (!hasFinishedError) {
            int errread = read(errfd, &errbuf, TASKIT_BUFLEN);
            const volatile int errerrno = errno;
            
            if (errread >= 1) {
                [errdata appendBytes:errbuf length:errread];
            }
            else if (errread == 0 || errerrno != EAGAIN) {
                hasFinishedError = YES;
            }
        }
        
        if (hasFinishedOutput && hasFinishedError) {
            break;
        }
    }
    
    if (output)
        *output = outdata;
    if (error)
        *error = errdata;

    return;
    
    NSRunLoop *runloop = [NSRunLoop currentRunLoop];
    NSTimeInterval delay = 0.01;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncFileHandleReadCompletion:) name:NSFileHandleReadToEndOfFileCompletionNotification object:[outPipe fileHandleForReading]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncFileHandleReadCompletion:) name:NSFileHandleReadToEndOfFileCompletionNotification object:[errPipe fileHandleForReading]];
        
    [[outPipe fileHandleForReading] readToEndOfFileInBackgroundAndNotifyForModes:[NSArray arrayWithObject:@"taskitread"]];
    [[errPipe fileHandleForReading] readToEndOfFileInBackgroundAndNotifyForModes:[NSArray arrayWithObject:@"taskitread"]];
    
    // TODO: Replace this with something more robust
    NSTimeInterval startTime = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval outputTime = 0;
    NSTimeInterval errorTime = 0;
    
    BOOL hitTimeout = NO;
    do {
        NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];
        
        if (timeoutIfNothing > 0 && currentTime - startTime > timeoutIfNothing) {
        
            // If the user has set a timeout for getting no data
            if ((!output || !hasFinishedReadingOutput) && (!error || !hasFinishedReadingError)) {
                hitTimeout = YES;
                break;
            }
        }
        
        if (outputTime == 0 && hasFinishedReadingOutput)
            outputTime = currentTime;
        if (errorTime == 0 && hasFinishedReadingError)
            errorTime = currentTime;
        
        if (timeoutSinceOutput > 0 && currentTime - outputTime > timeoutSinceOutput) {
            
            // If the user has set a timeout for getting error if we've received output
            if (hasFinishedReadingOutput && !hasFinishedReadingError) {
                hitTimeout = YES;
                break;
            }
        }
        
        if (timeoutSinceError > 0 && currentTime - errorTime > timeoutSinceError) {
            
            // If the user has set a timeout for getting output if we've received error
            if (hasFinishedReadingError && !hasFinishedReadingOutput) {
                hitTimeout = YES;
                break;
            }
        }
        
        if ((!output || hasFinishedReadingOutput) && (!error || hasFinishedReadingError))
            break;
        
        [runloop runMode:@"taskitread" beforeDate:[NSDate dateWithTimeIntervalSinceNow:delay]];
                
    } while (1);
    
    [outputBuffer autorelease];
    [errorBuffer autorelease];
        
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleReadToEndOfFileCompletionNotification object:[outPipe fileHandleForReading]];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleReadToEndOfFileCompletionNotification object:[errPipe fileHandleForReading]];
    
    [[outPipe fileHandleForReading] closeFile];
    [[errPipe fileHandleForReading] closeFile];
                
    if (hitTimeout) [self kill];
                
                
    if (output)
        *output = outputBuffer;
    if (error)
        *error = errorBuffer;
}
- (void)waitForOutputString:(NSString **)output errorString:(NSString **)error {
    NSData *outputData = nil;
    NSData *errorData = nil;
    
    [self waitForOutputData:output ? &outputData : NULL errorData:error ? &errorData : NULL];
    
    if (outputData)
        *output = [[[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding] autorelease];
    if (errorData)
        *error = [[[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding] autorelease];
}



#pragma mark Goodbye!

- (void)dealloc {
    
    //NSLog(@"Deallocing %@", launchPath);
    
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
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [super dealloc];
}

@end
