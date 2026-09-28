// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#include <QTest>
#include <QtCore/QPoint>
#include <QtGui/QWindow>
#include <QtGui/private/qappleframerate_p.h>

#include <cmath>
#include <limits>

using namespace Qt::StringLiterals;
using Range = QAppleFrameRateRange;
Q_DECLARE_METATYPE(QAppleFrameRateRange)
Q_DECLARE_METATYPE(std::optional<QAppleFrameRateRange>)

namespace QTest {
template <>
char *toString(const QAppleFrameRateRange &r)
{
    return qstrdup(QByteArray("(" + QByteArray::number(r.minimum) + ", "
                              + QByteArray::number(r.maximum) + ", "
                              + QByteArray::number(r.preferred) + ")")
                           .constData());
}
template <>
char *toString(const std::optional<QAppleFrameRateRange> &r)
{
    return r ? toString(*r) : qstrdup("invalid");
}
} // namespace QTest

class tst_QAppleFrameRate : public QObject
{
    Q_OBJECT
private slots:
    void validation_data();
    void validation();
    void fromString_data();
    void fromString();
    void fromVariant_data();
    void fromVariant();
    void unitedWith_data();
    void unitedWith();
    void frameInterval();
    void pacing_data();
    void pacing();
    void effectiveFrameInterval();
    void forPreferredFrameRate_data();
    void forPreferredFrameRate();
    void unitedExactRates_data();
    void unitedExactRates();
    void preferenceFromPublicApi();
    void preferenceFromWindowProperty();
};

static constexpr float inf = std::numeric_limits<float>::infinity();
static constexpr float qnan = std::numeric_limits<float>::quiet_NaN();

void tst_QAppleFrameRate::validation_data()
{
    QTest::addColumn<Range>("range");
    QTest::addColumn<bool>("valid");

    // Matches what -[CADisplayLink setPreferredFrameRateRange:] accepts
    // (measured on macOS 27 and the iOS 27 simulator)
    QTest::newRow("default") << Range(0, 0, 0) << true;
    QTest::newRow("0,0,30") << Range(0, 0, 30) << false;
    QTest::newRow("0,60,30") << Range(0, 60, 30) << false;
    QTest::newRow("30,0,0") << Range(30, 0, 0) << false;
    QTest::newRow("30,60,0") << Range(30, 60, 0) << true;
    QTest::newRow("30,30,30") << Range(30, 30, 30) << true;
    QTest::newRow("10,60,5") << Range(10, 60, 5) << false;
    QTest::newRow("10,60,70") << Range(10, 60, 70) << false;
    QTest::newRow("60,30,30") << Range(60, 30, 30) << false;
    QTest::newRow("0.5,60,60") << Range(0.5, 60, 60) << true;
    QTest::newRow("1000,1000,1000") << Range(1000, 1000, 1000) << true;
    QTest::newRow("-1,60,60") << Range(-1, 60, 60) << false;
    QTest::newRow("nan,60,60") << Range(qnan, 60, 60) << false;
    QTest::newRow("10,inf,60") << Range(10, inf, 60) << true;
    QTest::newRow("10,60,nan") << Range(10, 60, qnan) << false;
    QTest::newRow("inf,inf,0") << Range(inf, inf, 0) << false;
}

void tst_QAppleFrameRate::validation()
{
    QFETCH(Range, range);
    QFETCH(bool, valid);
    QCOMPARE(range.isValid(), valid);
}

void tst_QAppleFrameRate::fromString_data()
{
    QTest::addColumn<QString>("string");
    QTest::addColumn<std::optional<Range>>("expected");

    QTest::newRow("empty") << QString() << std::optional(Range());
    QTest::newRow("default") << u"default"_s << std::optional(Range());
    QTest::newRow("0") << u"0"_s << std::optional(Range());
    QTest::newRow("60") << u"60"_s << std::optional(Range(60, 60, 60));
    QTest::newRow(" 24 ") << u" 24 "_s << std::optional(Range(24, 24, 24));
    QTest::newRow("30,120") << u"30,120"_s << std::optional(Range(30, 120, 0));
    QTest::newRow("30, 120, 60") << u"30, 120, 60"_s << std::optional(Range(30, 120, 60));
    QTest::newRow("23.976") << u"23.976"_s << std::optional(Range(23.976f, 23.976f, 23.976f));
    QTest::newRow("-5") << u"-5"_s << std::optional<Range>();
    QTest::newRow("abc") << u"abc"_s << std::optional<Range>();
    QTest::newRow("1,2,3,4") << u"1,2,3,4"_s << std::optional<Range>();
    QTest::newRow("120,30") << u"120,30"_s << std::optional<Range>();
    QTest::newRow("30,60,90") << u"30,60,90"_s << std::optional<Range>();
    QTest::newRow("30,,60") << u"30,,60"_s << std::optional<Range>();
}

