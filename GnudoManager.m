#import "GnudoManager.h"
#import "NSObject+MoreDescriptions.h"


/*
 *	Private class representing a group of undo/redo actions.
 */
@interface	GnudoGroup : NSObject
{
	GnudoGroup	*parent;
	NSMutableArray	*actions;
	NSString              *actionName;
}
- (NSMutableArray*) actions;

- (NSString*) actionName;
- (void) addInvocation: (NSInvocation*)inv;
- (id) initWithParent: (GnudoGroup*)parent;
- (void) orphan;
- (GnudoGroup*) parent;
- (void) perform;
- (BOOL) removeActionsForTarget: (id)target;
- (void) setActionName: (NSString*)name;
@end

@implementation	GnudoGroup

- (NSMutableArray*) actions
{
	return actions;
}

- (NSString*) actionName
{
	return (actionName ? actionName : @"") ;  // JERRY
}

- (void) addInvocation: (NSInvocation*)inv
{
	if (actions == nil)
    {
		actions = [[NSMutableArray alloc] initWithCapacity: 2];
    }
	[actions addObject: inv];
}

- (NSString*)longDescription {
	NSMutableString* d = [NSMutableString stringWithFormat:
						  @"%@: %p with %d invocations:",
						  [self className],
						  self,
						  [[self actions] count]] ;
	for (NSInvocation* action in [self actions]) {
		[d appendFormat:
		 @"\n   %@",
		 [action longDescription]] ;
	}
	
	return d ;
}

- (void) dealloc
{
	[actions release];
	[parent release];
	[actionName release];
	[super dealloc];
}

- (id) initWithParent: (GnudoGroup*)p
{
	self = [super init];
	if (self)
    {
		parent = [p retain];
		actions = nil;
		actionName = @"";
    }
	return self;
}

- (void) orphan
{
	[parent release];
	parent = nil ;
}

- (GnudoGroup*) parent
{
	return parent;
}

- (void) perform
{
	if (actions != nil)
    {
		unsigned	i = [actions count];
		
		while (i-- > 0)
		{
			[[actions objectAtIndex: i] invoke];
		}
    }
}

- (BOOL) removeActionsForTarget: (id)target
{
	if (actions != nil)
    {
		unsigned	i = [actions count];
		
		while (i-- > 0)
		{
			NSInvocation	*inv = [actions objectAtIndex: i];
			
			if ([inv target] == target)
			{
				[actions removeObjectAtIndex: i];
			}
		}
		if ([actions count] > 0)
		{
			return YES;
		}
    }
	return NO;
}

- (void)setActionName:(NSString *)value {
    if (actionName != value) {
        [actionName release];
        actionName = [value copy];
    }
}

@end



/*
 *	Private category for the method used to handle default grouping
 */
@interface GnudoManager (Private)
- (void) _loop: (id)arg;
@end

@implementation GnudoManager (Private)
- (void) _loop: (id)arg
{
	if (_groupsByEvent)
    {
		if (m_group != nil)
		{
			[self endUndoGrouping];
		}
		[self beginUndoGrouping];
    }
	_runLoopGroupingPending = NO;
}
@end



/**
 *  GnudoManager provides a general mechanism supporting implementation of
 *  user action "undo" in applications.  Essentially, it allows you to store
 *  sequences of messages and receivers that need to be invoked to undo or
 *  redo an action.  The various methods in this class provide for grouping
 *  of sets of actions, execution of undo or redo actions, and tuning behavior
 *  parameters such as the size of the undo stack.  Each application entity
 *  with its own editing history (e.g., a document) should have its own undo
 *  manager instance.  Obtain an instance through a simple
 *  <code>[[GnudoManager alloc] init]</code> message.
 */
@implementation GnudoManager

/**
 * Starts a new grouping of undo actions which can be
 * atomically undone by an [-undo] invocation.
 * This method posts an NSUndoManagerCheckpointNotification
 * unless an undo is currently in progress.  It posts an
 * NSUndoManagerDidOpenUndoGroupNotification upon creating the grouping.
 */
