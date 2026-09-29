// What AppKit reports about each display's refresh rate range (no Qt)
#import <AppKit/AppKit.h>
int main()
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        for (NSScreen *screen in NSScreen.screens) {
            printf("%s: max %ld fps, refresh interval min %.6f s, max %.6f s -> %s\n",
                   screen.localizedName.UTF8String, (long)screen.maximumFramesPerSecond,
                   screen.minimumRefreshInterval, screen.maximumRefreshInterval,
                   screen.maximumRefreshInterval > screen.minimumRefreshInterval ? "variable" : "fixed");
        }
    }
    return 0;
}