void tst_QAppleFrameRate::fromString()
{
    QFETCH(QString, string);
    QFETCH(std::optional<Range>, expected);
    QCOMPARE(Range::fromString(string), expected);
}

void tst_QAppleFrameRate::fromVariant_data()
{
    QTest::addColumn<QVariant>("value");
    QTest::addColumn<std::optional<Range>>("expected");

    QTest::newRow("invalid") << QVariant() << std::optional(Range());
    QTest::newRow("int") << QVariant(30) << std::optional(Range(30, 30, 30));
    QTest::newRow("double") << QVariant(59.94) << std::optional(Range(59.94f, 59.94f, 59.94f));
    QTest::newRow("zero") << QVariant(0) << std::optional(Range());
    QTest::newRow("negative") << QVariant(-1) << std::optional<Range>();
    QTest::newRow("string") << QVariant(u"30,120,60"_s) << std::optional(Range(30, 120, 60));
    QTest::newRow("list 1") << QVariant(QVariantList{ 48 }) << std::optional(Range(48, 48, 48));
    QTest::newRow("list 2") << QVariant(QVariantList{ 30, 120 })
                            << std::optional(Range(30, 120, 0));
    QTest::newRow("list 3") << QVariant(QVariantList{ 30, 120, 60 })
                            << std::optional(Range(30, 120, 60));
    QTest::newRow("list 4") << QVariant(QVariantList{ 1, 2, 3, 4 }) << std::optional<Range>();
    QTest::newRow("list empty") << QVariant(QVariantList{ }) << std::optional<Range>();
    QTest::newRow("list junk") << QVariant(QVariantList{ u"a"_s }) << std::optional<Range>();
    QTest::newRow("map") << QVariant(
            QVariantMap{ { u"minimum"_s, 30 }, { u"maximum"_s, 120 }, { u"preferred"_s, 60 } })
                         << std::optional(Range(30, 120, 60));
    QTest::newRow("map no preferred")
            << QVariant(QVariantMap{ { u"minimum"_s, 30 }, { u"maximum"_s, 120 } })
            << std::optional(Range(30, 120, 0));
    QTest::newRow("map preferred only")
            << QVariant(QVariantMap{ { u"preferred"_s, 60 } }) << std::optional(Range(60, 60, 60));
    QTest::newRow("map typo") << QVariant(
            QVariantMap{ { u"minimum"_s, 30 }, { u"maximimum"_s, 120 } })
                              << std::optional<Range>();
    QTest::newRow("map invalid") << QVariant(
            QVariantMap{ { u"minimum"_s, 0 }, { u"maximum"_s, 60 }, { u"preferred"_s, 30 } })
                                 << std::optional<Range>();
    QTest::newRow("hash") << QVariant(QVariantHash{ { u"minimum"_s, 10 }, { u"maximum"_s, 60 } })
                          << std::optional(Range(10, 60, 0));
    QTest::newRow("point") << QVariant(QPoint(1, 2)) << std::optional<Range>();
}

void tst_QAppleFrameRate::fromVariant()
{
    QFETCH(QVariant, value);
    QFETCH(std::optional<Range>, expected);
    QCOMPARE(Range::fromVariant(value), expected);
}

