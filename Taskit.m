//  Taskit
//  Written by Alex Gordon on 09/09/2011.
//  Licensed under the WTFPL: http://sam.zoy.org/wtfpl/

#import "Taskit.h"

@interface Taskit ()

- (void)flushOutput;
- (void)flushError;

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
    
    size_t copysize = (strlen(originalString) + 1) * sizeof(char);
    char* newString = (char*)calloc(copysize, 1);
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
    
    self.launchPath = [launchPath stringByStandardizingPath];
    
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:launchPath])
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
    
    //TODO: Check ARG_MAX
    
// Backgrounding
    
    if (receivedOutputData || receivedOutputString) {
                
        //[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fileHandleDataAvailable:) name:NSFileHandleDataAvailableNotification object:[outPipe fileHandleForReading]];
        
//        [[outPipe fileHandleForReading] readInBackgroundAndNotify];
        [[outPipe fileHandleForReading] setReadabilityHandler:^void (NSFileHandle *h) {
            NSData *data = [h availableData];
            if (!outputBuffer)
                outputBuffer = [data mutableCopy];
            else
                [outputBuffer appendData:data];
            
            if (![self isRunning])
                [self flushOutput];
        }];
    }
    
    if (receivedErrorData || receivedErrorString) {
                
        //[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fileHandleDataAvailable:) name:NSFileHandleDataAvailableNotification object:[errPipe fileHandleForReading]];
        
//        [[errPipe fileHandleForReading] readInBackgroundAndNotify];
        [[errPipe fileHandleForReading] setReadabilityHandler:^void (NSFileHandle *h) {
            NSData *data = [h availableData];
            NSLog(@"ERR: %@", data);
            if (!errorBuffer)
                errorBuffer = [data mutableCopy];
            else
                [errorBuffer appendData:data];
            
            if (![self isRunning])
                [self flushError];
        }];

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
    
    // *retain* ourselves, since the notification center won't
    if (receivedOutputData || receivedOutputString)
        CFRetain(self);
    if (receivedErrorData || receivedErrorString)
        CFRetain(self);
    
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
/*
- (void)flushAll {
    NSLog(@"Flushing: %@ %@", outputBuffer, errorBuffer);
    [self flushOutput];
    [self flushError];
}
 */
- (void)flushOutput {
    if (outputBuffer) {
        if (receivedOutputData)
            receivedOutputData(outputBuffer);
        if (receivedOutputString)
            receivedOutputString([[[NSString alloc] initWithData:outputBuffer encoding:NSUTF8StringEncoding] autorelease]);
        
        [outputBuffer release];
        outputBuffer = nil;
        
        CFRelease(self);
    }
}
- (void)flushError {
    if (errorBuffer) {
        
        if (receivedErrorData)
            receivedErrorData(errorBuffer);
        if (receivedErrorString)
            receivedErrorString([[[NSString alloc] initWithData:errorBuffer encoding:NSUTF8StringEncoding] autorelease]);
        
        [errorBuffer release];
        errorBuffer = nil;
        
        CFRelease(self);
    }
}
/*
- (void)fileHandleDataAvailable:(NSNotification *)notif {
    
    NSData *data = [[notif userInfo] valueForKey:NSFileHandleNotificationDataItem];
    
    if ([[notif object] isEqual:[outPipe fileHandleForReading]]) {
        if (!outputBuffer)
            outputBuffer = [data copy];
        else
            [outputBuffer appendData:data];
        
        if (![self isRunning])
            [self flushOutput];
    }
    else if ([[notif object] isEqual:[errPipe fileHandleForReading]]) {
        if (!errorBuffer)
            errorBuffer = [data copy];
        else
            [errorBuffer appendData:data];
        
        if (![self isRunning])
            [self flushError];
    }
}
 */


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
    
    //[self flushOutput];
    
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

- (void)waitForOutputData:(NSData **)output errorData:(NSData **)error {
    *output = [NSMutableData data];
    *error = [NSMutableData data];
    
#define TASKIT_BUFFER_LENGTH 200
    
    unsigned char out_buf[TASKIT_BUFFER_LENGTH];
    int out_fd = [[outPipe fileHandleForReading] fileDescriptor];
    int out_flags = fcntl(out_fd, F_GETFL, 0);
    fcntl(out_fd, F_SETFL, out_flags | O_NONBLOCK);

    unsigned char err_buf[TASKIT_BUFFER_LENGTH];
    int err_fd = [[errPipe fileHandleForReading] fileDescriptor];
    int err_flags = fcntl(err_fd, F_GETFL, 0);
    fcntl(err_fd, F_SETFL, err_flags | O_NONBLOCK);
    
    while (1) {
        
        if (err_fd == -1 && out_fd == -1)
            break;
        
        // stdout
        if (out_fd >= 0) {
            NSLog(@"READING [out]: %d", out_fd);
            ssize_t ex = read(out_fd, out_buf, TASKIT_BUFFER_LENGTH);
            NSLog(@"\t(%d, %d)", ex, errno);
            if (ex == -1 && errno == EAGAIN)
                continue;
            else if (ex == -1 && errno == EINVAL) {
                out_fd = -1;
            }
            else if (ex == -1) {
                out_fd = -1;
            }
            else {
                [(NSMutableData *)*output appendBytes:out_buf length:ex];
            }
        }
        
        // stderr
        if (err_fd >= 0) {
            
            NSLog(@"READING [err]: %d", out_fd);
            ssize_t ex = read(err_fd, err_buf, TASKIT_BUFFER_LENGTH);
            NSLog(@"\t(%d, %d)", ex, errno);
            if (ex == -1 && errno == EAGAIN)
                continue;
            else if (ex == -1 && errno == EINVAL) {
                err_fd = -1;
            }
            else if (ex == -1) {
                err_fd = -1;
            }
            else {
                [(NSMutableData *)*error appendBytes:err_buf length:ex];
            }
        }
    }
}
- (void)waitForOutputString:(NSString **)output errorString:(NSString **)error {
    NSData *outputData = nil;
    NSData *errorData = nil;
    
    [self waitForOutputData:&outputData errorData:&errorData];
    
    if (output)
        *output = [[[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding] autorelease];
    if (error)
        *error = [[[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding] autorelease];
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
