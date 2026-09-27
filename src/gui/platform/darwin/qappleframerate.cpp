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
#include <QtGui/qwindow.h>

#include <algorithm>
#include <cmath>

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

QAppleFrameRateRange
QAppleFrameRateRange::unitedWith(const QAppleFrameRateRange &other) const noexcept
{
    // A default range lets the system run at whatever rate it sees fit, which
    // in practice is the maximum refresh rate, so that wins over any limit.
    if (isDefault() || other.isDefault())
        return QAppleFrameRateRange();

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
    return std::max(1, int(std::floor(interval / linkFrameInterval + 0.5 - 1e-3)));
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

QAppleFrameRateRange QAppleFrameRatePreference::update(const QWindow *window)
{
    const QVariant value = window->property(propertyName);
    if (!value.isValid()) {
        m_value = QVariant();
        m_valueWasInvalid = false;
        m_range = environmentDefault();
        return m_range;
    }

    if (value == m_value)
        return m_range;
    m_value = value;

    if (auto parsed = QAppleFrameRateRange::fromVariant(value)) {
        if (*parsed != m_range)
            qCDebug(lcFrameRate) << window << "prefers" << *parsed;
        m_range = *parsed;
        m_valueWasInvalid = false;
    } else {
        // Types such as QJSValue don't compare equal to themselves,
        // so only warn when going from a valid to an invalid value.
        if (!m_valueWasInvalid) {
            qCWarning(lcFrameRate) << "Ignoring invalid" << propertyName << value << "on" << window
                                   << "- using the system default frame rate";
        }
        m_valueWasInvalid = true;
        m_range = QAppleFrameRateRange();
    }
    return m_range;
}

QT_END_NAMESPACE
