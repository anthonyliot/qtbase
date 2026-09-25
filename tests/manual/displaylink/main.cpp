// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

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

#include <QtGui/QGuiApplication>
#include <QtGui/QKeyEvent>
#include <QtGui/QPainter>
#include <QtGui/QRasterWindow>
#include <QtGui/QScreen>
#include <QtCore/QElapsedTimer>
#include <QtCore/QList>
#include <QtCore/QVariant>

#include <cmath>
#include <deque>

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

protected:
    void paintEvent(QPaintEvent *) override
    {
        const qint64 now = m_clock.nsecsElapsed();
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

        const double rate = m_frameTimes.size() > 1
                ? (m_frameTimes.size() - 1) * 1e9 / (m_frameTimes.back() - m_frameTimes.front())
                : 0;

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

        if (m_animating)
            update();
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
            m_animating = !m_animating;
            m_frameTimes.clear();
        }
        update();
    }

private:
    void setPreset(int index)
    {
        m_preset = index;
        setProperty("_q_preferredFrameRateRange", presets.at(index).value);
        setTitle(u"Display link test - %1"_s.arg(presets.at(index).name));
        m_frameTimes.clear();
    }

    QElapsedTimer m_clock;
    std::deque<qint64> m_frameTimes;
    int m_preset = 0;
    bool m_animating = true;
};

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);

    AnimationWindow window;
    window.show();

    return app.exec();
}
