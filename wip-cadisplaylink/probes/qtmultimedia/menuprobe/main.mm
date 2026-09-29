// Probe: does video keep coming while a real menu is open, and in a modal session?
// Plays <file> in a loop, then counts the frames delivered during 1 s of an NSMenu's tracking
// loop, 1 s of an application-modal session, and 1 s of the normal event loop. MRC.
#include <QtGui/qguiapplication.h>
#include <QtMultimedia/qmediaplayer.h>
#include <QtMultimedia/qvideosink.h>
#include <QtMultimedia/qvideoframe.h>
#include <QtCore/qtimer.h>
#include <QtCore/qeventloop.h>
#include <QtCore/qurl.h>
#import <AppKit/AppKit.h>
#include <cstdio>

static int frames = 0;

static void spin(int ms) { QEventLoop loop; QTimer::singleShot(ms, &loop, &QEventLoop::quit); loop.exec(); }

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    QMediaPlayer player;
    QVideoSink sink;
    player.setVideoSink(&sink);
    // Counted on the main thread (the sink's), whichever thread the backend emits from
    QObject::connect(&sink, &QVideoSink::videoFrameChanged, &sink, [](const QVideoFrame &frame) {
        if (frame.isValid())
            ++frames;
    });
    player.setSource(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    player.setLoops(QMediaPlayer::Infinite);
    player.play();
    spin(1500);

    // A real menu: popUpMenuPositioningItem runs AppKit's menu tracking loop until cancelled
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"probe"];
    [menu addItemWithTitle:@"Video probe" action:nil keyEquivalent:@""];
    NSTimer *cancel = [NSTimer timerWithTimeInterval:1.0 repeats:NO block:^(NSTimer *) { [menu cancelTracking]; }];
    [NSRunLoop.currentRunLoop addTimer:cancel forMode:NSRunLoopCommonModes];
    int before = frames;
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(300, 300) inView:nil];
    const int inMenu = frames - before;

    // An application-modal session, as QDialog::exec() starts one
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(300, 300, 240, 80)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered defer:NO];
    NSTimer *stop = [NSTimer timerWithTimeInterval:1.0 repeats:NO block:^(NSTimer *) { [NSApp stopModal]; }];
    [NSRunLoop.currentRunLoop addTimer:stop forMode:NSRunLoopCommonModes];
    before = frames;
    [NSApp runModalForWindow:window];
    const int inModal = frames - before;
    [window orderOut:nil];

    before = frames;
    spin(1000);
    printf("frames in 1 s: menu open %d, modal session %d, normal %d\n", inMenu, inModal, frames - before);
    return 0;
}