void tst_QAppleFrameRate::unitedWith_data()
{
    QTest::addColumn<Range>("a");
    QTest::addColumn<Range>("b");
    QTest::addColumn<Range>("expected");

    QTest::newRow("default+default") << Range() << Range() << Range();
    QTest::newRow("default+30") << Range() << Range(30, 30, 30) << Range();
    QTest::newRow("30+default") << Range(30, 30, 30) << Range() << Range();
    QTest::newRow("30+30") << Range(30, 30, 30) << Range(30, 30, 30) << Range(30, 30, 30);
    QTest::newRow("30+60") << Range(30, 30, 30) << Range(60, 60, 60) << Range(60, 60, 60);
    QTest::newRow("24+30,120,60") << Range(24, 24, 24) << Range(30, 120, 60) << Range(30, 120, 60);
    // No preferred rate means up to the maximum, so the other side's lower
    // preference doesn't throttle it
    QTest::newRow("clamps preferred")
            << Range(100, 120, 0) << Range(10, 60, 30) << Range(100, 120, 120);
    QTest::newRow("no preferred + 24") << Range(30, 120) << Range(24, 24, 24) << Range(30, 120, 120);
    QTest::newRow("no preferred + 60") << Range(30, 120) << Range(60, 60, 60) << Range(60, 120, 120);
    QTest::newRow("no preferred") << Range(10, 60) << Range(20, 30) << Range(20, 60, 0);
    QTest::newRow("unbounded + 30") << Range(10, inf) << Range(30, 30, 30) << Range(30, inf, 0);
}

void tst_QAppleFrameRate::unitedWith()
{
    QFETCH(Range, a);
    QFETCH(Range, b);
    QFETCH(Range, expected);
    QVERIFY(a.isValid());
    QVERIFY(b.isValid());
    const Range united = a.unitedWith(b);
    QCOMPARE(united, expected);
    QVERIFY(united.isValid());
    QCOMPARE(b.unitedWith(a), expected);
}

void tst_QAppleFrameRate::frameInterval()
{
    QCOMPARE(Range().frameInterval(), 0.0);
    QCOMPARE(Range(30, 30, 30).frameInterval(), 1.0 / 30);
    QCOMPARE(Range(30, 120, 60).frameInterval(), 1.0 / 60);
    QCOMPARE(Range(30, 120).frameInterval(), 1.0 / 120);
    QCOMPARE(Range(30, inf).frameInterval(), 0.0);
}

void tst_QAppleFrameRate::pacing_data()
{
    QTest::addColumn<Range>("range");
    QTest::addColumn<double>("linkRate");
    QTest::addColumn<int>("framesPerDelivery");

    QTest::newRow("default@240") << Range() << 240.0 << 1;
    QTest::newRow("30@240") << Range(30, 30, 30) << 240.0 << 8;
    QTest::newRow("60@240") << Range(60, 60, 60) << 240.0 << 4;
    QTest::newRow("120@240") << Range(120, 120, 120) << 240.0 << 2;
    QTest::newRow("24@240") << Range(24, 24, 24) << 240.0 << 10;
    QTest::newRow("48@240") << Range(48, 48, 48) << 240.0 << 5;
    // Same rounding as CoreAnimation (measured: 100 on a 240 Hz panel gives 120)
    QTest::newRow("100@240") << Range(100, 100, 100) << 240.0 << 2;
    QTest::newRow("30@60") << Range(30, 30, 30) << 60.0 << 2;
    QTest::newRow("60@60") << Range(60, 60, 60) << 60.0 << 1;
    QTest::newRow("120@60") << Range(120, 120, 120) << 60.0 << 1;
    QTest::newRow("24@120") << Range(24, 24, 24) << 120.0 << 5;
    QTest::newRow("30,120,60@120") << Range(30, 120, 60) << 120.0 << 2;
    // Ties go to the faster rate (measured: 24 on a 60 Hz display gives 30)
    QTest::newRow("24@60") << Range(24, 24, 24) << 60.0 << 2;
    QTest::newRow("48@120") << Range(48, 48, 48) << 120.0 << 2;
    QTest::newRow("96@240") << Range(96, 96, 96) << 240.0 << 2;
    QTest::newRow("40@60") << Range(40, 40, 40) << 60.0 << 1;
    QTest::newRow("80@120") << Range(80, 80, 80) << 120.0 << 1;
    QTest::newRow("160@240") << Range(160, 160, 160) << 240.0 << 1;
    QTest::newRow("30@75") << Range(30, 30, 30) << 75.0 << 2;
    // Refresh rates that aren't multiples of the requested rate
    QTest::newRow("30@59.94") << Range(30, 30, 30) << 59.94 << 2;
    QTest::newRow("30@50") << Range(30, 30, 30) << 50.0 << 2;
    QTest::newRow("30@144") << Range(30, 30, 30) << 144.0 << 5;
    QTest::newRow("60@144") << Range(60, 60, 60) << 144.0 << 2;
}

