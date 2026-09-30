// Probe: does the AVFoundation backend's frame polling follow the video window's view?
#include <QtGui/qguiapplication.h>
#include <QtGui/qscreen.h>
#include <QtMultimedia/qmediaplayer.h>
#include <QtMultimedia/qvideosink.h>
#include <QtMultimedia/private/qvideowindow_p.h>
#include <QtCore/qtimer.h>
#include <QtCore/qeventloop.h>
#include <QtCore/qurl.h>
#include <cstdio>
#include <cstdlib>

static int frames = 0;
static void spin(int ms) { QEventLoop l; QTimer::singleShot(ms, &l, &QEventLoop::quit); l.exec(); }
static int count(int ms) { const int before = frames; spin(ms); return frames - before; }

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    // Declared first, as it's the video window's parent in child mode, and deletes its children
    QWindow parent;
    QVideoWindow window;
    window.resize(320, 240);
    // viewprobe <file> <seconds> <rate> full: full screen, in a space of its own, so that only
    // the video updates the display while measuring its refresh rate. Not with
    // WindowStaysOnTopHint: that's a panel's window level, which doesn't get a space.
    // viewprobe <file> <seconds> <rate> child: the video window as a child of a full screen
    // window, like QVideoWidget's, which the window server composites
    const bool fullScreen = argc > 4 && qstrcmp(argv[4], "full") == 0;
    const bool child = argc > 4 && qstrcmp(argv[4], "child") == 0;
    if (fullScreen) {
        window.showFullScreen();
    } else if (child) {
        parent.showFullScreen();
        window.setParent(&parent);
        window.setGeometry(100, 100, 960, 540);
        window.show();
    } else {
        window.setFlag(Qt::WindowStaysOnTopHint);
        window.show();
    }
    // viewprobe <file> <seconds> <rate>: another preference (0 for none), set before playing,
    // which the window leaves alone. 120 on a 120 Hz display is the default range, as without one.
    if (argc > 3)
        window.setPreferredFrameRate(std::atof(argv[3]));
    QMediaPlayer player;
    player.setVideoOutput(&window);
    player.setLoops(QMediaPlayer::Infinite);
    // Counted on the main thread, whichever thread the backend emits from
    QObject::connect(window.videoSink(), &QVideoSink::videoFrameChanged, &window, [](const QVideoFrame &f) {
        if (f.isValid()) ++frames;
    });
    player.setSource(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    player.play();
    spin(1500);
    if (fullScreen || child) {
        const QWindow &top = child ? parent : window;
        const QRect geometry = top.geometry(), screenGeometry = top.screen()->geometry();
        std::printf("window: full screen %s, %dx%d on a %dx%d screen%s\n",
                    top.windowStates() & Qt::WindowFullScreen ? "yes" : "no", geometry.width(),
                    geometry.height(), screenGeometry.width(), screenGeometry.height(),
                    child ? ", the video in a child window" : "");
    }
    // viewprobe <file> <seconds>: just play, and print the frames, the preferred frame
    // rate, the screen and whether the window is exposed every second, e.g. while moving the
    // window to another display (a window that isn't exposed requests no updates)
    if (argc > 2) {
        for (int second = 0; second < std::atoi(argv[2]); ++second) {
            const int frames = count(1000);
            std::printf("%3d s: %d frames, preferredFrameRate %.3f, screen %s (%.3f Hz), %s\n",
                        second, frames, window.preferredFrameRate(),
                        qPrintable(window.screen()->name()), window.screen()->refreshRate(),
                        window.isExposed() ? "exposed" : "NOT EXPOSED");
            std::fflush(stdout);
        }
        return 0;
    }
    std::printf("shown:        %d frames in 1 s, preferredFrameRate %.3f\n", count(1000), window.preferredFrameRate());
    window.hide();
    spin(300);
    std::printf("hidden:       %d frames in 1 s\n", count(1000));
    window.show();
    spin(500);
    std::printf("shown again:  %d frames in 1 s\n", count(1000));
    return 0;
}
