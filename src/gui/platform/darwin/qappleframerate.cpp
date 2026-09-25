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

Q_STATIC_LOGGING_CATEGORY(lcFrameRate, "qt.qpa.framerate")

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

    QAppleFrameRateRange united(std::max(minimum, other.minimum), std::max(maximum, other.maximum),
                                std::max(preferred, other.preferred));
    if (united.preferred != 0)
        united.preferred = std::clamp(united.preferred, united.minimum, united.maximum);
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

bool QAppleFrameRateRange::shouldDeliverFrame(double lastTargetTimestamp, double targetTimestamp,
                                              double linkFrameInterval) const noexcept
{
    const double interval = frameInterval();
    if (interval <= 0 || lastTargetTimestamp <= 0)
        return true;

    // Time going backwards, e.g. after the display link was recreated
    if (targetTimestamp < lastTargetTimestamp)
        return true;

    // Deliver on the display link frame closest to the requested interval.
    // This matches what CoreAnimation does when asked for a rate that is not
    // a divisor of the refresh rate (it rounds to the nearest supported rate).
    const double tolerance = std::max(linkFrameInterval / 2, 0.0005);
    return targetTimestamp - lastTargetTimestamp >= interval - tolerance;
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