void tst_QAppleFrameRate::pacing()
{
    QFETCH(Range, range);
    QFETCH(double, linkRate);
    QFETCH(int, framesPerDelivery);

    const double linkInterval = 1.0 / linkRate;

    // With a little jitter, and without jitter at a large host time (where
    // timestamps land exactly on the thresholds, apart from rounding)
    for (const auto &[startTime, jitterFactor] : { std::pair{ 1000.0, 0.05 }, std::pair{ 1e6, 0.0 } }) {
        double last = 0;
        QList<int> gaps;
        const int ticks = int(linkRate * 2);
        for (int i = 1; i <= ticks; ++i) {
            const double jitter = (i % 3 - 1) * linkInterval * jitterFactor;
            const double target = startTime + i * linkInterval + jitter;
            if (range.shouldDeliverFrame(last, target, linkInterval)) {
                if (last > 0)
                    gaps.append(qRound((target - last) / linkInterval));
                last = target;
            }
        }
        QVERIFY(!gaps.isEmpty());
        for (int gap : std::as_const(gaps))
            QCOMPARE(gap, framesPerDelivery);
    }

    // The effective frame interval matches what the pacing lets through
    QCOMPARE(range.effectiveFrameInterval(linkInterval), framesPerDelivery * linkInterval);

    // Time going backwards always delivers
    QVERIFY(range.shouldDeliverFrame(2000.0, 1000.0, linkInterval));
    // First frame always delivers
    QVERIFY(range.shouldDeliverFrame(0, 1000.0, linkInterval));
}

void tst_QAppleFrameRate::effectiveFrameInterval()
{
    // Unknown display link interval
    QCOMPARE(Range().effectiveFrameInterval(0), 0.0);
    QCOMPARE(Range(30, 30, 30).effectiveFrameInterval(0), 1.0 / 30);
    // No preference follows the display link
    QCOMPARE(Range().effectiveFrameInterval(1.0 / 240), 1.0 / 240);
    // Faster than the display link is capped by it
    QCOMPARE(Range(1000, 1000, 1000).effectiveFrameInterval(1.0 / 60), 1.0 / 60);
    // Exact divisors
    QCOMPARE(Range(30, 30, 30).effectiveFrameInterval(1.0 / 240), 8.0 / 240);
    QCOMPARE(Range(24, 24, 24).effectiveFrameInterval(1.0 / 240), 10.0 / 240);
    // Not divisors, rounded up to the next faster rate like CoreAnimation does
    QCOMPARE(Range(24, 24, 24).effectiveFrameInterval(1.0 / 60), 2.0 / 60);
    QCOMPARE(Range(100, 100, 100).effectiveFrameInterval(1.0 / 240), 2.0 / 240);
    // Display link already slowed down to the window's rate
    QCOMPARE(Range(30, 30, 30).effectiveFrameInterval(1.0 / 30), 1.0 / 30);
}

