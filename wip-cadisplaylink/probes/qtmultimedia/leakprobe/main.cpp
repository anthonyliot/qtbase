// Probe: are AVFDisplayLink's observer and CADisplayLink freed with the media player?
// Plays <file> in <n> players one after the other, each until its first frame, destroys
// them, then idles so that heap(1) can count the live objects.
#include <QtGui/qguiapplication.h>
#include <QtMultimedia/qmediaplayer.h>
#include <QtMultimedia/qvideosink.h>
#include <QtMultimedia/qvideoframe.h>
#include <QtCore/qtimer.h>
#include <QtCore/qeventloop.h>
#include <QtCore/qurl.h>
#include <cstdio>
#include <memory>
#include <unistd.h>

// Like an event loop iteration of an application, drain what each player autoreleased
extern "C" void *objc_autoreleasePoolPush(void);
extern "C" void objc_autoreleasePoolPop(void *);

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    const QUrl url = QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1]));
    const int n = atoi(argv[2]);
    int shown = 0;
    const bool pools = argc > 3;
    for (int i = 0; i < n; ++i) {
        void *pool = pools ? objc_autoreleasePoolPush() : nullptr;
        auto player = std::make_unique<QMediaPlayer>();
        auto sink = std::make_unique<QVideoSink>();
        player->setVideoSink(sink.get());
        QEventLoop loop;
        QObject::connect(sink.get(), &QVideoSink::videoFrameChanged, &loop, [&](const QVideoFrame &f) {
            if (f.isValid()) { ++shown; loop.quit(); }
        });
        QTimer::singleShot(3000, &loop, &QEventLoop::quit);
        player->setSource(url);
        player->play();
        loop.exec();
        player.reset();
        sink.reset();
        if (pool)
            objc_autoreleasePoolPop(pool);
    }
    QEventLoop settle; QTimer::singleShot(500, &settle, &QEventLoop::quit); settle.exec();
    printf("ready pid=%d players=%d with-a-frame=%d\n", getpid(), n, shown);
    fflush(stdout);
    QEventLoop idle; QTimer::singleShot(20000, &idle, &QEventLoop::quit); idle.exec();
    return 0;
}
