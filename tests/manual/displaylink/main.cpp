// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

// Manual test for update request pacing and per-window frame-rate preferences.
//
// Each window animates by requesting updates continuously, and shows the rate
// at which it gets them, next to the refresh rate of its screen. Use the keys
// to change the window's preferred frame rate (through the private
// _q_preferredFrameRateRange property), or open more windows to check that
// windows with different preferences don't affect each other.
//
// Things to check:
//  - Default: rate matches the screen refresh rate (e.g. 240 on a 240 Hz display)
//  - Presets: rate matches the preset, and the motion is smooth
//  - Several windows with different presets each get their own rate
//  - Space pauses: the display link should stop (see qt.qpa.screen.updates logging)
//  - Live resize, moving between screens, minimize/restore keep animating
//  - Instruments > Animation Hitches / Display: the display actually lowers its
//    refresh rate when all animating windows ask for less
//
// For automated runs:
//   --log              print updates/s, refresh rate and size every 250 ms
//   --preset <n>       start with preset n
//   --rate <fps>       set QWindow::preferredFrameRate (the public API) instead
//   --position <x,y>   initial window position
//   --pause-after <s>  stop animating after s seconds (to measure idle cost)
//   --quit-after <s>   quit after s seconds
//   --busy-ms <ms>     spend ms milliseconds of CPU time per frame, like a heavy renderer
//   --on-top           keep the window above others, so it isn't occluded (occluded
//                      windows are not exposed, and stop painting)
//   --trace            at exit, print the last update request, expose and paint events,
//                      with the window's exposure and pending update request state

#include <QtGui/QGuiApplication>
#include <QtGui/QKeyEvent>
#include <QtGui/QPainter>
#include <QtGui/QRasterWindow>
#include <QtGui/QScreen>
#include <qpa/qplatformwindow.h>
#include <QtCore/QStringList>
#include <QtCore/QCommandLineParser>
#include <QtCore/QElapsedTimer>
#include <QtCore/QTimer>
#include <QtCore/QList>
#include <QtCore/QVariant>

#include <cmath>
#include <cstdio>
#include <deque>
#include <utility>

using namespace Qt::StringLiterals;

struct Preset
{
    QString name;
    QVariant value;
};

static const QList<Preset> presets = {
    { u"default"_s, QVariant() },
    { u"24"_s, 24 },
    { u"30"_s, 30 },
    { u"48"_s, 48 },
    { u"60"_s, 60 },
    { u"120"_s, 120 },
    { u"240"_s, 240 },
    { u"30-120, preferred 60"_s, QVariantList{ 30, 120, 60 } },
    { u"invalid (-1)"_s, -1 },
};

class AnimationWindow : public QRasterWindow
{
public:
    explicit AnimationWindow(int presetIndex = 0)
    {
        setPreset(presetIndex);
        resize(640, 360);
        m_clock.start();
    }

    double updateRate() const
    {
        return m_frameTimes.size() > 1
                ? (m_frameTimes.size() - 1) * 1e9 / (m_frameTimes.back() - m_frameTimes.front())
                : 0;
    }

    void setAnimating(bool animating)
    {
        m_animating = animating;
        m_frameTimes.clear();
        update();
    }

    void setBusyTime(int ms) { m_busyMs = ms; }
    int takeFrameCount() { return std::exchange(m_frameCount, 0); }
    QString takeEventCounts()
    {
        const QString counts =
                u"updreq=%1 expose=%2 unexposed=%3 lostupdates=%4"_s.arg(m_updateRequests)
                        .arg(m_exposes)
                        .arg(m_unexposes)
                        .arg(m_lostUpdates);
        m_updateRequests = m_exposes = m_unexposes = m_lostUpdates = 0;
        return counts;
    }

    void setPreset(int index)
    {
        m_preset = index;
        setProperty("_q_preferredFrameRateRange", presets.at(index).value);
        setTitle(u"Display link test - %1"_s.arg(presets.at(index).name));
        m_frameTimes.clear();
    }

    // Recent events, for --trace
    bool tracing = false;
    QStringList trace;

    void note(const char *what)
    {
        if (!tracing)
            return;
        if (!m_traceClock.isValid())
            m_traceClock.start();
        const bool pending = handle() && handle()->hasPendingUpdateRequest();
        trace.append(QString::asprintf("%8.3f %-22s exposed=%d pending=%d",
                                       m_traceClock.nsecsElapsed() / 1e9, what, isExposed(), pending));
        if (trace.size() > 60)
            trace.removeFirst();
    }

protected:
    bool event(QEvent *event) override
    {
        if (event->type() == QEvent::UpdateRequest)
            note("UpdateRequest");
        else if (event->type() == QEvent::Expose)
            note("Expose");
        else if (event->type() == QEvent::Paint)
            note("Paint(event)");
        if (event->type() == QEvent::UpdateRequest)
            ++m_updateRequests;
        else if (event->type() == QEvent::Expose)
            isExposed() ? ++m_exposes : ++m_unexposes;
        return QRasterWindow::event(event);
    }