void tst_QAppleFrameRate::forPreferredFrameRate_data()
{
    QTest::addColumn<double>("displayRate");
    QTest::addColumn<double>("preferred");
    QTest::addColumn<double>("expectedRate"); // 0 = every refresh (default range)

    // Exact rates, and the next faster exact rate otherwise (never below)
    QTest::newRow("120@120") << 120.0 << 120.0 << 0.0;
    QTest::newRow("80@120") << 120.0 << 80.0 << 0.0;
    QTest::newRow("60@120") << 120.0 << 60.0 << 60.0;
    QTest::newRow("59.94@120") << 120.0 << 59.94 << 60.0;
    QTest::newRow("50@120") << 120.0 << 50.0 << 60.0;
    QTest::newRow("48@120") << 120.0 << 48.0 << 60.0;
    QTest::newRow("40@120") << 120.0 << 40.0 << 40.0;
    QTest::newRow("30@120") << 120.0 << 30.0 << 30.0;
    QTest::newRow("29.97@120") << 120.0 << 29.97 << 30.0;
    QTest::newRow("25@120") << 120.0 << 25.0 << 30.0;
    QTest::newRow("24@120") << 120.0 << 24.0 << 24.0;
    QTest::newRow("23.976@120") << 120.0 << 24000.0 / 1001 << 24.0;
    QTest::newRow("1000@120") << 120.0 << 1000.0 << 0.0;
    QTest::newRow("60@60") << 60.0 << 60.0 << 0.0;
    QTest::newRow("50@60") << 60.0 << 50.0 << 0.0;
    QTest::newRow("30@60") << 60.0 << 30.0 << 30.0;
    QTest::newRow("25@60") << 60.0 << 25.0 << 30.0;
    QTest::newRow("24@60") << 60.0 << 24.0 << 30.0;
    QTest::newRow("30@59.94") << 59.94 << 30.0 << 29.97;
    QTest::newRow("48@240") << 240.0 << 48.0 << 48.0;
    QTest::newRow("80@240") << 240.0 << 80.0 << 80.0;
    // CoreAnimation only runs display links at whole rates that divide the
    // refresh rate (measured on a 240 Hz display: 240 / 9 = 26.67 gives 30,
    // 240 / 7 = 34.29 gives 40, 240 / 13 = 18.46 gives 20), so only those are
    // exact, and requested
    QTest::newRow("25@240") << 240.0 << 25.0 << 30.0;
    QTest::newRow("34@240") << 240.0 << 34.0 << 40.0;
    QTest::newRow("18@240") << 240.0 << 18.0 << 20.0;
    QTest::newRow("16@240") << 240.0 << 16.0 << 16.0;
    QTest::newRow("15@240") << 240.0 << 15.0 << 15.0;
    QTest::newRow("17@120") << 120.0 << 17.0 << 20.0;
    QTest::newRow("20@120") << 120.0 << 20.0 << 20.0;
    QTest::newRow("30@144") << 144.0 << 30.0 << 36.0;
    QTest::newRow("24@144") << 144.0 << 24.0 << 24.0;
    // Tiny rates: at least once a second, the slowest the display can do exactly
    QTest::newRow("0.5@240") << 240.0 << 0.5 << 1.0;
    QTest::newRow("1e-9@120") << 120.0 << 1e-9 << 1.0;
    QTest::newRow("0") << 120.0 << 0.0 << 0.0;
    QTest::newRow("negative") << 120.0 << -1.0 << 0.0;
}

void tst_QAppleFrameRate::forPreferredFrameRate()
{
    QFETCH(double, displayRate);
    QFETCH(double, preferred);
    QFETCH(double, expectedRate);

    const Range range = Range::forPreferredFrameRate(preferred, displayRate);
    QVERIFY(range.isValid());
    if (expectedRate == 0) {
        QVERIFY2(range.isDefault(), QTest::toString(range));
    } else {
        QCOMPARE(range.preferred, float(expectedRate));
        QCOMPARE(range.minimum, range.preferred);
        QCOMPARE(range.maximum, range.preferred);
        // Never below the preferred rate
        QVERIFY(range.preferred >= preferred * 0.99);
    }
}

void tst_QAppleFrameRate::unitedExactRates_data()
{
    QTest::addColumn<double>("displayRate");
    QTest::addColumn<Range>("a");
    QTest::addColumn<Range>("b");
    QTest::addColumn<Range>("expected");

    // Both stay exact: the display link runs at their greatest common rate
    QTest::newRow("24+60@120") << 120.0 << Range(24, 24, 24) << Range(60, 60, 60) << Range();
    QTest::newRow("30+60@120") << 120.0 << Range(30, 30, 30) << Range(60, 60, 60) << Range(60, 60, 60);
    QTest::newRow("24+30@120") << 120.0 << Range(24, 24, 24) << Range(30, 30, 30) << Range();
    QTest::newRow("30+40@120") << 120.0 << Range(30, 30, 30) << Range(40, 40, 40) << Range();
    QTest::newRow("30+30@120") << 120.0 << Range(30, 30, 30) << Range(30, 30, 30) << Range(30, 30, 30);
    QTest::newRow("24+60@240") << 240.0 << Range(24, 24, 24) << Range(60, 60, 60) << Range(120, 120, 120);
    QTest::newRow("48+80@240") << 240.0 << Range(48, 48, 48) << Range(80, 80, 80) << Range();
    QTest::newRow("24+48@240") << 240.0 << Range(24, 24, 24) << Range(48, 48, 48) << Range(48, 48, 48);
    QTest::newRow("16+24@240") << 240.0 << Range(16, 16, 16) << Range(24, 24, 24) << Range(48, 48, 48);
    QTest::newRow("20+48@240") << 240.0 << Range(20, 20, 20) << Range(48, 48, 48) << Range();
    // Not exact on this display: previous behavior
    QTest::newRow("25+60@120") << 120.0 << Range(25, 25, 25) << Range(60, 60, 60) << Range(60, 60, 60);
    // Not a rate the system supports (240 / 9), so not exact either
    QTest::newRow("26.67+60@240") << 240.0 << Range(240.f / 9, 240.f / 9, 240.f / 9)
                                  << Range(60, 60, 60) << Range(60, 60, 60);
    // Unknown display rate: previous behavior
    QTest::newRow("24+60@0") << 0.0 << Range(24, 24, 24) << Range(60, 60, 60) << Range(60, 60, 60);
}

