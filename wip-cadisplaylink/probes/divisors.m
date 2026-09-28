// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: BSD-3-Clause
//
// Measures the callback rate of an NSScreen CADisplayLink for rate = max / n,
// to find which rates CoreAnimation supports exactly.
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <initializer_list>
@interface Counter : NSObject
@property int count;
- (void)tick:(CADisplayLink *)link;
@end
@implementation Counter
- (void)tick:(CADisplayLink *)link { self.count++; }
@end
int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSScreen *screen = NSScreen.mainScreen;
        const double max = screen.maximumFramesPerSecond;
        printf("screen max %g fps\n", max);
        for (int n : std::initializer_list<int>{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 20, 24}) {
            Counter *c = [Counter new];
            CADisplayLink *link = [screen displayLinkWithTarget:c selector:@selector(tick:)];
            const float rate = max / n;
            link.preferredFrameRateRange = CAFrameRateRangeMake(rate, rate, rate);
            [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
            c.count = 0;
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];
            printf("n=%2d requested %7.3f got %6.1f/s\n", n, rate, c.count / 2.0);
            [link invalidate];
        }
    }
}
