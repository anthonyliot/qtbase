// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
// Qt-Security score:significant reason:default

#include "qappleframerate_p.h"

#include <QtCore/qdebug.h>
#include <QtCore/qhash.h>
#include <QtCore/qloggingcategory.h>
#include <QtCore/qmap.h>
#include <QtCore/qstringlist.h>
#include <QtCore/qvarlengtharray.h>
#include <QtCore/qpointer.h>
#include <QtGui/qguiapplication.h>
#include <QtGui/qwindow.h>
#include <QtGui/private/qwindow_p.h>

#include <algorithm>
#include <cmath>
#include <numeric>

QT_BEGIN_NAMESPACE

Q_STATIC_LOGGING_CATEGORY(lcFrameRate, "qt.qpa.framerate", QtWarningMsg)

bool QAppleFrameRateRange::isValid() const noexcept
{
    if (isDefault())
        return true;
    if (std::isnan(minimum) || std::isnan(maximum) || std::isnan(preferred))
        return false;
    if (!(minimum > 0) || !std::isfinite(minimum) || maximum < minimum)
        return false;
    return preferred == 0 || (preferred >= minimum && preferred <= maximum);
}

std::optional<QAppleFrameRateRange> QAppleFrameRateRange::fromString(QStringView string)
{
    string = string.trimmed();
    if (string.isEmpty() || string.compare(u"default", Qt::CaseInsensitive) == 0)
        return QAppleFrameRateRange();

    QVarLengthArray<float, 3> values;
    for (QStringView part : string.tokenize(u',')) {
        bool ok = false;
        const float value = part.trimmed().toFloat(&ok);
        if (!ok || values.size() == 3)
            return std::nullopt;
        values.append(value);
    }

    QAppleFrameRateRange range;
    switch (values.size()) {
    case 1:
        if (values[0] == 0)
            return QAppleFrameRateRange();
        range = QAppleFrameRateRange(values[0], values[0], values[0]);
        break;
    case 2:
        range = QAppleFrameRateRange(values[0], values[1]);
        break;
    case 3:
        range = QAppleFrameRateRange(values[0], values[1], values[2]);
        break;
    default:
        return std::nullopt;
    }

    if (!range.isValid())
        return std::nullopt;
    return range;
}

std::optional<QAppleFrameRateRange> QAppleFrameRateRange::fromVariant(const QVariant &value)
{
    if (!value.isValid() || value.isNull())
        return QAppleFrameRateRange();

    auto fromNumbers = [](const QVariantList &list) -> std::optional<QAppleFrameRateRange> {
        QStringList parts;
        for (const QVariant &v : list) {
            bool ok = false;
            const double d = v.toDouble(&ok);
            if (!ok)
                return std::nullopt;
            parts.append(QString::number(d, 'g', 9));
        }
        if (parts.isEmpty())
            return std::nullopt;
        return fromString(parts.join(u','));
    };

    switch (value.typeId()) {
    case QMetaType::QString:
    case QMetaType::QByteArray:
        return fromString(value.toString());
    case QMetaType::QVariantMap:
    case QMetaType::QVariantHash: {
        const QVariantMap map = value.toMap();
        const auto number = [&map](const char *key, bool *present) -> std::optional<float> {
            const auto it = map.constFind(QLatin1StringView(key));
            *present = it != map.constEnd();
            if (!*present)
                return 0.0f;
            bool ok = false;
            const float f = it->toFloat(&ok);
            if (!ok)
                return std::nullopt;
            return f;
        };
        bool hasMinimum, hasMaximum, hasPreferred;
        const auto minimum = number("minimum", &hasMinimum);
        const auto maximum = number("maximum", &hasMaximum);
        const auto preferred = number("preferred", &hasPreferred);
        if (!minimum || !maximum || !preferred)
            return std::nullopt;
        if (map.size() != int(hasMinimum) + int(hasMaximum) + int(hasPreferred))
            return std::nullopt; // Unknown keys, most likely a typo
        if (!hasMinimum && !hasMaximum && hasPreferred)
            return fromNumbers({ *preferred });
        const QAppleFrameRateRange range(*minimum, *maximum, *preferred);
        if (!range.isValid())
            return std::nullopt;
        return range;
    }
    case QMetaType::QVariantList:
    case QMetaType::QStringList:
        return fromNumbers(value.toList());
    default:
        break;
    }

    // Numbers, and types such as QJSValue that convert to one of the above
    if (value.canConvert<double>() && !value.canConvert<QVariantList>()) {
        bool ok = false;
        const double d = value.toDouble(&ok);
        if (ok)
            return fromNumbers({ d });
    }
    if (value.canConvert<QVariantList>()) {
        if (const QVariantList list = value.toList(); !list.isEmpty())
            return fromNumbers(list);
    }
    if (value.canConvert<QVariantMap>()) {
        if (const QVariantMap map = value.toMap(); !map.isEmpty())
            return fromVariant(map);
    }
    return std::nullopt;
}