- (void) beginUndoGrouping
{
	GnudoGroup	*parent;
	
	if (_isUndoing == NO)
    {
		[[NSNotificationCenter defaultCenter]
		 postNotificationName: NSUndoManagerCheckpointNotification
		 object: self];
    }
	parent = (GnudoGroup*)m_group;
	m_group = [[GnudoGroup alloc] initWithParent: parent];
	if (m_group == nil)
    {
		m_group = parent;
		[NSException raise: NSInternalInconsistencyException
					format: @"beginUndoGrouping failed to greate group"];
    }
	else
    {
		[parent release];
		
		[[NSNotificationCenter defaultCenter]
		 postNotificationName: NSUndoManagerDidOpenUndoGroupNotification
		 object: self];
    }
}

/**
 * Returns whether the receiver can service redo requests and
 * posts a NSUndoManagerCheckpointNotification.
 */
- (BOOL) canRedo
{
	[[NSNotificationCenter defaultCenter]
	 postNotificationName: NSUndoManagerCheckpointNotification
	 object: self];
	if ([_redoStack count] > 0)
    {
		return YES;
    }
	else
    {
		return NO;
    }
}

/**
 * Returns whether the receiver has any action groupings
 * on the stack to undo.  It does not imply, that the
 * receiver is currently in a state to service an undo
 * request.  Make sure [-endUndoGrouping] is invoked before
 * requesting either an [-undo] or an [-undoNestedGroup].
 */
- (BOOL) canUndo
{
	if ([_undoStack count] > 0)
    {
		return YES;
    }
	if (m_group != nil && [[m_group actions] count] > 0)
    {
		return YES;
    }
	return NO;
}

- (void) dealloc
{
	[[NSRunLoop currentRunLoop] cancelPerformSelector: @selector(_loop:)
											   target: self
											 argument: nil];
	[_redoStack release];
	[_undoStack release];
	[m_group release];
	[_modes release];
	[super dealloc];
}

/**
 * Disables the registration of operations with with either
 * [-registerUndoWithTarget:selector:object:] or
 * [-forwardInvocation:].  This method may be called multiple
 * times.  Each will need to be paired to a call of
 * [-enableUndoRegistration] before registration is actually
 * reenabled.
 */
- (void) disableUndoRegistration
{
	_disableCount++;
}

/**
 * Matches previous calls of to [-disableUndoRegistration].
 * Only call this method to that end.  Once all are matched,
 * the registration of [-registerUndoWithTarget:selector:object:]
 * and [-forwardInvocation:] are reenabled.  If this method is
 * called without a matching -disableUndoRegistration,
 * it will raise an NSInternalInconsistencyException.
 */
- (void) enableUndoRegistration
{
	if (_disableCount > 0)
    {
		_disableCount--;
    }
	else
    {
		[NSException raise: NSInternalInconsistencyException
					format: @"enableUndoRegistration without disable"];
    }
}

/**
 * Matches previous calls of to [-beginUndoGrouping] and
 * puts the group on the undo stack.  This method posts
 * an NSUndoManagerCheckpointNotification and
 * a NSUndoManagerWillCloseUndoGroupNotification.
 * If there was no matching call to -beginUndoGrouping,
 * this method will raise an NSInternalInconsistencyException.
 */
