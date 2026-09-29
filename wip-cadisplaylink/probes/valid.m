// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
@interface T : NSObject
- (void)t:(id)s;
@end
@implementation T
- (void)t:(id)s
{
}
@end
int main()
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        CADisplayLink *l = [NSScreen.mainScreen displayLinkWithTarget:[T new]
                                                             selector:@selector(t:)];
        float c[][3] = { { 0, 0, 0 },          { 0, 0, 30 },      { 0, 60, 30 },   { 30, 0, 0 },
                         { 30, 60, 0 },        { 30, 30, 30 },    { 10, 60, 0 },   { 10, 60, 5 },
                         { 10, 60, 70 },       { 60, 30, 30 },    { 1, 240, 240 }, { 0.5, 60, 60 },
                         { 1000, 1000, 1000 }, { 240, 480, 480 }, { -1, 60, 60 },  { NAN, 60, 60 },
                         { 10, INFINITY, 60 }, { 10, 60, NAN } };
        for (auto &r : c) {
            @try {
                l.preferredFrameRateRange = CAFrameRateRangeMake(r[0], r[1], r[2]);
                CAFrameRateRange g = l.preferredFrameRateRange;
                printf("ok   (%g,%g,%g) -> (%g,%g,%g)\n", r[0], r[1], r[2], g.minimum, g.maximum,
                       g.preferred);
            } @catch (NSException *e) {
                printf("THROW(%g,%g,%g)\n", r[0], r[1], r[2]);
            }
        }
        printf("isValid? default=%d\n",
               CAFrameRateRangeIsEqualToRange(CAFrameRateRangeDefault,
                                              CAFrameRateRangeMake(0, 0, 0)));
    }
}