// The display's refresh rate in whole frames per second, e.g. 120 for a 120 Hz
// display. CoreAnimation only runs display links at rates that divide it
// evenly and are whole numbers themselves: 240 / 9 = 26.67 on a 240 Hz display
// gives 30, and 240 / 7 = 34.29 gives 40. 0 if unknown.
static int wholeDisplayRate(qreal displayRate)
{
    return displayRate >= 1 && displayRate < 1e6 ? qRound(displayRate) : 0;
}

// The number of display refreshes per frame if the range is an exact rate the
// display can show (its refresh rate divided by a divisor of it), or 0.
static int exactFramesPerDelivery(const QAppleFrameRateRange &range, qreal displayRate)
{
    const int rate = wholeDisplayRate(displayRate);
    if (!rate || !(range.preferred > 0) || range.minimum != range.preferred
        || range.maximum != range.preferred) {
        return 0;
    }
    const double frames = displayRate / range.preferred;
    const int n = qRound(frames);
    return n >= 1 && qAbs(frames - n) < 1e-3 * frames && rate % n == 0 ? n : 0;
}

QAppleFrameRateRange QAppleFrameRateRange::forPreferredFrameRate(qreal framesPerSecond,
                                                                 qreal displayRate) noexcept
{
    if (!(framesPerSecond > 0) || !std::isfinite(framesPerSecond))
        return QAppleFrameRateRange();
    if (!(displayRate > 0)) {
        // Unknown display, let the system pick the closest rate it supports
        const float rate = float(framesPerSecond);
        return QAppleFrameRateRange(rate, rate, rate);
    }

    // The most refreshes per frame, i.e. the slowest rate, that is not below the
    // preferred rate (within 1%, so that 23.976 counts as 24), so that content at
    // that rate doesn't skip frames: 25 fps on a 120 Hz display gives 30, not 24.
    // Clamped, as tiny rates would overflow, and as no more refreshes per frame
    // than the display has per second divide its refresh rate.
    const int wholeRate = wholeDisplayRate(displayRate);
    int frames = int(std::clamp(displayRate / (framesPerSecond * 0.99), 1.0,
                                wholeRate ? double(wholeRate) : 1e6));
    // And a rate the system supports, see wholeDisplayRate()
    while (frames > 1 && wholeRate % frames != 0)
        --frames;
    // Every refresh is what the system does by default. Don't pin the maximum
    // rate explicitly, the system knows better what that is at any moment.
    if (frames == 1)
        return QAppleFrameRateRange();
    const float rate = float(displayRate / frames);
    return QAppleFrameRateRange(rate, rate, rate);
}

QAppleFrameRateRange QAppleFrameRateRange::unitedWith(const QAppleFrameRateRange &other,
                                                      qreal displayRate) const noexcept
{
    // A default range lets the system run at whatever rate it sees fit, which
    // in practice is the maximum refresh rate, so that wins over any limit.
    if (isDefault() || other.isDefault())
        return QAppleFrameRateRange();

    // Two exact rates: run at their greatest common rate, so both stay exact
    const int a = exactFramesPerDelivery(*this, displayRate);
    const int b = exactFramesPerDelivery(other, displayRate);
    if (a && b) {
        const int common = std::gcd(a, b);
        if (common == 1)
            return QAppleFrameRateRange();
        const float rate = float(displayRate / common);
        return QAppleFrameRateRange(rate, rate, rate);
    }

    QAppleFrameRateRange united(std::max(minimum, other.minimum), std::max(maximum, other.maximum));

    // No preferred rate means "as fast as the maximum allows", not "as slow as
    // possible", so it must not let the other side's lower preference win.
    // An unbounded maximum without a preference leaves the choice to the system.
    const auto effectivePreferred = [](const QAppleFrameRateRange &r) -> float {
        if (r.preferred > 0)
            return r.preferred;
        return std::isfinite(r.maximum) ? r.maximum : 0;
    };
    if (preferred != 0 || other.preferred != 0) {
        const float a = effectivePreferred(*this);
        const float b = effectivePreferred(other);
        if (a != 0 && b != 0)
            united.preferred = std::clamp(std::max(a, b), united.minimum, united.maximum);
    }
    return united;
}