void tst_QAppleFrameRate::unitedExactRates()
{
    QFETCH(double, displayRate);
    QFETCH(Range, a);
    QFETCH(Range, b);
    QFETCH(Range, expected);
    QCOMPARE(a.unitedWith(b, displayRate), expected);
    QCOMPARE(b.unitedWith(a, displayRate), expected);

    // And each window is then paced exactly at its rate on the resulting link
    const Range united = a.unitedWith(b, displayRate);
    const double linkRate = united.isDefault() ? displayRate : united.preferred;
    if (displayRate > 0 && linkRate > 0) {
        for (const Range &r : { a, b }) {
            const double frames = linkRate / r.preferred;
            if (qAbs(frames - qRound(frames)) < 1e-3 * frames)
                QCOMPARE(r.effectiveFrameInterval(1 / linkRate), 1 / double(r.preferred));
        }
    }
}

void tst_QAppleFrameRate::preferenceFromPublicApi()
{
    QWindow window;
    QAppleFrameRatePreference preference;
    const qreal displayRate = window.screen()->refreshRate();

    window.setPreferredFrameRate(30);
    QCOMPARE(preference.update(&window), Range::forPreferredFrameRate(30, displayRate));

    // The public API wins over the property
    window.setProperty(QAppleFrameRatePreference::propertyName, 60);
    QCOMPARE(preference.update(&window), Range::forPreferredFrameRate(30, displayRate));

    // And the property applies again once the API is reset
    window.resetPreferredFrameRate();
    QCOMPARE(preference.update(&window), Range(60, 60, 60));
}

void tst_QAppleFrameRate::preferenceFromWindowProperty()
{
    QWindow window;
    QAppleFrameRatePreference preference;

    QCOMPARE(preference.update(&window), QAppleFrameRatePreference::environmentDefault());

    window.setProperty(QAppleFrameRatePreference::propertyName, 30);
    QCOMPARE(preference.update(&window), Range(30, 30, 30));
    QCOMPARE(preference.range(), Range(30, 30, 30));

    window.setProperty(QAppleFrameRatePreference::propertyName, QVariantList{ 30, 120, 60 });
    QCOMPARE(preference.update(&window), Range(30, 120, 60));

    QTest::ignoreMessage(QtWarningMsg,
                         QRegularExpression("Ignoring invalid _q_preferredFrameRateRange"));
    window.setProperty(QAppleFrameRatePreference::propertyName, -30);
    QCOMPARE(preference.update(&window), Range());
    // No repeated warning for the same invalid value (would fail on unexpected message)
    QCOMPARE(preference.update(&window), Range());

    window.setProperty(QAppleFrameRatePreference::propertyName, QVariant());
    QCOMPARE(preference.update(&window), QAppleFrameRatePreference::environmentDefault());

    // Pacing state
    window.setProperty(QAppleFrameRatePreference::propertyName, 60);
    preference.update(&window);
    QVERIFY(preference.shouldDeliverFrame(10.0, 1.0 / 240));
    preference.frameDelivered(10.0);
    QVERIFY(!preference.shouldDeliverFrame(10.0 + 1.0 / 240, 1.0 / 240));
    QVERIFY(preference.shouldDeliverFrame(10.0 + 4.0 / 240, 1.0 / 240));
}

QTEST_MAIN(tst_QAppleFrameRate)
#include "tst_qappleframerate.moc"