- (void) endUndoGrouping
{
	GnudoGroup	*g;
	GnudoGroup	*p;
	
	if (m_group == nil)
    {
		[NSException raise: NSInternalInconsistencyException
					format: @"endUndoGrouping without beginUndoGrouping"];
    }
	[[NSNotificationCenter defaultCenter]
	 postNotificationName: NSUndoManagerCheckpointNotification
	 object: self];
	g = (GnudoGroup*)m_group;
/*DB?Line*/ NSLog(@"6600 >> %s", __PRETTY_FUNCTION__) ;
/*DB?Line*/ NSLog(@"6610:    m_group = %@", m_group) ;
	p = [[g parent] retain];
/*DB?Line*/ NSLog(@"6750:          p = %@", p) ;
	m_group = p;
/*DB?Line*/ NSLog(@"6610:    m_group = %@", m_group) ;
	[g orphan];
/*DB?Line*/ NSLog(@"6653     did orphan m_group %p", m_group) ;
	[[NSNotificationCenter defaultCenter]
	 postNotificationName: NSUndoManagerWillCloseUndoGroupNotification
	 object: self];
	if (p == nil)
    {
		if (_isUndoing)
		{
			if (_levelsOfUndo > 0 && [_redoStack count] == _levelsOfUndo && [[g actions] count] > 0)
			{
				[_redoStack removeObjectAtIndex: 0];
			}
			
			if (g != nil)
			{
				if ([[g actions] count] > 0)
					[_redoStack addObject: g];
			}
		}
		else
		{
			if (_levelsOfUndo > 0 && [_undoStack count] == _levelsOfUndo && [[g actions] count] > 0)
			{
				[_undoStack removeObjectAtIndex: 0];
			}
			
			if (g != nil)
			{
				if ([[g actions] count] > 0)
					[_undoStack addObject: g];
			}
		}
    }
	else if ([g actions] != nil)
    {
		NSArray	*a = [g actions];
		unsigned	i;
		
		for (i = 0; i < [a count]; i++)
		{
			[p addInvocation: [a objectAtIndex: i]];
		}
    }
	[g release];
/*DB?Line*/ NSLog(@"7791 << %s", __PRETTY_FUNCTION__) ;
}

/**
 * Registers the invocation with the current undo grouping.
 * This method is part of the NSInvocation-based undo registration
 * as opposed to the simpler [-registerUndoWithTarget:selector:object:]
 * technique.<br />
 * You generally never invoke this method directly.
 * Instead invoke [-prepareWithInvocationTarget:] with the target of the
 * undo action and then invoke the targets method to undo the action
 * on the return value of -prepareWithInvocationTarget:
 * which actually is the undo manager.
 * The runtime will then fallback to -forwardInvocation: to do the actual
 * registration of the invocation.
 * The invocation will added to the current grouping.<br />
 * If the registrations have been disabled through [-disableUndoRegistration],
 * this method does nothing.<br />
 * Unless the receiver implicitly
 * groups operations by event, the this method must have been preceded
 * with a [-beginUndoGrouping] message.  Otherwise it will raise an
 * NSInternalInconsistencyException. <br />
 * Unless this method is invoked as part of a [-undo] or [-undoNestedGroup]
 * processing, the redo stack is cleared.<br />
 * If the receiver [-groupsByEvent] and this is the first call to this
 * method since the last run loop processing, this method sets up
 * the receiver to process the [-endUndoGrouping] at the
 * end of the event loop.
 */
- (void) forwardInvocation: (NSInvocation*)anInvocation
{
	if (_disableCount == 0)
    {
		if (_nextTarget == nil)
		{
			[NSException raise: NSInternalInconsistencyException
						format: @"forwardInvocation without perparation"];
		}
		if (m_group == nil)
		{
			if ([self groupsByEvent])
			{
				[self beginUndoGrouping];
			}
			else
			{
				[NSException raise: NSInternalInconsistencyException
							format: @"forwardInvocation without beginUndoGrouping"];
			}
		}
		[anInvocation retainArguments];
		[anInvocation setTarget: _nextTarget];
		_nextTarget = nil;
		[m_group addInvocation: anInvocation];
		if (_isUndoing == NO && _isRedoing == NO && [m_group actions] > 0)
		{
			[_redoStack removeAllObjects];
		}
		if ((_runLoopGroupingPending == NO) && ([self groupsByEvent] == YES))
		{
			[[NSRunLoop currentRunLoop] performSelector: @selector(_loop:)
												 target: self
											   argument: nil
												  order: NSUndoCloseGroupingRunLoopOrdering
												  modes: _modes];
			_runLoopGroupingPending = YES;
		}
    }
}

