// Does a CADisplayLink made by -[NSScreen displayLinkWithTarget:selector:] retain its target?
// Built without ARC, like the Qt code.
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
static int deallocs = 0;
@interface Target : NSObject
- (void)tick:(CADisplayLink *)link;
@end
@implementation Target
- (void)tick:(CADisplayLink *)link { (void)link; }
- (void)dealloc { ++deallocs; [super dealloc]; }
@end
int main()
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        // Same ownership as AVFDisplayLink: the owner holds the target, the target retains the link.
        Target *target = [[Target alloc] init];
        CADisplayLink *link = [[NSScreen.mainScreen displayLinkWithTarget:target
                                                                 selector:@selector(tick:)] retain];
        NSLog(@"target retain count after creating the link: %lu", (unsigned long)[target retainCount]);
        [link addToRunLoop:NSRunLoop.currentRunLoop forMode:NSDefaultRunLoopMode];
        [link removeFromRunLoop:NSRunLoop.currentRunLoop forMode:NSDefaultRunLoopMode];
        [target release]; // what ~AVFDisplayLink does
        NSLog(@"after releasing the target: deallocs=%d (0 = kept alive by the link)", deallocs);
        [link invalidate];
        NSLog(@"after invalidating the link: deallocs=%d", deallocs);
        [link release];
    }
    NSLog(@"end: deallocs=%d", deallocs);
    return 0;
}