double QAppleFrameRateRange::frameInterval() const noexcept
{
    if (isDefault())
        return 0;
    const double rate = preferred > 0 ? preferred : maximum;
    if (!(rate > 0) || !std::isfinite(rate))
        return 0;
    return 1.0 / rate;
}

// The number of display link frames between deliveries, when the requested
// interval isn't a multiple of the display link interval. Rounds to the nearest
// frame count, with ties (e.g. 24 fps on a 60 Hz display) going to the faster
// rate, like CoreAnimation does. The bias is large compared to timestamp jitter,
// so that the decision is stable from frame to frame.
static int framesPerDelivery(double interval, double linkFrameInterval)
{
    // Clamped, as tiny rates would overflow
    const double frames = std::min(interval / linkFrameInterval, 1e6);
    return std::max(1, int(std::floor(frames + 0.5 - 1e-3)));
}

bool QAppleFrameRateRange::shouldDeliverFrame(double lastTargetTimestamp, double targetTimestamp,
                                              double linkFrameInterval) const noexcept
{
    const double interval = frameInterval();
    if (interval <= 0 || lastTargetTimestamp <= 0)
        return true;

    // Time going backwards, e.g. after the display link was recreated
    if (targetTimestamp < lastTargetTimestamp)
        return true;

    const double elapsed = targetTimestamp - lastTargetTimestamp;
    if (linkFrameInterval <= 0)
        return elapsed >= interval - 0.0005;

    // Deliver on the display link frame that is closest to the frame count,
    // with half a frame of tolerance for timestamp jitter.
    const int frames = framesPerDelivery(interval, linkFrameInterval);
    return elapsed >= (frames - 0.5) * linkFrameInterval;
}

double QAppleFrameRateRange::effectiveFrameInterval(double linkFrameInterval) const noexcept
{
    const double interval = frameInterval();
    if (linkFrameInterval <= 0)
        return interval;
    if (interval <= 0)
        return linkFrameInterval;

    return framesPerDelivery(interval, linkFrameInterval) * linkFrameInterval;
}

#ifndef QT_NO_DEBUG_STREAM
QDebug operator<<(QDebug debug, const QAppleFrameRateRange &range)
{
    QDebugStateSaver saver(debug);
    debug.nospace() << "QAppleFrameRateRange(";
    if (range.isDefault())
        debug << "default";
    else
        debug << "min=" << range.minimum << ", max=" << range.maximum
              << ", preferred=" << range.preferred;
    debug << ')';
    return debug;
}
#endif

QAppleFrameRateRange QAppleFrameRatePreference::environmentDefault()
{
    static const QAppleFrameRateRange range = [] {
        const QString value = qEnvironmentVariable("QT_APPLE_PREFERRED_FRAME_RATE_RANGE");
        if (auto parsed = QAppleFrameRateRange::fromString(value)) {
            if (!parsed->isDefault())
                qCInfo(lcFrameRate) << "Using default preferred frame rate range" << *parsed;
            return *parsed;
        }
        qCWarning(lcFrameRate) << "Ignoring invalid QT_APPLE_PREFERRED_FRAME_RATE_RANGE" << value
                               << "- expected \"rate\", \"min,max\" or \"min,max,preferred\"";
        return QAppleFrameRateRange();
    }();
    return range;
}

// A range asking for the display's maximum rate, without a lower preferred
// rate, is what the system does by default anyway. Passed on explicitly, such
// ranges ((120, 120, 120) and (1, 120, 0) on a 120 Hz ProMotion display) were
// seen to make the display link stop delivering, which isn't understood, so
// use the default range for them.
static QAppleFrameRateRange withoutExplicitMaximum(const QAppleFrameRateRange &range,
                                                   qreal displayRate)
{
    if (range.isDefault() || !(displayRate > 0))
        return range;
    const double maximum = displayRate * 0.99;
    if (range.maximum >= maximum && (range.preferred == 0 || range.preferred >= maximum))
        return QAppleFrameRateRange();
    return range;
}