/**
 * If the receiver was sent a [-prepareWithInvocationTarget:] and
 * the target's method hasn't been invoked on the receiver yet, this
 * method forwards the request to the target.
 * Otherwise or if the target didn't return a signature, the message
 * is sent to super.
 */
- (NSMethodSignature*) methodSignatureForSelector: (SEL)selector
{
	NSMethodSignature *sig = nil;
	
	if (_nextTarget != nil)
    {
		sig = [_nextTarget methodSignatureForSelector: selector];
    }
	if (sig == nil)
    {
		sig = [super methodSignatureForSelector: selector];
    }
	return sig;
}

/**
 * Returns the current number of groupings.  These are the current
 * groupings which can be nested, not the number of of groups on either
 * the undo or redo stack.
 */
- (int) groupingLevel
{
	GnudoGroup	*g = (GnudoGroup*)m_group;
	int			level = 0;
	
	while (g != nil)
    {
		level++;
		g = [g parent];
    }
	return level;
}

// JERRY
- (void)logGroupLineage
{
	GnudoGroup	*g = (GnudoGroup*)m_group;
	NSMutableString* lineage = [NSMutableString string] ;
	[lineage appendFormat:@"\nCurrently, %d Undo Groups Nested:\n", [self groupingLevel]] ;
	
	while (g != nil)
    {
		[lineage appendFormat:@"   %@\nWith Parent Group:", [g longDescription]] ;
		g = [g parent];
    }
	[lineage appendString:@"   0x0"] ;
	NSLog(lineage) ;
}

/**
 * Returns whether the receiver currently groups undo
 * operations by events.  When it does, so it implicitly
 * invokes [-beginUndoGrouping] upon registration of undo
 * operations and registers an internal call to insure
 * the invocation of [-endUndoGrouping] at the end of the
 * run loop.
 */
- (BOOL) groupsByEvent
{
	return _groupsByEvent;
}

- (id) init
{
	self = [super init];
	if (self)
    {
		_redoStack = [[NSMutableArray alloc] initWithCapacity: 16];
		_undoStack = [[NSMutableArray alloc] initWithCapacity: 16];
		_groupsByEvent = YES;
		[self setRunLoopModes:
		 [NSArray arrayWithObjects: NSDefaultRunLoopMode, nil]];
    }
	return self;
}

/**
 * Returns whether the receiver is currently processing a redo.
 */
- (BOOL) isRedoing
{
	return _isRedoing;
}

/**
 * Returns whether the receiver is currently processing an undo.
 */
- (BOOL) isUndoing
{
	return _isUndoing;
}

/**
 * Returns whether the receiver will currently register undo operations.
 */
- (BOOL) isUndoRegistrationEnabled
{
	if (_disableCount == 0)
    {
		return YES;
    }
	else
    {
		return NO;
    }
}

/**
 * Returns the maximum number of undo groupings the receiver will maintain.
 * The default value is 0 meaning the number is only limited by
 * memory availability.
 */
- (unsigned int) levelsOfUndo
{
	return _levelsOfUndo;
}

/**
 * Prepares the receiver to registers an invocation-based undo operation.
 * This method is part of the NSInvocation-based undo registration
 * as opposed to the simpler [-registerUndoWithTarget:selector:object:]
 * technique. <br />
 * You invoke this method with the target of the
 * undo action and then invoke the targets method to undo the action
 * on the return value of this invocation
 * which actually is the undo manager.
 * The runtime will then fallback to [-forwardInvocation:] to do the actual
 * registration of the invocation.
 */
- (id) prepareWithInvocationTarget: (id)target
{
	_nextTarget = target;
	return self;
}

