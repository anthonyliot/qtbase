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
    QVideoWindow window;
    window.resize(320, 240);
    window.setFlag(Qt::WindowStaysOnTopHint);
    window.show();
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
    // viewprobe <file> <seconds>: just play, and print the frames, the preferred frame
    // rate and the screen every second, e.g. while moving the window to another display
    if (argc > 2) {
        for (int second = 0; second < std::atoi(argv[2]); ++second) {
            const int frames = count(1000);
            std::printf("%3d s: %d frames, preferredFrameRate %.3f, screen %s (%.3f Hz)\n", second,
                        frames, window.preferredFrameRate(),
                        qPrintable(window.screen()->name()), window.screen()->refreshRate());
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
