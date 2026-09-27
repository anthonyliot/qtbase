// Copyright (C) 2016 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
// Qt-Security score:significant reason:default

#undef QT_NO_FOREACH // this file contains unported legacy Q_FOREACH uses

#include "qiosglobal.h"
#include "qiosintegration.h"
#include "qiosscreen.h"
#include "qioswindow.h"
#include <qpa/qwindowsysteminterface.h>
#include "qiosapplicationdelegate.h"
#include "qiosviewcontroller.h"
#include "quiview.h"
#include "qiostheme.h"
#include "quiwindow.h"

#include <QtCore/private/qcore_mac_p.h>

#include <QtGui/qpointingdevice.h>
#include <QtGui/private/qwindow_p.h>
#include <QtGui/private/qguiapplication_p.h>
#include <QtGui/private/qappleframerate_p.h>
#include <private/qcoregraphics_p.h>
#include <qpa/qwindowsysteminterface.h>

#include <Metal/Metal.h>

#include <sys/sysctl.h>

// -------------------------------------------------------------------------

typedef void (^DisplayLinkBlock)(CADisplayLink *displayLink);

@implementation UIScreen (DisplayLinkBlock)
- (CADisplayLink*)displayLinkWithBlock:(DisplayLinkBlock)block
{
    return [self displayLinkWithTarget:[[block copy] autorelease]
        selector:@selector(invokeDisplayLinkBlock:)];
}
@end

@implementation NSObject (DisplayLinkBlock)
- (void)invokeDisplayLinkBlock:(CADisplayLink *)sender
{
    DisplayLinkBlock block = static_cast<id>(self);
    block(sender);
}
@end


// -------------------------------------------------------------------------

#if !defined(Q_OS_VISIONOS)
static QIOSScreen* qtPlatformScreenFor(UIScreen *uiScreen)
{
    foreach (QScreen *screen, QGuiApplication::screens()) {
        QIOSScreen *platformScreen = static_cast<QIOSScreen *>(screen->handle());
        if (platformScreen->uiScreen() == uiScreen)
            return platformScreen;
    }

    return 0;
}

@interface QIOSScreenTracker : NSObject
@end

@implementation QIOSScreenTracker

+ (void)load
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(screenConnected:)
            name:UIScreenDidConnectNotification object:nil];
    [center addObserver:self selector:@selector(screenDisconnected:)
            name:UIScreenDidDisconnectNotification object:nil];
    [center addObserver:self selector:@selector(screenModeChanged:)
            name:UIScreenModeDidChangeNotification object:nil];
}

+ (void)screenConnected:(NSNotification*)notification
{
    if (!QIOSIntegration::instance())
        return; // Will be added when QIOSIntegration is created

    QWindowSystemInterface::handleScreenAdded(new QIOSScreen([notification object]));
}

+ (void)screenDisconnected:(NSNotification*)notification
{
    if (!QIOSIntegration::instance())
        return;

    QIOSScreen *screen = qtPlatformScreenFor([notification object]);
    Q_ASSERT_X(screen, Q_FUNC_INFO, "Screen disconnected that we didn't know about");

    QWindowSystemInterface::handleScreenRemoved(screen);
}

+ (void)screenModeChanged:(NSNotification*)notification
{
    if (!QIOSIntegration::instance())
        return;

    QIOSScreen *screen = qtPlatformScreenFor([notification object]);
    Q_ASSERT_X(screen, Q_FUNC_INFO, "Screen changed that we didn't know about");

    screen->updateProperties();
}

@end

#endif // !defined(Q_OS_VISIONOS)

// -------------------------------------------------------------------------

QT_BEGIN_NAMESPACE

using namespace Qt::StringLiterals;

#if !defined(Q_OS_VISIONOS)
/*!
    Returns the model identifier of the device.
*/
static QString deviceModelIdentifier()
{
#if TARGET_OS_SIMULATOR
    return QString::fromLocal8Bit(qgetenv("SIMULATOR_MODEL_IDENTIFIER"));
#else
    static const char key[] = "hw.machine";

    size_t size;
    sysctlbyname(key, NULL, &size, NULL, 0);

    QVarLengthArray<char> value(size);
    sysctlbyname(key, value.data(), &size, NULL, 0);

    return QString::fromLatin1(QByteArrayView(value.constData(), qsizetype(size)));
#endif
}
#endif // !defined(Q_OS_VISIONOS)