/**
 * Performs a redo of previous undo request by taking the top grouping
 * from the redo stack and invoking them.  This method posts an
 * NSUndoManagerCheckpointNotification notification to allow the client
 * to process any pending changes before proceeding.  If there are groupings
 * on the redo stack, the top object is popped off the stack and invoked
 * within a nested [-beginUndoGrouping]/[-endUndoGrouping].  During this
 * processing, the operations registered for undo are recorded on the undo
 * stack again.<br />
 */
- (void) redo
{
	NSString *name = nil;
	
	if (_isUndoing || _isRedoing)
    {
		[NSException raise: NSInternalInconsistencyException
					format: @"redo while undoing or redoing"];
    }
	[[NSNotificationCenter defaultCenter]
	 postNotificationName: NSUndoManagerCheckpointNotification
	 object: self];
	if ([_redoStack count] > 0)
    {
		GnudoGroup	*oldGroup;
		GnudoGroup	*groupToRedo;
		
		[[NSNotificationCenter defaultCenter]
		 postNotificationName: NSUndoManagerWillRedoChangeNotification
		 object: self];
		
		groupToRedo = [[_redoStack lastObject]retain];
		[_redoStack removeLastObject];
		
		name = [NSString stringWithString: [groupToRedo actionName]];
		
		oldGroup = m_group;
/*DB?Line*/ NSLog(@"14115 %s setting _group to nil", __PRETTY_FUNCTION__) ;
		m_group = nil;
		_isRedoing = YES;
		
		[self beginUndoGrouping];
		[groupToRedo perform];
		[groupToRedo release];
		[self endUndoGrouping];
		
		_isRedoing = NO;
		m_group = oldGroup;
		
		[[_undoStack lastObject] setActionName: name];
		
		[[NSNotificationCenter defaultCenter]
		 postNotificationName: NSUndoManagerDidRedoChangeNotification
		 object: self];
    }
}

/**
 * If the receiver can perform a redo, this method returns
 * the action name previously associated with the top grouping with
 * [-setActionName:].  This name should identify the action to be redone.
 * If there are no items on the redo stack this method returns nil.
 * If no action name has been set, this method returns an empty string.
 */
- (NSString*) redoActionName
{
	if ([self canRedo] == NO)
    {
		return @"";  // JERRY was return nil ;
    }
	return [[_redoStack lastObject] actionName];
}

/**
 * Returns the full localized title of the actions to be displayed
 * as a menu item.  This method first invokes [-redoActionName] and
 * passes it to [-redoMenuTitleForUndoActionName:] and returns the result.
 */
- (NSString*) redoMenuItemTitle
{
	return [self redoMenuTitleForUndoActionName: [self redoActionName]];
}

/**
 * Returns the localized title of the actions to be displayed
 * as a menu item identified by actionName, by appending a
 * localized command string like @"Redo &lt;localized(actionName)&gt;".
 */
- (NSString*) redoMenuTitleForUndoActionName: (NSString*)actionName
{
	/*
	 * FIXME: The terms @"Redo" and @"Redo %@" should be localized.
	 * Possibly with the introduction of GSBaseLocalizedString() private
	 * the the library.
	 */
	if (actionName)
    {
		if ([actionName isEqual: @""])
		{
			return @"Redo";
		}
		else
		{
			return [NSString stringWithFormat: @"Redo %@", actionName];
		}
    }
	return actionName;
}

/**
 * Registers an undo operation.
 * This method is the simple target-action-based undo registration
 * as opposed to the sophisticated [-forwardInvocation:]
 * mechanism. <br />
 * You invoke this method with the target of the
 * undo action providing the selector which can perform the undo with
 * the provided object.  The object is often a dictionary of the
 * identifying the attribute and their values before the change. The object
 * will be retained. The invocation will added to the current grouping.<br />
 * If the registrations have been disabled through [-disableUndoRegistration],
 * this method does nothing.<br />
 * Unless the receiver implicitly
 * groups operations by event, the this method must have been preceded
 * with a [-beginUndoGrouping] message.  Otherwise it will raise an
 * NSInternalInconsistencyException. <br />
 * Unless this method is invoked as part of a [-undo] or [-undoNestedGroup]
 * processing, the redo stack is cleared.<br />
 * If the receiver [-groupsByEvent] and this is the first call to this
 * method since the last run loop processing, this method sets up
 * the receiver to process the [-endUndoGrouping] at the
 * end of the event loop.
 */
