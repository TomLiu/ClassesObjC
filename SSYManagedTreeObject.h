#import <Cocoa/Cocoa.h>
#import "SSYManagedObject.h"
#import "SSYIndexee.h"

extern NSString* const constKeyChildren ;
extern NSString* const constKeyIndex ;
extern NSString* const constKeyParent ;

/*!
 @brief    A subclass of SSYManagedObject which has 'parent'
 'children' and 'index' properties, so that it can be used as
 a node in a tree.

 @details  I could put more stuff from the Stark class in here.
 Examples: recursivelyPerformSelector:... et al, moveToBkmxParent... et al
*/
@interface SSYManagedTreeObject : SSYManagedObject <SSYIndexee> {
}

@property (retain) NSSet* children ;

- (int)numberOfChildren ;
- (SSYManagedTreeObject*)childAtIndex:(int)index ;
- (NSArray*)childrenOrdered ;

@property (retain) SSYManagedTreeObject* parent ;

/*!
 @brief    Removes all children from the receiver
 
 @details  I'm not sure if the implementation used could be made more efficient
 */
- (void)removeAllChildren ;

/*!
 @brief    Sets the value in the ivar index
 */
- (void)setIndexValue:(NSInteger)index ;

- (int)indexValue ;


@end
