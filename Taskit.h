//  Taskit
//  Written by Alex Gordon on 09/09/2011.
//  Licensed under the WTFPL: http://sam.zoy.org/wtfpl/

#import <Foundation/Foundation.h>

typedef enum {
    
    TaskitWaitFor_Exit = 1,
    TaskitWaitFor_Output = 1 << 1,
    TaskitWaitFor_Error = 1 << 2,
    
} TaskitWaitMaskComponent;
typedef unsigned TaskitWaitMask;

@interface Taskit : NSObject
{
    BOOL hasLaunched;
    
    NSString *launchPath;
    NSMutableArray *arguments;
    NSMutableDictionary *environment;
    NSString *workingDirectory;
    
    NSData *input;
    NSString *inputString;
    NSString* inputPath; // Optional alternative to inputString
    
    //TODO: BOOL usesAuthorization;
    
    NSPipe *inPipe;
    NSPipe *outPipe;
    NSPipe *errPipe;
    
    BOOL shouldSetUpFileHandlesAutomatically;
    
    pid_t pid;
    int waitpid_status;
    BOOL isRunning;
    
#ifdef TASKIT_BACKGROUNDING
    void (^receivedOutputData)(NSData *output);
    void (^receivedOutputString)(NSString *outputString);
    
    void (^receivedErrorData)(NSData *err);
    void (^receivedErrorString)(NSString *errString);
#endif
    
    NSMutableData *outputBuffer;
    NSMutableData *errorBuffer;
    
    BOOL hasFinishedReadingOutput;
    BOOL hasFinishedReadingError;
    
    BOOL hasRetainedForOutput;
    BOOL hasRetainedForError;
    
    NSTimeInterval timeoutIfNothing;
    NSTimeInterval timeoutSinceOutput;
    NSTimeInterval timeoutSinceError;
    
    NSInteger priority;
}

+ (id)task;
- (id)init;

#pragma mark Setup

@property (copy) NSString *launchPath;
@property (readonly) NSMutableArray *arguments;
@property (readonly) NSMutableDictionary *environment;
@property (copy) NSString *workingDirectory;

@property (copy) NSData *input;
@property (copy) NSString *inputString;
@property (copy) NSString *inputPath;

@property NSInteger priority;

@property BOOL shouldSetUpFileHandlesAutomatically;
- (void)setUpFileHandles;

- (void)populateWithCurrentEnvironment;

//TODO: @property BOOL usesAuthorization;

#pragma mark Concurrency
#ifdef TASKIT_BACKGROUNDING
@property (copy) void (^receivedOutputData)(NSData *output);
@property (copy) void (^receivedOutputString)(NSString *outputString);
@property (copy) void (^receivedErrorData)(NSData *err);
@property (copy) void (^receivedErrorString)(NSString *errString);
#endif

//TODO: @property (copy) void (^processExited)(NSString *outputString);

#pragma mark Timeouts

// The amount of time to wait if nothing has been read yet
@property NSTimeInterval timeoutIfNothing;

// The amount of time to wait for stderr if stdout HAS been read
@property NSTimeInterval timeoutSinceOutput;

// The amount of time to wait for stdout if stderr HAS been read
@property NSTimeInterval timeoutSinceError;


#pragma mark Status
- (NSInteger)processIdentifier;
- (NSInteger)terminationStatus;
- (NSTaskTerminationReason)terminationReason;
- (NSInteger)terminationSignal;


#pragma mark Control
- (BOOL)launch;

- (void)interrupt; // Not always possible. Sends SIGINT.
- (void)terminate; // Not always possible. Sends SIGTERM.
- (void)kill;

- (BOOL)suspend;
- (BOOL)resume;


- (BOOL)isRunning;
- (void)reapOnExit;

#pragma mark Blocking methods
- (void)waitUntilExit;
- (BOOL)waitUntilExitWithTimeout:(NSTimeInterval)timeout;

- (BOOL)waitForIntoOutputData:(NSMutableData *)output intoErrorData:(NSMutableData *)error;
- (BOOL)waitForOutputData:(NSData **)output errorData:(NSData **)error;
- (void)waitForOutputString:(NSString **)output errorString:(NSString **)error;

- (NSData *)waitForOutput;
- (NSString *)waitForOutputString;

- (NSData *)waitForError;
- (NSString *)waitForErrorString;

@end