    void paintEvent(QPaintEvent *) override
    {
        const qint64 now = m_clock.nsecsElapsed();
        ++m_frameCount;
        m_frameTimes.push_back(now);
        while (!m_frameTimes.empty() && now - m_frameTimes.front() > 1'000'000'000)
            m_frameTimes.pop_front();

        QPainter p(this);
        const QRect bounds(QPoint(), size());
        p.fillRect(bounds, QColor(24, 24, 28));

        // A bar moving at constant speed, which makes judder easy to spot
        const double t = now / 1e9;
        const double phase = std::fmod(t * 0.5, 1.0);
        const int barWidth = 40;
        const int x = int(phase * (width() + barWidth)) - barWidth;
        p.fillRect(QRect(x, height() / 2, barWidth, height() / 2), QColor(80, 160, 255));

        const double rate = updateRate();

        p.setPen(Qt::white);
        QFont font = p.font();
        font.setPixelSize(20);
        p.setFont(font);
        const QString text = u"Updates: %1/s\nScreen: %2 (%3 Hz)\nPreference: %4\n\n"
                             "0-8: preset   n: new window   space: pause"_s.arg(rate, 0, 'f', 1)
                                     .arg(screen()->name())
                                     .arg(screen()->refreshRate(), 0, 'f', 1)
                                     .arg(presets.at(m_preset).name);
        p.drawText(bounds.adjusted(16, 16, -16, -16), Qt::AlignLeft | Qt::AlignTop, text);

        if (m_busyMs > 0) {
            QElapsedTimer busy;
            busy.start();
            while (busy.elapsed() < m_busyMs) { }
        }

        if (m_animating) {
            // QPaintDeviceWindow::update() doesn't request an update when not exposed
            if (!isExposed())
                ++m_lostUpdates;
            note("paint:before update()");
            update();
            note("paint:after update()");
        }
    }

    void keyPressEvent(QKeyEvent *event) override
    {
        const int key = event->key();
        if (key >= Qt::Key_0 && key < Qt::Key_0 + presets.size()) {
            setPreset(key - Qt::Key_0);
        } else if (key == Qt::Key_N) {
            auto *window = new AnimationWindow((m_preset + 1) % presets.size());
            window->setPosition(position() + QPoint(40, 40));
            window->show();
        } else if (key == Qt::Key_Space) {
            setAnimating(!m_animating);
        }
        update();
    }

private:
    QElapsedTimer m_clock;
    std::deque<qint64> m_frameTimes;
    int m_preset = 0;
    int m_busyMs = 0;
    int m_frameCount = 0;
    QElapsedTimer m_traceClock;
    int m_updateRequests = 0;
    int m_exposes = 0;
    int m_unexposes = 0;
    int m_lostUpdates = 0;
    bool m_animating = true;
};

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);

    QCommandLineParser parser;
    parser.addHelpOption();
    const QCommandLineOption logOption(u"log"_s, u"Print stats every 250 ms."_s);
    const QCommandLineOption presetOption(u"preset"_s, u"Initial preset."_s, u"n"_s, u"0"_s);
    const QCommandLineOption positionOption(u"position"_s, u"Window position."_s, u"x,y"_s);
    const QCommandLineOption pauseOption(u"pause-after"_s, u"Stop animating after s seconds."_s,
                                         u"s"_s);
    const QCommandLineOption quitOption(u"quit-after"_s, u"Quit after s seconds."_s, u"s"_s);
    const QCommandLineOption busyOption(u"busy-ms"_s, u"CPU time per frame."_s, u"ms"_s, u"0"_s);
    const QCommandLineOption onTopOption(u"on-top"_s, u"Keep the window above others."_s);
    const QCommandLineOption traceOption(u"trace"_s, u"Print recent update events at exit."_s);
    const QCommandLineOption rateOption(u"rate"_s, u"QWindow::preferredFrameRate."_s, u"fps"_s);
    parser.addOptions({ logOption, presetOption, positionOption, pauseOption, quitOption,
                        busyOption, onTopOption, traceOption, rateOption });
    parser.process(app);

    AnimationWindow window(parser.value(presetOption).toInt() % presets.size());
    window.setBusyTime(parser.value(busyOption).toInt());
    if (parser.isSet(onTopOption))
        window.setFlag(Qt::WindowStaysOnTopHint);
    window.tracing = parser.isSet(traceOption);
    if (parser.isSet(rateOption))
        window.setPreferredFrameRate(parser.value(rateOption).toDouble());
    if (parser.isSet(positionOption)) {
        const QStringList xy = parser.value(positionOption).split(u',');
        if (xy.size() == 2)
            window.setPosition(xy.at(0).toInt(), xy.at(1).toInt());
    }
    window.show();

    if (parser.isSet(logOption)) {
        auto *logTimer = new QTimer(&app);
        QElapsedTimer sinceStart;
        sinceStart.start();
        QObject::connect(logTimer, &QTimer::timeout, &app, [&window, sinceStart] {
            std::printf("t=%.2f rate=%.1f frames=%d refresh=%.1f size=%dx%d exposed=%d %s\n",
                        sinceStart.elapsed() / 1000.0, window.updateRate(), window.takeFrameCount(),
                        window.screen()->refreshRate(), window.width(), window.height(),
                        window.isExposed(), qPrintable(window.takeEventCounts()));
            std::fflush(stdout);
        });
        logTimer->start(250);
    }
    if (parser.isSet(pauseOption)) {
        QTimer::singleShot(int(parser.value(pauseOption).toDouble() * 1000), &window,
                           [&window] { window.setAnimating(false); });
    }
    if (parser.isSet(quitOption)) {
        QTimer::singleShot(int(parser.value(quitOption).toDouble() * 1000), &app,
                           &QCoreApplication::quit);
    }

    const int rc = app.exec();
    for (const QString &line : std::as_const(window.trace))
        std::fprintf(stderr, "TRACE %s\n", qPrintable(line));
    return rc;
}
