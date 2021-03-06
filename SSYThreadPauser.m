#import "SSYThreadPauser.h"
#import "NSInvocation+Quick.h"

NSString* const SSYThreadPauserKeyLock = @"SSYThreadPauserKeyLock" ;
NSString* const SSYThreadPauserKeyInvocation = @"SSYThreadPauserKeyInvocation" ;

#define WORK_IS_NOT_DONE 0
#define WORK_IS_DONE 1


@implementation SSYThreadPauser

- (void)beginWorkWithInfo:(NSDictionary*)info {
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init] ;
	NSConditionLock* lock = [info objectForKey:SSYThreadPauserKeyLock] ;
 	[lock lock] ;
 	NSInvocation* invocation = [info objectForKey:SSYThreadPauserKeyInvocation] ;
	
	// Do actual work
	[invocation invoke] ;
	
	[lock unlockWithCondition:WORK_IS_DONE] ;
	[pool drain] ;
}


+ (BOOL)blockUntilWorker:(id)worker
				selector:(SEL)selector	
				  object:(id)object
				  thread:(NSThread*)workerThread
				 timeout:(NSTimeInterval)timeout {
    /*
     Here's a fun 64-bit quirk that set me back a couple hours.  If you ever
     write a method which creates a date from an NSTimeInterval parameter, make
     sure that you can't create an unreasonably large date.  I'd been passing
     FLT_MAX to indicate "no timeout" to such a method.
     
     Works OK in 32-bit.  In 64-bit, -[NSDate compare:] and -[NSDate laterDate:]
     still work as expected.  But other methods may not.  For example,
     -[NSConditionLock lockWhenCondition:beforeDate:] seems to think that such
     a "float max date" has already past and returns NO immediately, regardless
     of its 'condition'.
     
     The solution is the next two lines…
     */
    NSTimeInterval maxTimeout = [[NSDate distantFuture] timeIntervalSinceNow] ;
    timeout = MIN(timeout, maxTimeout) ;
    NSDate* timeoutDate = [NSDate dateWithTimeIntervalSinceNow:timeout] ;
    
	SSYThreadPauser* instance = [[SSYThreadPauser alloc] init] ;
	
	NSInvocation* invocation = [NSInvocation invocationWithTarget:worker
														 selector:selector
												  retainArguments:YES
												argumentAddresses:&object] ;
	
	NSConditionLock* lock = [[NSConditionLock alloc] initWithCondition:WORK_IS_NOT_DONE] ;
	
	NSDictionary* info = [NSDictionary dictionaryWithObjectsAndKeys:
						  invocation, SSYThreadPauserKeyInvocation,
						  lock, SSYThreadPauserKeyLock,
						  nil] ;
	
	// Begin Work
	if (workerThread) {
		[instance performSelector:@selector(beginWorkWithInfo:)
						 onThread:workerThread
					   withObject:info
					waitUntilDone:NO] ;
	}
	else {
		// Default if no workerThread given is to create one
		workerThread = [[[NSThread alloc] initWithTarget:instance
												selector:@selector(beginWorkWithInfo:)
												  object:info] autorelease] ;
		// Name the thread, to help in debugging.
		[workerThread setName:@"Worker created by SSYThreadPauser"] ;
		[workerThread start] ;
	}
	
	// Will block here until work is done, or timeout
	BOOL workFinishedInTime = [lock lockWhenCondition:WORK_IS_DONE
										   beforeDate:timeoutDate] ;
	if (workFinishedInTime) {
		[lock unlock] ;
	}
	[workerThread cancel] ;
	
	[instance release] ;
	[lock release] ;
	
	return (workFinishedInTime) ;
}


@end