QAppleFrameRateRange QAppleFrameRatePreference::update(const QWindow *window, qreal displayRate)
{
    // The public API wins over the (unsupported) property and environment variable
    if (const qreal preferredFrameRate = window->preferredFrameRate(); preferredFrameRate > 0) {
        const auto range = QAppleFrameRateRange::forPreferredFrameRate(preferredFrameRate, displayRate);
        if (range != m_range)
            qCDebug(lcFrameRate) << window << "prefers" << preferredFrameRate << "fps, using" << range;
        m_range = range;
        m_value = QVariant();
        m_valueWasInvalid = false;
        return m_range;
    }

    const QVariant value = window->property(propertyName);
    if (!value.isValid()) {
        m_value = QVariant();
        m_valueWasInvalid = false;
        m_requested = environmentDefault();
    } else if (value != m_value) {
        m_value = value;
        if (auto parsed = QAppleFrameRateRange::fromVariant(value)) {
            m_requested = *parsed;
            m_valueWasInvalid = false;
        } else {
            // Types such as QJSValue don't compare equal to themselves,
            // so only warn when going from a valid to an invalid value.
            if (!m_valueWasInvalid) {
                qCWarning(lcFrameRate) << "Ignoring invalid" << propertyName << value << "on"
                                       << window << "- using the system default frame rate";
            }
            m_valueWasInvalid = true;
            m_requested = QAppleFrameRateRange();
        }
    }

    const auto range = withoutExplicitMaximum(m_requested, displayRate);
    if (range != m_range)
        qCDebug(lcFrameRate) << window << "prefers" << m_requested << "- using" << range;
    m_range = range;
    return m_range;
}

QAppleDisplayLinkDelivery::Screen::~Screen() = default;

static bool hasPendingUpdateRequest(QWindow *window)
{
    return QWindowPrivate::get(window)->updateRequestPending;
}

std::optional<QAppleFrameRateRange> QAppleDisplayLinkDelivery::deliver(Screen &screen,
                                                                     const Frame &frame)
{
    // Delivering to a window may destroy other windows
    QVarLengthArray<QPointer<QWindow>, 16> windows;
    for (QWindow *window : QGuiApplication::allWindows()) {
        if (screen.updatesWithDisplayLink(window))
            windows.append(window);
    }

    const auto deliverIfDue = [&](QWindow *window) {
        auto &preference = screen.frameRatePreference(window);
        preference.update(window, frame.displayRate);
        if (!preference.shouldDeliverFrame(frame.targetTimestamp, frame.linkFrameInterval))
            return;

        const QPointer<QWindow> guard(window);
        QWindowPrivate::get(window)->updateRequestInterval =
                preference.effectiveFrameInterval(frame.linkFrameInterval);
        const bool delivered = screen.deliverUpdateRequest(window);
        if (!guard)
            return;
        // Only valid during delivery, so that frames driven by other means,
        // such as expose events, don't use the paced interval
        QWindowPrivate::get(guard)->updateRequestInterval = 0;
        // A deferred update request is delivered on the next display link
        // frame, instead of waiting for the next paced one
        if (delivered && screen.updatesWithDisplayLink(guard))
            screen.frameRatePreference(guard).frameDelivered(frame.targetTimestamp);
    };

    QVarLengthArray<bool, 16> visited(windows.size());
    std::fill(visited.begin(), visited.end(), false);
    for (qsizetype i = 0; i < windows.size(); ++i) {
        QWindow *window = windows.at(i);
        if (!window || !screen.updatesWithDisplayLink(window) || !hasPendingUpdateRequest(window))
            continue;
        visited[i] = true;
        deliverIfDue(window);
    }

    // Windows that got an update request while delivering to a window after
    // them, e.g. when one window drives the frames of another
    for (qsizetype i = 0; i < windows.size(); ++i) {
        QWindow *window = windows.at(i);
        if (visited.at(i) || !window || !screen.updatesWithDisplayLink(window)
            || !hasPendingUpdateRequest(window)) {
            continue;
        }
        deliverIfDue(window);
    }

    return pendingRange(screen, frame.displayRate);
}

std::optional<QAppleFrameRateRange> QAppleDisplayLinkDelivery::pendingRange(Screen &screen,
                                                                          qreal displayRate)
{
    std::optional<QAppleFrameRateRange> range;
    for (QWindow *window : QGuiApplication::allWindows()) {
        if (!screen.updatesWithDisplayLink(window) || !hasPendingUpdateRequest(window))
            continue;
        const auto windowRange = screen.frameRatePreference(window).update(window, displayRate);
        range = range ? range->unitedWith(windowRange, displayRate) : windowRange;
    }
    return range;
}

QT_END_NAMESPACE
