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
                
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fileHandleDataAvailable:) name:NSFileHandleDataAvailableNotification object:[outPipe fileHandleForReading]];
        
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
                
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fileHandleDataAvailable:) name:NSFileHandleDataAvailableNotification object:[errPipe fileHandleForReading]];
        
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
        //dup2(new_err, STDERR_FILENO);
        
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
    
//    [[outPipe fileHandleForReading] readToEndOfFileInBackgroundAndNotify];
//    [[errPipe fileHandleForReading] readToEndOfFileInBackgroundAndNotify];

    
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
    /*
    if (receivedOutputData || receivedOutputString) {
                
        [[outPipe fileHandleForReading] readToEndOfFileInBackgroundAndNotify];
    }
    
    if (receivedErrorData || receivedErrorString) {
                
        [[errPipe fileHandleForReading] readToEndOfFileInBackgroundAndNotify];
    }
    */
    return YES;
}
- (void)flushAll {
    NSLog(@"Flushing: %@ %@", outputBuffer, errorBuffer);
    [self flushOutput];
    [self flushError];
}
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
- (void)fileHandleDataAvailable:(NSNotification *)notif {
    
    NSData *data = [[notif userInfo] valueForKey:NSFileHandleNotificationDataItem];
    NSLog(@"[notif object] = %@", [notif object]);
    /*if ([[notif object] isEqual:[outPipe fileHandleForReading]]) {
        
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
    }*/
    
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
    
    [self flushOutput];
    
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
/*
- (void)waitFor:(TaskitWaitMask)waitMask {
    
    NSRunLoop *runloop = [NSRunLoop currentRunLoop];
    NSTimeInterval delay = 0.01;
    
    while ([self isRunning]) {
        
        [runloop runMode:@"taskit" beforeDate:[NSDate dateWithTimeIntervalSinceNow:delay]];
        
        delay *= 2;
        if (delay >= 1.0)
            delay = 1.0;
    }
}
*/
- (NSData *)waitForOutput {
    //[[outPipe fileHandleForWriting] closeFile];
    NSLog(@"WAIT FOR OUTPUT");
   
    NSMutableData *data = [NSMutableData data];
    unsigned char buf[200];
    int fd = [[outPipe fileHandleForReading] fileDescriptor];
    
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    
    while (1) {
        //        if (![self isRunning])
        //            break;
        
        ssize_t ex = read(fd, buf, 200);
        NSLog(@"\t ex = %ld", ex);
        if (ex == -1 && errno == EAGAIN)
            continue;
        if (ex == -1) {
            NSLog(@"%d", errno);
            return data;
        }
        if (ex == 0)
            break;
        
        [data appendBytes:buf length:ex];
    }
    /*
    
    NSMutableData *data = [NSMutableData data];
    unsigned char buf[200];
    int fd = [[outPipe fileHandleForReading] fileDescriptor];
    while (1) {
//        if (![self isRunning])
//            break;
        
        ssize_t ex = read(fd, buf, 200);
        if (ex == -1)
            return nil;
        
        if (ex == 0)
            break;
        
        [data appendBytes:buf length:ex];
    }
    */
    //NSData *data = [[outPipe fileHandleForReading] readDataToEndOfFile];
    //[[outPipe fileHandleForReading] closeFile];
    
    return data;
}
- (NSString *)waitForOutputString {
    
    NSData *data = [self waitForOutput];
    if (!data)
        return nil;
    return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
}
// Want to either wait for it to exit, or for it to EOF
- (NSData *)waitForError {
    
    NSLog(@"WAIT FOR ERROR");
    NSMutableData *data = [NSMutableData data];
    unsigned char buf[200];
    int fd = [[errPipe fileHandleForReading] fileDescriptor];
    
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    
    while (1) {
        //        if (![self isRunning])
        //            break;
        
        ssize_t ex = read(fd, buf, 200);
        NSLog(@"\t ex = %ld", ex);
        if (ex == -1 && errno == EAGAIN)
            continue;
        if (ex == -1) {
            NSLog(@"%d", errno);
            return data;
        }
        if (ex == 0)
            break;
        
        [data appendBytes:buf length:ex];
    }
    NSLog(@"data = %@", data);
    /*
    
    NSMutableData *data = [NSMutableData data];
    NSFileHandle *fh =[errPipe fileHandleForReading];
    while (1) {
        //NSLog(@"Again");
        NSData *availableData = [fh availableData];
        //NSLog(@"availableData = %@", availableData);
        if (!availableData)
            break;
        [data appendData:availableData];
        break;
    }
    //NSData *data = [[errPipe fileHandleForReading] readDataToEndOfFile];
    //[[errPipe fileHandleForReading] closeFile];
    */
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
