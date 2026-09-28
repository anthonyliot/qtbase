// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
// Qt-Security score:significant reason:default

#ifndef QAPPLEFRAMERATE_P_H
#define QAPPLEFRAMERATE_P_H

//
//  W A R N I N G
//  -------------
//
// This file is not part of the Qt API.  It exists purely as an
// implementation detail.  This header file may change from version to
// version without notice, or even be removed.
//
// We mean it.
//

#include <QtGui/qtguiglobal.h>
#include <QtCore/qvariant.h>

#include <optional>

QT_BEGIN_NAMESPACE

class QDebug;
class QWindow;

// Mirrors CAFrameRateRange, but is plain C++ so that it can be shared between
// the Apple platform plugins and tested without a display.
struct Q_GUI_EXPORT QAppleFrameRateRange
{
    float minimum = 0;
    float maximum = 0;
    float preferred = 0;

    constexpr QAppleFrameRateRange() noexcept = default;
    constexpr QAppleFrameRateRange(float min, float max, float pref = 0) noexcept
        : minimum(min), maximum(max), preferred(pref)
    {
    }

    // CAFrameRateRangeDefault, meaning the system decides
    bool isDefault() const noexcept { return minimum == 0 && maximum == 0 && preferred == 0; }

    // Matches the validation done by -[CADisplayLink setPreferredFrameRateRange:],
    // which throws NSInvalidArgumentException for invalid ranges.
    bool isValid() const noexcept;

    // Accepts a number (min = max = preferred), a list of [min, max] or
    // [min, max, preferred], a map with "minimum", "maximum", and "preferred"
    // keys, or a string (see fromString). A null variant or 0 means default.
    // Returns std::nullopt for values that can't be turned into a valid range.
    static std::optional<QAppleFrameRateRange> fromVariant(const QVariant &value);

    // "60", "30,120" or "30,120,60". Empty, "0" or "default" means default.
    static std::optional<QAppleFrameRateRange> fromString(QStringView string);

    // The range for QWindow::preferredFrameRate on a display refreshing at
    // displayRate: the slowest exact rate the display supports (displayRate / n,
    // with n dividing displayRate) that is not below framesPerSecond (within 1%),
    // so that no content frame is skipped. The default range if that's every
    // refresh.
    static QAppleFrameRateRange forPreferredFrameRate(qreal framesPerSecond, qreal displayRate) noexcept;

    // The range a shared display link needs to satisfy both requests. If both
    // are exact rates the display can show, the display link runs at their
    // greatest common rate, so that both stay exact, e.g. 24 and 60 on a
    // 120 Hz display keep the display link at 120.
    QAppleFrameRateRange unitedWith(const QAppleFrameRateRange &other,
                                    qreal displayRate = 0) const noexcept;

    // The interval in seconds between frames requested by this range,
    // or 0 if the range doesn't limit the frame rate.
    double frameInterval() const noexcept;

    // Whether a frame targeting targetTimestamp should be delivered, given that
    // the previous one delivered targeted lastTargetTimestamp, and that the
    // display link fires every linkFrameInterval seconds. All times in seconds.
    bool shouldDeliverFrame(double lastTargetTimestamp, double targetTimestamp,
                            double linkFrameInterval) const noexcept;

    // The interval in seconds between the frames that shouldDeliverFrame() lets
    // through when the display link fires every linkFrameInterval seconds, i.e.
    // the frame interval the window will actually see.
    double effectiveFrameInterval(double linkFrameInterval) const noexcept;

    friend constexpr bool operator==(const QAppleFrameRateRange &a,
                                     const QAppleFrameRateRange &b) noexcept
    {
        return a.minimum == b.minimum && a.maximum == b.maximum && a.preferred == b.preferred;
    }
    friend constexpr bool operator!=(const QAppleFrameRateRange &a,
                                     const QAppleFrameRateRange &b) noexcept
    {
        return !(a == b);
    }
};

