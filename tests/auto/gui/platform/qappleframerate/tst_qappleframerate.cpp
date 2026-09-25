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
    void preferenceFromWindowProperty();
};

static constexpr float inf = std::numeric_limits<float>::infinity();
static constexpr float qnan = std::numeric_limits<float>::quiet_NaN();

void tst_QAppleFrameRate::validation_data()
{
    QTest::addColumn<Range>("range");
    QTest::addColumn<bool>("valid");

    // Matches what -[CADisplayLink setPreferredFrameRateRange:] accepts
    // (see wip-cadisplaylink/probes/valid.m)
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
    QTest::newRow("clamps preferred")
            << Range(100, 120, 0) << Range(10, 60, 30) << Range(100, 120, 100);
    QTest::newRow("no preferred") << Range(10, 60) << Range(20, 30) << Range(20, 60, 0);
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
    QTest::addColumn<int>("expectedFramesPerSecond");

    QTest::newRow("default@240") << Range() << 240.0 << 240;
    QTest::newRow("30@240") << Range(30, 30, 30) << 240.0 << 30;
    QTest::newRow("60@240") << Range(60, 60, 60) << 240.0 << 60;
    QTest::newRow("120@240") << Range(120, 120, 120) << 240.0 << 120;
    QTest::newRow("24@240") << Range(24, 24, 24) << 240.0 << 24;
    QTest::newRow("48@240") << Range(48, 48, 48) << 240.0 << 48;
    // Same rounding as CoreAnimation (measured: 100 on a 240 Hz panel gives 120)
    QTest::newRow("100@240") << Range(100, 100, 100) << 240.0 << 120;
    QTest::newRow("30@60") << Range(30, 30, 30) << 60.0 << 30;
    QTest::newRow("60@60") << Range(60, 60, 60) << 60.0 << 60;
    QTest::newRow("120@60") << Range(120, 120, 120) << 60.0 << 60;
    QTest::newRow("24@120") << Range(24, 24, 24) << 120.0 << 24;
    QTest::newRow("30,120,60@120") << Range(30, 120, 60) << 120.0 << 60;
}

void tst_QAppleFrameRate::pacing()
{
    QFETCH(Range, range);
    QFETCH(double, linkRate);
    QFETCH(int, expectedFramesPerSecond);

    const double linkInterval = 1.0 / linkRate;
    // Start at an arbitrary host time, and simulate a little jitter
    double last = 0;
    int delivered = 0;
    const int ticks = int(linkRate);
    for (int i = 1; i <= ticks; ++i) {
        const double jitter = (i % 3 - 1) * linkInterval * 0.05;
        const double target = 1000.0 + i * linkInterval + jitter;
        if (range.shouldDeliverFrame(last, target, linkInterval)) {
            ++delivered;
            last = target;
        }
    }
    QCOMPARE(delivered, expectedFramesPerSecond);

    // Time going backwards always delivers
    QVERIFY(range.shouldDeliverFrame(2000.0, 1000.0, linkInterval));
    // First frame always delivers
    QVERIFY(range.shouldDeliverFrame(0, 1000.0, linkInterval));
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