void QIOSScreen::initializeScreens()
{
#if defined(Q_OS_VISIONOS)
    // Qt requires a screen, so let's give it a dummy one
    QWindowSystemInterface::handleScreenAdded(new QIOSScreen);
#else
    Q_ASSERT([UIScreen.screens containsObject:UIScreen.mainScreen]);
    for (UIScreen *screen in UIScreen.screens)
        QWindowSystemInterface::handleScreenAdded(new QIOSScreen(screen));
#endif
}

#if defined(Q_OS_VISIONOS)
QIOSScreen::QIOSScreen()
{
#else
QIOSScreen::QIOSScreen(UIScreen *screen)
    : m_uiScreen(screen)
{
    QString deviceIdentifier = deviceModelIdentifier();

    if (screen == [UIScreen mainScreen] && !deviceIdentifier.startsWith("AppleTV")) {
        // Based on https://en.wikipedia.org/wiki/List_of_iOS_devices#Display

        // iPhone (1st gen), 3G, 3GS, and iPod Touch (1st–3rd gen) are 18-bit devices
        static QRegularExpression lowBitDepthDevices("^(iPhone1,[12]|iPhone2,1|iPod[1-3],1)$");
        m_depth = deviceIdentifier.contains(lowBitDepthDevices) ? 18 : 24;

        static QRegularExpression iPhoneXModels("^iPhone(10,[36])$");
        static QRegularExpression iPhonePlusModels("^iPhone(7,1|8,2|9,[24]|10,[25])$");
        static QRegularExpression iPadMiniModels("^iPad(2,[567]|4,[4-9]|5,[12])$");

        if (deviceIdentifier.contains(iPhoneXModels)) {
            m_physicalDpi = 458;
        } else if (deviceIdentifier.contains(iPhonePlusModels)) {
            m_physicalDpi = 401;
        } else if (deviceIdentifier.startsWith("iPad")) {
            if (deviceIdentifier.contains(iPadMiniModels))
                m_physicalDpi = 163 * devicePixelRatio();
            else
                m_physicalDpi = 132 * devicePixelRatio();
        } else {
            // All normal iPhones, and iPods
            m_physicalDpi = 163 * devicePixelRatio();
        }
    } else {
        // External display, hard to say
        m_depth = 24;
        m_physicalDpi = 96;
    }

    m_displayLink = [m_uiScreen displayLinkWithBlock:^(CADisplayLink *displayLink) {
        deliverUpdateRequests(displayLink);
    }];
    m_displayLink.paused = YES; // Enabled when clients call QWindow::requestUpdate()
    [m_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];


    // The screen brightness might affect the EDR headroom of the display,
    // which might affect the rendering of windows that opt in to EDR.
    m_screenBrightnessObserver = QMacNotificationObserver(m_uiScreen,
        UIScreenBrightnessDidChangeNotification, [&]() {
            for (auto *window : QPlatformScreen::windows()) {
                auto *platformWindow = static_cast<QIOSWindow*>(window->handle());
                if (!platformWindow)
                    continue;

                UIView *view = platformWindow->view();

                if (!view.layer.wantsExtendedDynamicRangeContent)
                    continue;

                [view setNeedsDisplay];
            }
        });

    if (shouldPauseDisplayLinkWhenInactive()) {
        // We're pausing the display link if the application moves out of the active state,
        // so make sure to deliver to any windows that need it once the app becomes active.
        QObject::connect(qGuiApp, &QGuiApplication::applicationStateChanged, this, [this](auto newState) {
            if (newState == Qt::ApplicationActive) {
                qCDebug(lcQpaApplication) << "Attempting update request delivery after becoming active";
                deliverUpdateRequests(m_displayLink);
            }
        });
    }

#endif // !defined(Q_OS_VISIONOS))

    updateProperties();
}

QIOSScreen::~QIOSScreen()
{
    [m_displayLink invalidate];
}

QString QIOSScreen::name() const
{
#if defined(Q_OS_VISIONOS)
    return {};
#else
    if (m_uiScreen == [UIScreen mainScreen])
        return QString::fromNSString([UIDevice currentDevice].model) + " built-in display"_L1;
    else
        return "External display"_L1;
#endif
}

void QIOSScreen::updateProperties()
{
    QRect previousGeometry = m_geometry;
    QRect previousAvailableGeometry = m_availableGeometry;

#if defined(Q_OS_VISIONOS)
    // Based on what iPad app reports
    m_geometry = QRectF::fromCGRect(rootViewForScreen(this).bounds).toRect();
    m_depth = 24;
#else
    m_geometry = QRectF::fromCGRect(m_uiScreen.bounds).toRect();

    if (m_geometry != previousGeometry) {
        // We can't use the primaryOrientation of screen(), as we haven't reported the new geometry yet
        Qt::ScreenOrientation primaryOrientation = m_geometry.width() >= m_geometry.height() ?
            Qt::LandscapeOrientation : Qt::PortraitOrientation;

        // On iPhone 6+ devices, or when display zoom is enabled, the render buffer is scaled
        // before being output on the physical display. We have to take this into account when
        // computing the physical size. Note that unlike the native bounds, the physical size
        // follows the primary orientation of the screen.
        const QRectF physicalGeometry = mapBetween(nativeOrientation(), primaryOrientation, QRectF::fromCGRect(m_uiScreen.nativeBounds).toRect());

        static const qreal millimetersPerInch = 25.4;
        m_physicalSize = physicalGeometry.size() / m_physicalDpi * millimetersPerInch;
    }

#endif // defined(Q_OS_VISIONOS)

    // UIScreen does not provide a consistent accessor for the safe area margins
    // of the screen, and on visionOS we won't even have a UIScreen, so we report
    // the available geometry of the screen to be the same as the full geometry.
    // Safe area margins and maximized state is handled in QIOSWindow::setWindowState.
    m_availableGeometry = m_geometry;

    // At construction time, we don't yet have an associated QScreen, but we still want
    // to compute the properties above so they are ready for when the QScreen attaches.
    // Also, at destruction time the QScreen has already been torn down, so notifying
    // Qt about changes to the screen will cause asserts in the event delivery system.
    if (!screen())
        return;

    if (screen()->orientation() != orientation())
        QWindowSystemInterface::handleScreenOrientationChange(screen(), orientation());

    // Note: The screen orientation change and the geometry changes are not atomic, so when
    // the former is emitted, the latter has not been reported and reflected in the QScreen
    // API yet. But conceptually it makes sense that the orientation update happens first,
    // and the geometry updates caused by auto-rotation happen after that.

    if (m_geometry != previousGeometry || m_availableGeometry != previousAvailableGeometry)
        QWindowSystemInterface::handleScreenGeometryChange(screen(), m_geometry, m_availableGeometry);
}

void QIOSScreen::setUpdatesPaused(bool paused)
{
    // Make sure the display link runs fast enough for the window that
    // requested the update. During delivery this happens once all the
    // windows have been processed instead.
    if (!paused && !m_deliveringUpdateRequests)
        updateDisplayLinkFrameRate();

    m_displayLink.paused = paused;
}

// Updates the display link's frame rate range from the windows that have pending
// update requests, and returns whether there are any.
bool QIOSScreen::updateDisplayLinkFrameRate() const
{
    std::optional<QAppleFrameRateRange> frameRateRange;
    for (auto *window : QGuiApplication::allWindows()) {
        if (platformScreenForWindow(window) != this)
            continue;

        auto *platformWindow = static_cast<QIOSWindow *>(window->handle());
        if (!platformWindow || !platformWindow->hasPendingUpdateRequest())
            continue;

        const auto range = platformWindow->frameRatePreference().update(window);
        frameRateRange = frameRateRange ? frameRateRange->unitedWith(range, refreshRate()) : range;
    }

    if (frameRateRange)
        setDisplayLinkFrameRate(*frameRateRange);
    return frameRateRange.has_value();
}

void QIOSScreen::setDisplayLinkFrameRate(const QAppleFrameRateRange &range) const
{
    if (!m_displayLink)
        return;

    // CoreAnimation throws for invalid ranges. QAppleFrameRateRange
    // never produces those, but let's be defensive about it.
    if (!range.isValid()) {
        qCWarning(lcQpaWindow) << "Refusing to set invalid" << range << "on display link";
        return;
    }

    const CAFrameRateRange current = m_displayLink.preferredFrameRateRange;
    if (QAppleFrameRateRange(current.minimum, current.maximum, current.preferred) == range)
        return;

    qCDebug(lcQpaWindow) << "Setting display link frame rate for" << this << "to" << range;
    m_displayLink.preferredFrameRateRange =
            CAFrameRateRangeMake(range.minimum, range.maximum, range.preferred);
}

void QIOSScreen::deliverUpdateRequests(CADisplayLink *displayLink) const
{
    bool pauseUpdates = true;

    if (shouldPauseDisplayLinkWhenInactive()
        && QGuiApplication::applicationState() != Qt::ApplicationActive) {
        // The applicationWillResignActive documentation describes that the app
        // should "use this method to pause ongoing tasks, disable timers, and
        // throttle down OpenGL ES frame rates", so we skip update request
        // delivery if the app is not active. Once it becomes active again
        // we re-try the update request delivery (see QIOSScreen constructor).
        qCDebug(lcQpaApplication) << "Skipping update request delivery and pausing display link";
        m_displayLink.paused = true;
        return;
    }

    QScopedValueRollback recursionGuard(m_deliveringUpdateRequests, true);

    const double targetTimestamp = displayLink.targetTimestamp;
    const double frameInterval = displayLink.targetTimestamp - displayLink.timestamp;
    std::optional<QAppleFrameRateRange> frameRateRange;

    QList<QWindow*> windows = QGuiApplication::allWindows();
    for (int i = 0; i < windows.size(); ++i) {
        QWindow *window = windows.at(i);
        if (platformScreenForWindow(window) != this)
            continue;

        QPointer<QIOSWindow> platformWindow = static_cast<QIOSWindow *>(window->handle());
        if (!platformWindow)
            continue;

        if (!platformWindow->hasPendingUpdateRequest())
            continue;

        // The display link runs fast enough for the most demanding window,
        // so windows that asked for a lower frame rate skip some frames.
        auto &frameRatePreference = platformWindow->frameRatePreference();
        frameRatePreference.update(window);
        if (frameRatePreference.shouldDeliverFrame(targetTimestamp, frameInterval)) {
            frameRatePreference.frameDelivered(targetTimestamp);
            qt_window_private(window)->updateRequestInterval =
                    frameRatePreference.effectiveFrameInterval(frameInterval);
            platformWindow->deliverUpdateRequest();

            // platform window can be destroyed in deliverUpdateRequest()
            if (!platformWindow)
                continue;

            // Only valid during delivery, so that frames driven by other means,
            // such as expose events, don't use the paced interval.
            qt_window_private(window)->updateRequestInterval = 0;
        }

        // Another update request was triggered, keep the display link running
        if (platformWindow->hasPendingUpdateRequest()) {
            pauseUpdates = false;
            const auto range = platformWindow->frameRatePreference().update(window);
            frameRateRange = frameRateRange ? frameRateRange->unitedWith(range, refreshRate()) : range;
        }
    }

    if (frameRateRange)
        setDisplayLinkFrameRate(*frameRateRange);

    // A window we looked at before delivering to another one may have gotten an
    // update request in the meantime, e.g. when one window drives the frames of
    // another. Its request won't reach us again, as it's already pending, so look
    // at all the windows again before pausing.
    if (pauseUpdates)
        pauseUpdates = !updateDisplayLinkFrameRate();

    // Pause the display link if there are no pending update requests
    m_displayLink.paused = pauseUpdates;
}

QRect QIOSScreen::geometry() const
{
    return m_geometry;
}

QRect QIOSScreen::availableGeometry() const
{
    return m_availableGeometry;
}

int QIOSScreen::depth() const
{
    return m_depth;
}

QImage::Format QIOSScreen::format() const
{
    return QImage::Format_ARGB32_Premultiplied;
}

QSizeF QIOSScreen::physicalSize() const
{
    return m_physicalSize;
}

QDpi QIOSScreen::logicalBaseDpi() const
{
    return QDpi(72, 72);
}

qreal QIOSScreen::devicePixelRatio() const
{
#if defined(Q_OS_VISIONOS)
    // Based on what iPad app reports, and what Apple
    // documents to be the default scale factor on
    // visionOS, and the minimum scale for assets.
    return 2.0;
#else
    return [m_uiScreen scale];
#endif
}

qreal QIOSScreen::refreshRate() const
{
#if defined(Q_OS_VISIONOS)
    return 120.0; // Based on what iPad app reports
#else
    return m_uiScreen.maximumFramesPerSecond;
#endif
}

Qt::ScreenOrientation QIOSScreen::nativeOrientation() const
{
#if defined(Q_OS_VISIONOS)
    // Based on iPad app reporting native bounds 1668x2388
    return Qt::PortraitOrientation;
#else
    CGRect nativeBounds =
#if defined(Q_OS_IOS)
        m_uiScreen.nativeBounds;
#else
        m_uiScreen.bounds;
#endif

    // All known iOS devices have a native orientation of portrait, but to
    // be on the safe side we compare the width and height of the bounds.
    return nativeBounds.size.width >= nativeBounds.size.height ?
        Qt::LandscapeOrientation : Qt::PortraitOrientation;
#endif
}

Qt::ScreenOrientation QIOSScreen::orientation() const
{
    // We don't report UIDevice.currentDevice.orientation here,
    // as that would report the actual orientation of the device,
    // even if the orientation of the UI was locked to a subset
    // of the possible orientations via the app's Info.plist or
    // via [UIViewController supportedInterfaceOrientations].
    auto *windowScene = rootViewForScreen(this).window.windowScene;
    auto interfaceOrientation = windowScene ?
        windowScene.interfaceOrientation : UIInterfaceOrientationUnknown;

    // FIXME: On visionOS the interface orientation is reported
    // as portrait, which seems strange, but at least it matches
    // what we report as the native orientation.

    switch (interfaceOrientation) {
    case UIInterfaceOrientationPortrait:
        return Qt::PortraitOrientation;
    case UIInterfaceOrientationPortraitUpsideDown:
        return Qt::InvertedPortraitOrientation;
    case UIInterfaceOrientationLandscapeLeft:
        return Qt::LandscapeOrientation;
    case UIInterfaceOrientationLandscapeRight:
        return Qt::InvertedLandscapeOrientation;
    case UIInterfaceOrientationUnknown:
    default:
        // Fall back to the primary orientation, but with a concrete
        // orientation instead of Qt::PrimaryOrientation, as when we
        // report orientation changes the primary orientation has not
        // been updated yet, so user's can't query it in response.
        return m_geometry.width() >= m_geometry.height() ?
            Qt::LandscapeOrientation : Qt::PortraitOrientation;
    }
}

QPixmap QIOSScreen::grabWindow(WId window, int x, int y, int width, int height) const
{
    if (window && ![reinterpret_cast<id>(window) isKindOfClass:[UIView class]])
        return QPixmap();

    UIView *view = window ? reinterpret_cast<UIView *>(window)
                          : rootViewForScreen(this);

    if (width < 0)
        width = qMax(view.bounds.size.width - x, CGFloat(0));
    if (height < 0)
        height = qMax(view.bounds.size.height - y, CGFloat(0));

    CGRect captureRect = [view.window convertRect:CGRectMake(x, y, width, height) fromView:view];
    captureRect = CGRectIntersection(captureRect, view.window.bounds);

    QMacAutoReleasePool autoReleasePool;

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = NO;
    format.scale = devicePixelRatio();
    // Could be adjusted to support HDR in the future.
    format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;

    UIGraphicsImageRenderer *renderer = [[[UIGraphicsImageRenderer alloc]
        initWithSize:captureRect.size format:format]
        autorelease];

    UIImage *screenshot = [renderer imageWithActions:^(UIGraphicsImageRendererContext *rendererContext) {
        CGContextRef context = rendererContext.CGContext;
        CGContextTranslateCTM(context, -captureRect.origin.x, -captureRect.origin.y);

        // Draws the complete view hierarchy of view.window into the given rect, which
        // needs to be the same aspect ratio as the view.window's size. Since we've
        // translated the graphics context, and are potentially drawing into a smaller
        // context than the full window, the resulting image will be a subsection of the
        // full screen.
        //
        // TODO: Should only be run on the UI thread in the future. At
        // the time of writing, QScreen::grabWindow doesn't include any
        // requirements as to which thread it can be called from.
        [view.window drawViewHierarchyInRect:view.window.bounds afterScreenUpdates:NO];
    }];

    return QPixmap::fromImage(qt_mac_toQImage(screenshot.CGImage));
}

bool QIOSScreen::shouldPauseDisplayLinkWhenInactive() const
{
    // iPad 7 with iOS 18 has been observed to crash during swapBuffers
    // if the user enters split-view mode and drags the divider around.
    // This is likely a GL driver issue. To reduce the chance of hitting
    // this crash we pause the display link when the app is inactive.
    // We limit it to A10 devices, as the crash has not been observed on
    // other SoCs. See QTBUG-132314 for more information.

    static const bool isA10GPU = []{
        auto device = MTLCreateSystemDefaultDevice();
        return [device.name containsString:@"A10"];
    }();

    static const bool pauseWhenInactive = qEnvironmentVariableIntegerValue(
        "QT_IOS_PAUSE_DISPLAY_LINK_WHEN_INACTIVE").value_or(isA10GPU);
    return pauseWhenInactive;
}

#if !defined(Q_OS_VISIONOS)
UIScreen *QIOSScreen::uiScreen() const
{
    return m_uiScreen;
}
#endif

QT_END_NAMESPACE

#include "moc_qiosscreen.cpp"