- (void) registerUndoWithTarget: (id)target
					   selector: (SEL)aSelector
						 object: (id)anObject
{
	if (_disableCount == 0)
    {
		NSMethodSignature	*sig;
		NSInvocation	*inv;
		GnudoGroup	*g;
		
		if (m_group == nil)
		{
			if ([self groupsByEvent])
			{
				[self beginUndoGrouping];
			}
			else
			{
				[NSException raise: NSInternalInconsistencyException
							format: @"registerUndo without beginUndoGrouping"];
			}
		}
		g = m_group;
		sig = [target methodSignatureForSelector: aSelector];
		inv = [NSInvocation invocationWithMethodSignature: sig];
		[inv retainArguments];
		[inv setTarget: target];
		[inv setSelector: aSelector];
		[inv setArgument: &anObject atIndex: 2];
		[g addInvocation: inv];
		if (_isUndoing == NO && _isRedoing == NO)
		{
			[_redoStack removeAllObjects];
		}
		if ((_runLoopGroupingPending == NO) && ([self groupsByEvent] == YES))
		{
			[[NSRunLoop currentRunLoop] performSelector: @selector(_loop:)
												 target: self
											   argument: nil
												  order: NSUndoCloseGroupingRunLoopOrdering
												  modes: _modes];
			_runLoopGroupingPending = YES;
		}
    }
}

/**
 * Removes all grouping stored in the receiver.  This clears the both
 * the undo and the redo stacks.  This method is if the sole client
 * of the undo manager will be unable to service any undo or redo events.
 * The client can call this method in its -dealloc method, unless the
 * undo manager has several clients, in which case
 * [-removeAllActionsWithTarget:] is more appropriate.
 */
- (void) removeAllActions
{
	[_redoStack removeAllObjects];
	[_undoStack removeAllObjects];
	_isRedoing = NO;
	_isUndoing = NO;
	_disableCount = 0;
}

/**
 * Removes all actions recorded for the given target.  This method is
 * is useful when a client of the undo manager will be unable to
 * service any undo or redo events.  Clients should call this method
 * in their dealloc method, unless they are the sole client of the
 * undo manager in which case [-removeAllActions] is more appropriate.
 */
- (void) removeAllActionsWithTarget: (id)target
{
	unsigned 	i;
	
	i = [_redoStack count];
	while (i-- > 0)
    {
		GnudoGroup	*g;
		
		g = [_redoStack objectAtIndex: i];
		if ([g removeActionsForTarget: target] == NO)
		{
			[_redoStack removeObjectAtIndex: i];
		}
    }
	i = [_undoStack count];
	while (i-- > 0)
    {
		GnudoGroup	*g;
		
		g = [_undoStack objectAtIndex: i];
		if ([g removeActionsForTarget: target] == NO)
		{
			[_undoStack removeObjectAtIndex: i];
		}
    }
}

/**
 * Returns the run loop modes in which the receiver registers
 * the [-endUndoGrouping] processing when it [-groupsByEvent].
 */
- (NSArray*) runLoopModes
{
	return _modes;
}

/**
 * Sets the name associated with the actions of the current group.
 * Typically you can call this method while registering the actions
 * for the current group.  This name will be used to determine the
 * name in the [-undoMenuTitleForUndoActionName:] and
 * [-redoMenuTitleForUndoActionName:] names typically displayed
 * in the menu.
 */
- (void) setActionName: (NSString*)name
{
	if ((name != nil) && (m_group != nil))
    {
		[m_group setActionName: name];
    }
}

