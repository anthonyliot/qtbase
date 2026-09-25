// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

// Probe AppKit CADisplayLink behaviour relevant to the Qt port.
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

@interface Counter : NSObject
@property int count;
@property BOOL mainThread;
@property CFTimeInterval first, last;
@property CFTimeInterval lastDuration;
- (void)tick:(CADisplayLink *)l;
@end
@implementation Counter
- (void)tick:(CADisplayLink *)l
{
    if (!self.count)
        self.first = l.timestamp;
    self.last = l.timestamp;
    self.lastDuration = l.targetTimestamp - l.timestamp;
    self.count++;
    self.mainThread = NSThread.isMainThread;
}
@end

static void spin(double s)
{
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]];
}

static void measure(NSString *label, CADisplayLink *l, Counter *c, double secs)
{
    c.count = 0;
    spin(secs);
    printf("%-44s callbacks/s=%6.1f main=%d interval(target-ts)=%.2fms\n", label.UTF8String,
           c.count / secs, c.mainThread, c.lastDuration * 1000);
}

int main()
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        NSScreen *screen = NSScreen.mainScreen;
        printf("screen maxFPS=%ld minRefreshInterval=%.3fms maxRefreshInterval=%.3fms\n",
               (long)screen.maximumFramesPerSecond, screen.minimumRefreshInterval * 1000,
               screen.maximumRefreshInterval * 1000);

        Counter *sc = [Counter new];
        CADisplayLink *sl = [screen displayLinkWithTarget:sc selector:@selector(tick:)];
        [sl addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        measure(@"screen link default", sl, sc, 1);
        for (float fps : (float[]){ 30, 60, 120, 24, 48, 100 }) {
            sl.preferredFrameRateRange = CAFrameRateRangeMake(fps, fps, fps);
            measure([NSString stringWithFormat:@"screen link range(%g,%g,%g)", fps, fps, fps], sl,
                    sc, 1);
        }
        sl.preferredFrameRateRange = CAFrameRateRangeMake(10, 60, 60);
        measure(@"screen link range(10,60,60)", sl, sc, 1);
        sl.preferredFrameRateRange = CAFrameRateRangeMake(1, 60, 30);
        measure(@"screen link range(1,60,30)", sl, sc, 1);
        sl.preferredFrameRateRange = CAFrameRateRangeDefault;
        sl.paused = YES;
        measure(@"screen link paused", sl, sc, 0.5);
        sl.paused = NO;
        measure(@"screen link unpaused", sl, sc, 0.5);
        [sl invalidate];

        // View-based link
        NSView *orphan = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        Counter *vc = [Counter new];
        CADisplayLink *vl = [orphan displayLinkWithTarget:vc selector:@selector(tick:)];
        [vl addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        measure(@"view link, view not in window", vl, vc, 0.5);

        NSWindow *w = [[NSWindow alloc]
                initWithContentRect:NSMakeRect(100, 100, 300, 300)
                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskMiniaturizable
                            backing:NSBackingStoreBuffered
                              defer:NO];
        w.releasedWhenClosed = NO;
        w.contentView = orphan;
        measure(@"view link, window created not shown", vl, vc, 0.5);
        [w makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        measure(@"view link, window visible", vl, vc, 1);
        vl.preferredFrameRateRange = CAFrameRateRangeMake(30, 30, 30);
        measure(@"view link, window visible range 30", vl, vc, 1);
        vl.preferredFrameRateRange = CAFrameRateRangeDefault;
        [w orderOut:nil];
        measure(@"view link, window ordered out", vl, vc, 1);
        [w orderFront:nil];
        spin(0.2);
        [w miniaturize:nil];
        spin(1.0);
        measure(@"view link, window miniaturized", vl, vc, 1);
        [w deminiaturize:nil];
        spin(1.0);
        measure(@"view link, window deminiaturized", vl, vc, 1);

        // Two links on same screen with different ranges
        Counter *a = [Counter new], *b = [Counter new];
        CADisplayLink *la = [screen displayLinkWithTarget:a selector:@selector(tick:)];
        CADisplayLink *lb = [screen displayLinkWithTarget:b selector:@selector(tick:)];
        la.preferredFrameRateRange = CAFrameRateRangeMake(30, 30, 30);
        [la addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        [lb addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        a.count = b.count = 0;
        spin(1);
        printf("two links (30 / default): a=%d b=%d\n", a.count, b.count);
        [la invalidate];
        [lb invalidate];
        [vl invalidate];
    }
}