#ifndef QT_NO_DEBUG_STREAM
Q_GUI_EXPORT QDebug operator<<(QDebug debug, const QAppleFrameRateRange &range);
#endif

// Tracks a window's frame-rate preference and pacing state for a platform window.
//
// The preference comes from QWindow::preferredFrameRate, mapped to an exact rate
// of the window's display with QAppleFrameRateRange::forPreferredFrameRate(). If
// that isn't set, from the "_q_preferredFrameRateRange" QWindow property, which
// also accepts ranges, or else from the QT_APPLE_PREFERRED_FRAME_RATE_RANGE
// environment variable, a default for all windows (e.g. of unmodified
// applications). Invalid values of those two are warned about once and treated
// as default.
//
// The property and the environment variable are internal and unsupported, meant
// for experimentation. Applications should use QWindow::preferredFrameRate.
class Q_GUI_EXPORT QAppleFrameRatePreference
{
public:
    static constexpr const char *propertyName = "_q_preferredFrameRateRange";

    // Re-reads the preference of the window on a display refreshing at
    // displayRate (0 if unknown), and returns the resulting range
    QAppleFrameRateRange update(const QWindow *window, qreal displayRate);
    QAppleFrameRateRange range() const { return m_range; }

    bool shouldDeliverFrame(double targetTimestamp, double linkFrameInterval) const noexcept
    {
        return m_range.shouldDeliverFrame(m_lastTargetTimestamp, targetTimestamp,
                                          linkFrameInterval);
    }
    void frameDelivered(double targetTimestamp) noexcept
    {
        m_lastTargetTimestamp = targetTimestamp;
    }
    double effectiveFrameInterval(double linkFrameInterval) const noexcept
    {
        return m_range.effectiveFrameInterval(linkFrameInterval);
    }

    static QAppleFrameRateRange environmentDefault();

private:
    QVariant m_value;
    QAppleFrameRateRange m_requested; // parsed from m_value, or the environment default
    QAppleFrameRateRange m_range;
    double m_lastTargetTimestamp = 0;
    bool m_valueWasInvalid = false;
};

// Delivers a display link frame to the windows on a screen that are due for it,
// and works out the frame rate range the display link needs. Shared by the
// cocoa and ios platform plugins, and tested without a display.
class Q_GUI_EXPORT QAppleDisplayLinkDelivery
{
public:
    // A display link callback
    struct Frame
    {
        double targetTimestamp = 0; // when the frame is going to be displayed, in seconds
        double linkFrameInterval = 0; // the display link's current frame interval, in seconds
        qreal displayRate = 0; // the display's refresh rate, 0 if unknown
    };

    // What the platform plugin provides about a screen with a display link
    class Screen
    {
    public:
        virtual ~Screen();
        // Whether the window is on this screen, has a platform window, and
        // gets its update requests from the display link
        virtual bool updatesWithDisplayLink(const QWindow *window) const = 0;
        // Only called for windows that updatesWithDisplayLink() is true for
        virtual QAppleFrameRatePreference &frameRatePreference(const QWindow *window) = 0;
        // Delivers the window's pending update request, and returns false if
        // the platform window deferred it. May create and destroy windows.
        virtual bool deliverUpdateRequest(QWindow *window) = 0;
    };

    // Delivers the pending update requests of the windows that are due for the
    // frame, including those that get an update request while delivering to
    // another window, so that the order of the windows doesn't matter. Sets
    // QWindowPrivate::updateRequestInterval during each delivery. Returns the
    // range the display link needs for the windows that have pending update
    // requests afterwards, or std::nullopt if there are none, and the display
    // link can be paused.
    static std::optional<QAppleFrameRateRange> deliver(Screen &screen, const Frame &frame);

    // The range the display link needs for the windows that have pending
    // update requests, or std::nullopt if there are none
    static std::optional<QAppleFrameRateRange> pendingRange(Screen &screen, qreal displayRate);
};

QT_END_NAMESPACE

#endif // QAPPLEFRAMERATE_P_H