/**
 * Sets whether the receiver should implicitly call [-beginUndoGrouping] when
 * necessary and register a call to invoke [-endUndoGrouping] at the end
 * of the current event loop.  The grouping is turned on by default.
 */
- (void) setGroupsByEvent: (BOOL)flag
{
	if (_groupsByEvent != flag)
    {
		_groupsByEvent = flag;
    }
}

/**
 * Sets the maximum number of groups in either the undo or redo stack.
 * Use this method to limit memory usage if you either expect very many
 * actions to be recorded or the recorded objects require a lot of memory.
 * When set to 0 the stack size is limited by the range of a unsigned int,
 * available memory.
 */
- (void) setLevelsOfUndo: (unsigned)num
{
	_levelsOfUndo = num;
	if (num > 0)
    {
		while ([_undoStack count] > num)
		{
			[_undoStack removeObjectAtIndex: 0];
		}
		while ([_redoStack count] > num)
		{
			[_redoStack removeObjectAtIndex: 0];
		}
    }
}

/**
 * Sets the modes in which the receiver registers the calls
 * with the current run loop to invoke
 * [-endUndoGrouping] when it [-groupsByEvent].  This method
 * first cancels any pending registrations in the old modes and
 * registers the invocation in the new modes.
 */
- (void) setRunLoopModes: (NSArray*)newModes
{
	if (_modes != newModes)
    {
		if (_modes != newModes) {
			[_modes release];
			_modes = [newModes retain];
		}
		
		[[NSRunLoop currentRunLoop] cancelPerformSelector: @selector(_loop:)
												   target: self
												 argument: nil];
		[[NSRunLoop currentRunLoop] performSelector: @selector(_loop:)
											 target: self
										   argument: nil
											  order: NSUndoCloseGroupingRunLoopOrdering
											  modes: _modes];
		_runLoopGroupingPending = YES;
    }
}

/**
 * This method performs an undo by invoking [-undoNestedGroup].
 * If current group of the receiver is the top group this method first
 * calls [-endUndoGrouping].  This method may only be called on the top
 * level group, otherwise it will raise an NSInternalInconsistencyException.
 */
- (void) undo
{
	if ([self groupingLevel] == 1)
    {
		[self endUndoGrouping];
    }
	if (m_group != nil)
    {
		[NSException raise: NSInternalInconsistencyException
					format: @"undo with nested groups"];
    }
	[self undoNestedGroup];
}

/**
 * If the receiver can perform an undo, this method returns
 * the action name previously associated with the top grouping with
 * [-setActionName:].  This name should identify the action to be undone.
 * If there are no items on the undo stack this method returns nil.
 * If no action name has been set, this method returns an empty string.
 */
- (NSString*) undoActionName
{
	if ([self canUndo] == NO)
    {
		return nil;
    }
	return [[_undoStack lastObject] actionName];
}

/**
 * Returns the full localized title of the actions to be displayed
 * as a menu item.  This method first invokes [-undoActionName] and
 * passes it to [-undoMenuTitleForUndoActionName:] and returns the result.
 */
- (NSString*) undoMenuItemTitle
{
	return [self undoMenuTitleForUndoActionName: [self undoActionName]];
}

/**
 * Returns the localized title of the actions to be displayed
 * as a menu item identified by actionName, by appending a
 * localized command string like @"Undo &lt;localized(actionName)&gt;".
 */
- (NSString*) undoMenuTitleForUndoActionName: (NSString*)actionName
{
	/*
	 * FIXME: The terms @"Undo" and @"Undo %@" should be localized.
	 * Possibly with the introduction of GSBaseLocalizedString() private
	 * the the library.
	 */
	if (actionName)
    {
		if ([actionName isEqual: @""])
		{
			return @"Undo";
		}
		else
		{
			return [NSString stringWithFormat: @"Undo %@", actionName];
		}
    }
	return actionName;
}

