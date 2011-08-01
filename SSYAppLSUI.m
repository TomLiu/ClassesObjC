#import "SSYAppLSUI.h"
//#import "NSMenu+Initialize.h"


@implementation SSYAppLSUI

+ (BOOL)isLSUIElement {
	ProcessSerialNumber psn = { 0, kCurrentProcess } ;
	NSDictionary* info = nil ;
	info = (NSDictionary*)ProcessInformationCopyDictionary (&psn, kProcessDictionaryIncludeAllInformationMask) ;
	
	BOOL is = [[info objectForKey:@"LSUIElement"] boolValue] ;
	
	if (info != NULL) {
		CFRelease((CFDictionaryRef)info) ;
	}
	
	return is ;
}

+ (pid_t)inactivateActiveAppAndReturnNewActiveApp {
	//NSLog(@"1000 Hiding Current ActiveApp: %@", [[[NSWorkspace sharedWorkspace] activeApplication] objectForKey:@"NSApplicationName"]) ;
	pid_t activeAppPid = [[[[NSWorkspace sharedWorkspace] activeApplication] objectForKey:@"NSApplicationProcessIdentifier"] intValue] ;
	OSStatus err;
	ProcessSerialNumber psn ;
	err = GetProcessForPID(activeAppPid, &psn) ;
	err = ShowHideProcess(&psn, false) ;
	//NSLog(@"2000 New ActiveApp: %@", [[[NSWorkspace sharedWorkspace] activeApplication] objectForKey:@"NSApplicationName"]) ;
	activeAppPid = [[[[NSWorkspace sharedWorkspace] activeApplication] objectForKey:@"NSApplicationProcessIdentifier"] intValue] ;
	return activeAppPid ;
}

+ (void)bringFrontPid:(pid_t)pid {
	// Remember that any NSLogs early in the app results in two "Help" menus
	//NSLog(@"ActiveApp: %@", [[[NSWorkspace sharedWorkspace] activeApplication] objectForKey:@"NSApplicationName"]) ;
	sleep(2) ;
	ProcessSerialNumber psn ;
	OSStatus err ;
	err = GetProcessForPID(pid, &psn) ;
	SetFrontProcess(&psn);
}

+ (void)transformToGui {
	if ([self isLSUIElement]) {
#if 0
		ProcessSerialNumber psn;
		pid_t pid = getpid();
		OSStatus err;
		err = ShowHideProcess(&psn, true);
		err = TransformProcessType(&psn, kProcessTransformToForegroundApplication);
		[NSMenu setMenuBarVisible:NO];
		SetFrontProcess(&psn);
		[NSMenu setMenuBarVisible:YES];
		// [NSMenu setMenuBarVisible:YES] ;  // causes The Dreaded Two Help Menus if run in app delegate's -init
		
		// More stuff which doesn't work
		// At this point, this app will show in the dock, but the menu
		// will not show unless you activate some other app and then
		// re-activate this app.  I tried a bunch of stuff but nothing
		// worked reliably
		
		BOOL yes = YES ;
		NSInvocation* invocation = [NSInvocation invocationWithTarget:[NSMenu class]
															 selector:@selector(setMenuBarVisible:)
													  retainArguments:YES
													argumentAddresses:&yes] ;
		[invocation performSelector:@selector(invoke)
						 withObject:nil
						 afterDelay:1.0] ;
		[invocation performSelector:@selector(invoke)
						 withObject:nil
						 afterDelay:2.0] ;
		[invocation performSelector:@selector(invoke)
						 withObject:nil
						 afterDelay:3.0] ;

		for (NSWindow* window in [NSApp windows]) {
			[window display] ;
			usleep(500000) ;
			[NSMenu setMenuBarVisible:NO];
			[window makeKeyAndOrderFront:self] ;
			usleep(500000) ;
			[NSMenu setMenuBarVisible:YES];
		}
		[NSApp activateIgnoringOtherApps:YES] ;
		// [[[[[NSApp mainMenu] itemArray] objectAtIndex:0] submenu] performActionForItemAtIndex:0] ;
#else
			ProcessSerialNumber psn = { 0, kCurrentProcess } ;
			OSStatus err ;
			err = TransformProcessType(&psn, kProcessTransformToForegroundApplication) ;
			
			[NSApp activateIgnoringOtherApps:YES] ;
#endif
	}
}

+ (IBAction)transformToGui:(id)sender {
	[self transformToGui] ;
}


@end