/**
 * Performs an undo by taking the top grouping
 * from the undo stack and invoking them.  This method posts an
 * NSUndoManagerCheckpointNotification notification to allow the client
 * to process any pending changes before proceeding.  If there are groupings
 * on the undo stack, the top object is popped off the stack and invoked
 * within a nested beginUndoGrouping/endUndoGrouping.  During this
 * processing, the undo operations registered for undo are recorded on the redo
 * stack.<br />
 */
- (void) undoNestedGroup
{
/*DB?Line*/ NSLog(@"25016 >> %s m_group = %@", __PRETTY_FUNCTION__, m_group) ;
/*DB?Line*/ [self logGroupLineage] ;
	
	NSString *name = nil;
	GnudoGroup	*oldGroup;
	GnudoGroup	*groupToUndo;
	
	[[NSNotificationCenter defaultCenter]
	 postNotificationName: NSUndoManagerCheckpointNotification
	 object: self];
	
	if (m_group != nil)
    {
		[NSException raise: NSInternalInconsistencyException
					format: @"undoNestedGroup before endUndoGrouping"];
    }
	
	if (_isUndoing || _isRedoing)
    {
		[NSException raise: NSInternalInconsistencyException
					format: @"undoNestedGroup while undoing or redoing"];
    }
	
	if ([_undoStack count] == 0)
    {
/*DB?Line*/ NSLog(@"25972 %s Returning cuz nothing to undo", __PRETTY_FUNCTION__) ;
		return;
    }
	
	[[NSNotificationCenter defaultCenter]
	 postNotificationName: NSUndoManagerWillUndoChangeNotification
	 object: self];
	
	oldGroup = m_group;
	m_group = nil;
	/*DB?Line*/ NSLog(@"25347 %s Set _group to nil", __PRETTY_FUNCTION__) ;
	/*DB?Line*/ [self logGroupLineage] ;
	_isUndoing = YES;
	
	if (oldGroup)
    {
		groupToUndo = oldGroup;
		oldGroup = [[oldGroup parent] retain];
		[groupToUndo orphan];
		[_redoStack addObject: groupToUndo];
    }
	else
    {
		groupToUndo = [[_undoStack lastObject] retain];
		[_undoStack removeLastObject];
    }
	
	name = [NSString stringWithString: [groupToUndo actionName]];
	
/*DB?Line*/ NSLog(@"26242 %s will beginUndoGrouping", __PRETTY_FUNCTION__) ;
	/*DB?Line*/ [self logGroupLineage] ;
	[self beginUndoGrouping];
/*DB?Line*/ NSLog(@"26269 %s did beginUndoGrouping", __PRETTY_FUNCTION__) ;
	/*DB?Line*/ [self logGroupLineage] ;
	[groupToUndo perform];
	[groupToUndo release];
/*DB?Line*/ NSLog(@"26317 %s will endUndoGrouping", __PRETTY_FUNCTION__) ;
	/*DB?Line*/ [self logGroupLineage] ;
	[self endUndoGrouping];
/*DB?Line*/ NSLog(@"26342 %s did endUndoGrouping", __PRETTY_FUNCTION__) ;
	/*DB?Line*/ [self logGroupLineage] ;
	
	_isUndoing = NO;
	m_group = oldGroup;
/*DB?Line*/ NSLog(@"26383: %s set m_group to oldGroup = %p", __PRETTY_FUNCTION__, m_group) ;
	/*DB?Line*/ [self logGroupLineage] ;
	
	[[_redoStack lastObject] setActionName: name];
	
	[[NSNotificationCenter defaultCenter]
	 postNotificationName: NSUndoManagerDidUndoChangeNotification
	 object: self];
/*DB?Line*/ NSLog(@"26532 <<%s with m_group = %@", __PRETTY_FUNCTION__, m_group) ;
	/*DB?Line*/ [self logGroupLineage] ;
}

// Methods added for Mac OS

- (void)_processEndOfEventNotification:(id)note {
}

@end
