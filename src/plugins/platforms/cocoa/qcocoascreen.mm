// Copyright (C) 2017 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
// Qt-Security score:significant reason:default

#include <AppKit/AppKit.h>
#include <ScreenCaptureKit/ScreenCaptureKit.h>

#include "qcocoascreen.h"

#include "qcocoawindow.h"
#include "qcocoahelpers.h"
#include "qcocoaintegration.h"

#include <QtCore/qcoreapplication.h>
#include <QtGui/private/qcoregraphics_p.h>

#include <IOKit/graphics/IOGraphicsLib.h>

#include <QtGui/private/qwindow_p.h>
#include <QtGui/private/qhighdpiscaling_p.h>
#include <QtGui/private/qappleframerate_p.h>

#include <QtCore/private/qcore_mac_p.h>
#include <QtCore/private/qeventdispatcher_cf_p.h>

#include <QuartzCore/CADisplayLink.h>

// clang-format off
QT_DECLARE_NAMESPACED_OBJC_INTERFACE(QCocoaDisplayLinkTarget, NSObject
- (instancetype)initWithScreen:(QT_PREPEND_NAMESPACE(QCocoaScreen) *)screen;
- (void)displayLinkDidFire:(CADisplayLink *)displayLink;
)
// clang-format on

QT_BEGIN_NAMESPACE

namespace CoreGraphics {
    Q_NAMESPACE
    enum DisplayChange {
        ReconfiguredWithFlagsMissing = 0,
        Moved = kCGDisplayMovedFlag,
        SetMain = kCGDisplaySetMainFlag,
        SetMode = kCGDisplaySetModeFlag,
        Added = kCGDisplayAddFlag,
        Removed = kCGDisplayRemoveFlag,
        Enabled = kCGDisplayEnabledFlag,
        Disabled = kCGDisplayDisabledFlag,
        Mirrored = kCGDisplayMirrorFlag,
        UnMirrored = kCGDisplayUnMirrorFlag,
        DesktopShapeChanged = kCGDisplayDesktopShapeChangedFlag
    };
    Q_ENUM_NS(DisplayChange)
}

QMacNotificationObserver QCocoaScreen::s_screenParameterObserver;
CGDisplayReconfigurationCallBack QCocoaScreen::s_displayReconfigurationCallBack = nullptr;

void QCocoaScreen::initializeScreens()
{
    updateScreens();

    s_displayReconfigurationCallBack = [](CGDirectDisplayID displayId, CGDisplayChangeSummaryFlags flags, void *userInfo) {
        Q_UNUSED(userInfo);

        const bool beforeReconfigure = flags & kCGDisplayBeginConfigurationFlag;
        qCDebug(lcQpaScreen).verbosity(0) << "Display" << displayId
                << (beforeReconfigure ? "beginning" : "finished") << "reconfigure"
                << QFlags<CoreGraphics::DisplayChange>(flags);

        if (!beforeReconfigure)
            updateScreens();
    };
    CGDisplayRegisterReconfigurationCallback(s_displayReconfigurationCallBack, nullptr);

    s_screenParameterObserver = QMacNotificationObserver(NSApplication.sharedApplication,
        NSApplicationDidChangeScreenParametersNotification, [&]() {
            qCDebug(lcQpaScreen) << "Received screen parameter change notification";
            updateScreens();

            // The notification is posted when the EDR headroom of a display changes,
            // which might affect the rendering of windows that opt in to EDR.
            updateHdrWindows();
        });
}

/*
    Update the list of available QScreens, and the properties of existing screens.

    At this point we rely on the NSScreen.screens to be up to date.
*/
void QCocoaScreen::updateScreens()
{
    // Adding, updating, or removing a screen below might trigger
    // Qt or the application to move a window to a different screen,
    // recursing back here via QCocoaWindow::windowDidChangeScreen.
    // The update code is not re-entrant, so bail out if we end up
    // in this situation. The screens will stabilize eventually.
    static bool updatingScreens = false;
    if (updatingScreens) {
        qCInfo(lcQpaScreen) << "Skipping screen update, already updating";
        return;
    }
    QScopedValueRollback recursionGuard(updatingScreens, true);

    uint32_t displayCount = 0;
    if (CGGetOnlineDisplayList(0, nullptr, &displayCount) != kCGErrorSuccess)
        qFatal("Failed to get number of online displays");

    QVector<CGDirectDisplayID> onlineDisplays(displayCount);
    if (CGGetOnlineDisplayList(displayCount, onlineDisplays.data(), &displayCount) != kCGErrorSuccess)
        qFatal("Failed to get online displays");

    qCInfo(lcQpaScreen) << "Updating screens with" << displayCount
        << "online displays:" << onlineDisplays;

    // TODO: Verify whether we can always assume the main display is first
    int mainDisplayIndex = onlineDisplays.indexOf(CGMainDisplayID());
    if (mainDisplayIndex < 0) {
        qCWarning(lcQpaScreen) << "Main display not in list of online displays!";
    } else if (mainDisplayIndex > 0) {
        qCWarning(lcQpaScreen) << "Main display not first display, making sure it is";
        onlineDisplays.move(mainDisplayIndex, 0);
    }

    for (CGDirectDisplayID displayId : onlineDisplays) {
        Q_ASSERT(CGDisplayIsOnline(displayId));

        if (CGDisplayMirrorsDisplay(displayId))
            continue;

        // A single physical screen can map to multiple displays IDs,
        // depending on which GPU is in use or which physical port the
        // screen is connected to. By mapping the display ID to a UUID,
        // which are shared between displays that target the same screen,
        // we can pick an existing QScreen to update instead of needlessly
        // adding and removing QScreens.
        QCFType<CFUUIDRef> uuid = CGDisplayCreateUUIDFromDisplayID(displayId);
        Q_ASSERT(uuid);

        if (QCocoaScreen *existingScreen = QCocoaScreen::get(uuid)) {
            existingScreen->update(displayId);
            qCInfo(lcQpaScreen) << "Updated" << existingScreen;
            if (CGDisplayIsMain(displayId) && existingScreen != qGuiApp->primaryScreen()->handle()) {
                qCInfo(lcQpaScreen) << "Primary screen changed to" << existingScreen;
                QWindowSystemInterface::handlePrimaryScreenChanged(existingScreen);
            }
        } else {
            QCocoaScreen::add(displayId);
        }
    }

    for (QScreen *screen : QGuiApplication::screens()) {
        QCocoaScreen *platformScreen = static_cast<QCocoaScreen*>(screen->handle());
        if (!platformScreen->isOnline() || platformScreen->isMirroring())
            platformScreen->remove();
    }
}

void QCocoaScreen::add(CGDirectDisplayID displayId)
{
    const bool isPrimary = CGDisplayIsMain(displayId);
    QCocoaScreen *cocoaScreen = new QCocoaScreen(displayId);
    qCInfo(lcQpaScreen) << "Adding" << cocoaScreen
        << (isPrimary ? "as new primary screen" : "");
    QWindowSystemInterface::handleScreenAdded(cocoaScreen, isPrimary);
}

QCocoaScreen::QCocoaScreen(CGDirectDisplayID displayId)
    : QPlatformScreen(), m_displayId(displayId)
{
    update(m_displayId);
    m_cursor = new QCocoaCursor;
}

void QCocoaScreen::cleanupScreens()
{
    // Remove screens in reverse order to avoid crash in case of multiple screens
    for (QScreen *screen : backwards(QGuiApplication::screens()))
        static_cast<QCocoaScreen*>(screen->handle())->remove();

    Q_ASSERT(s_displayReconfigurationCallBack);
    CGDisplayRemoveReconfigurationCallback(s_displayReconfigurationCallBack, nullptr);
    s_displayReconfigurationCallBack = nullptr;

    s_screenParameterObserver.remove();
}

void QCocoaScreen::remove()
{
    // This may result in the application responding to QGuiApplication::screenRemoved
    // by moving the window to another screen, either by setGeometry, or by setScreen.
    // If the window isn't moved by the application, Qt will as a fallback move it to
    // the primary screen via setScreen. Due to the way setScreen works, this won't
    // actually recreate the window on the new screen, it will just assign the new
    // QScreen to the window. The associated NSWindow will have an NSScreen determined
    // by AppKit. AppKit will then move the window to another screen by changing the
    // geometry, and we will get a callback in QCocoaWindow::windowDidMove and then
    // QCocoaWindow::windowDidChangeScreen. At that point the window will appear to have
    // already changed its screen, but that's only true if comparing the Qt screens,
    // not when comparing the NSScreens.
    qCInfo(lcQpaScreen) << "Removing " << this;
    QWindowSystemInterface::handleScreenRemoved(this);
}

QCocoaScreen::~QCocoaScreen()
{
    Q_ASSERT_X(!screen(), "QCocoaScreen", "QScreen should be deleted first");

    delete m_cursor;

    invalidateDisplayLink();
}

void QCocoaScreen::update(CGDirectDisplayID displayId)
{
    if (displayId != m_displayId) {
        qCDebug(lcQpaScreen) << "Reconnecting" << this << "as display" << displayId;
        m_displayId = displayId;

        // The display link is tied to the NSScreen of the old display, so
        // recreate it, making sure we don't strand pending update requests.
        if (m_displayLink) {
            invalidateDisplayLink();
            if (hasPendingUpdateRequests())
                requestUpdate();
        }
    }

    Q_ASSERT(isOnline());

    // Some properties are only available via NSScreen
    NSScreen *nsScreen = nativeScreen();
    if (!nsScreen) {
        qCDebug(lcQpaScreen) << "Corresponding NSScreen not yet available. Deferring update";
        return;
    }

    const QRect previousGeometry = m_geometry;
    const QRect previousAvailableGeometry = m_availableGeometry;
    const qreal previousRefreshRate = m_refreshRate;
    const double previousRotation = m_rotation;

    // The reference screen for the geometry is always the primary screen
    QRectF primaryScreenGeometry = QRectF::fromCGRect(CGDisplayBounds(CGMainDisplayID()));
    m_geometry = qt_mac_flip(QRectF::fromCGRect(nsScreen.frame), primaryScreenGeometry).toRect();
    m_availableGeometry = qt_mac_flip(QRectF::fromCGRect(nsScreen.visibleFrame), primaryScreenGeometry).toRect();

    m_devicePixelRatio = nsScreen.backingScaleFactor;

    m_format = QImage::Format_RGB32;
    m_depth = NSBitsPerPixelFromDepth(nsScreen.depth);
    m_colorSpace = QColorSpace::fromIccProfile(QByteArray::fromNSData(nsScreen.colorSpace.ICCProfileData));
    if (!m_colorSpace.isValid()) {
        qCWarning(lcQpaScreen) << "Failed to parse ICC profile for" << nsScreen.colorSpace
                               << "with ICC data" << nsScreen.colorSpace.ICCProfileData
                               << "- Falling back to sRGB";
        m_colorSpace = QColorSpace::SRgb;
    }

    CGSize size = CGDisplayScreenSize(m_displayId);
    m_physicalSize = QSizeF(size.width, size.height);

    QCFType<CGDisplayModeRef> displayMode = CGDisplayCopyDisplayMode(m_displayId);
    float refresh = CGDisplayModeGetRefreshRate(displayMode);
    m_refreshRate = refresh > 0 ? refresh : 60.0;
    m_rotation = CGDisplayRotation(displayId);
    m_name = QString::fromNSString(nsScreen.localizedName);

    const bool didChangeGeometry = m_geometry != previousGeometry || m_availableGeometry != previousAvailableGeometry;

    if (m_rotation != previousRotation)
        QWindowSystemInterface::handleScreenOrientationChange(screen(), orientation());

    if (didChangeGeometry)
        QWindowSystemInterface::handleScreenGeometryChange(screen(), geometry(), availableGeometry());
    if (m_refreshRate != previousRefreshRate)
        QWindowSystemInterface::handleScreenRefreshRateChange(screen(), m_refreshRate);
}

// ----------------------- Display link -----------------------

Q_LOGGING_CATEGORY(lcQpaScreenUpdates, "qt.qpa.screen.updates", QtCriticalMsg);

bool QCocoaScreen::requestUpdate()
{
    Q_ASSERT(m_displayId);

    if (!isOnline()) {
        qCDebug(lcQpaScreenUpdates) << this << "is not online. Ignoring update request";
        return false;
    }

    if (!m_displayLink) {
        NSScreen *nsScreen = nativeScreen();
        if (!nsScreen) {
            qCWarning(lcQpaScreenUpdates)
                    << "No NSScreen for" << this << "- can't create display link";
            return false;
        }

        qCDebug(lcQpaScreenUpdates) << "Creating display link for" << this;

        // The display link retains its target, and the target doesn't retain us,
        // so we invalidate the display link before the screen goes away.
        auto *target = [[[QCocoaDisplayLinkTarget alloc] initWithScreen:this] autorelease];
        m_displayLink = [[nsScreen displayLinkWithTarget:target
                                                selector:@selector(displayLinkDidFire:)] retain];
        if (!m_displayLink) {
            qCWarning(lcQpaScreenUpdates) << "Failed to create display link for" << this;
            return false;
        }

        // Unlike CVDisplayLink, the callback is delivered on the run loop the display
        // link is added to, so there's no need to marshal it over to the main thread.
        // Use the common modes, so that we keep delivering update requests during
        // event tracking (live resize, menus) and modal sessions.
        [m_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];

        // During live window resizing -[NSWindow _resizeWithEvent:] will spin a local event loop
        // in event-tracking mode, dequeuing only the mouse drag events needed to update the window's
        // frame. It will repeatedly spin this loop until no longer receiving any mouse drag events,
        // and will then update the frame (effectively coalescing/compressing the events). Unfortunately
        // the events are pulled out using -[NSApplication nextEventMatchingEventMask:untilDate:inMode:dequeue:]
        // which internally uses CFRunLoopRunSpecific, so the event loop will also process GCD queues and other
        // runloop sources that have been added to the tracking mode. This includes the display-link
        // source that we use to deliver update requests. If the
        // subsequent delivery of the update-request on the main thread stalls due to inefficient
        // user code, the NSEventThread will have had time to deliver additional mouse drag events,
        // and the logic in -[NSWindow _resizeWithEvent:] will keep on compressing events and never
        // get to the point of actually updating the window frame, making it seem like the window
        // is stuck in its original size. Only when the user stops moving their mouse, and the event
        // queue is completely drained of drag events, will the window frame be updated.

        // By keeping an event tap listening for drag events, registered as a version 1 runloop source,
        // we prevent the GCD source from being prioritized, giving the resize logic enough time
        // to finish coalescing the events. This is incidental, but conveniently gives us the behavior
        // we are looking for, interleaving display-link updates and resize events.
        static CFMachPortRef eventTap = []() {
            CFMachPortRef eventTap = CGEventTapCreateForPid(getpid(), kCGTailAppendEventTap,
                kCGEventTapOptionListenOnly, NSEventMaskLeftMouseDragged,
                [](CGEventTapProxy, CGEventType type, CGEventRef event, void *) -> CGEventRef {
                    if (type == kCGEventTapDisabledByTimeout)
                        qCWarning(lcQpaScreenUpdates) << "Event tap disabled due to timeout!";
                    return event; // Listen only tap, so what we return doesn't really matter
                }, nullptr);
            CGEventTapEnable(eventTap, false); // Event taps are normally enabled when created
            static CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);

            NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
            [center addObserverForName:NSWindowWillStartLiveResizeNotification object:nil queue:nil
                usingBlock:^(NSNotification *notification) {
                    qCDebug(lcQpaScreenUpdates) << "Live resize of" << notification.object
                        << "started. Enabling event tap";
                    CGEventTapEnable(eventTap, true);
                }];
            [center addObserverForName:NSWindowDidEndLiveResizeNotification object:nil queue:nil
                usingBlock:^(NSNotification *notification) {
                    qCDebug(lcQpaScreenUpdates) << "Live resize of" << notification.object
                        << "ended. Disabling event tap";
                    CGEventTapEnable(eventTap, false);
                }];
            return eventTap;
        }();
        Q_UNUSED(eventTap);
    }

    // Make sure the display link runs fast enough for the window that
    // requested the update. During delivery this happens once all the
    // windows have been processed instead.
    if (!m_deliveringUpdateRequests)
        updateDisplayLinkFrameRate();

    if (m_displayLink.paused) {
        qCDebug(lcQpaScreenUpdates) << "Resuming display link for" << this;
        m_displayLink.paused = NO;
    }

    return true;
}

void QCocoaScreen::deliverUpdateRequests(double targetTimestamp, double frameInterval)
{
    Q_ASSERT(NSThread.isMainThread);

    if (!isOnline()) {
        qCDebug(lcQpaScreenUpdates) << this << "is not online. Ignoring update request delivery";
        return;
    }

    // Delivering an update request might spin a nested event loop,
    // which could result in the display link firing again.
    if (m_deliveringUpdateRequests) {
        qCDebug(lcQpaScreenUpdates) << "Skipping recursive display link callback for" << this;
        return;
    }
    QScopedValueRollback recursionGuard(m_deliveringUpdateRequests, true);

    QMacAutoReleasePool pool;

    qCDebug(lcQpaScreenUpdates) << "Display link callback for" << this << "targeting"
                                << targetTimestamp << "with frame interval" << frameInterval;

    bool anyPendingUpdateRequests = false;
    std::optional<QAppleFrameRateRange> frameRateRange;

    auto windows = QGuiApplication::allWindows();
    for (int i = 0; i < windows.size(); ++i) {
        QWindow *window = windows.at(i);
        if (window->screen() != screen())
            continue;

        QPointer<QCocoaWindow> platformWindow = static_cast<QCocoaWindow *>(window->handle());
        if (!platformWindow)
            continue;

        if (!platformWindow->hasPendingUpdateRequest())
            continue;

        // Skip windows that are not doing update requests via display link
        if (!platformWindow->updatesWithDisplayLink())
            continue;

        // The display link runs fast enough for the most demanding window,
        // so windows that asked for a lower frame rate skip some frames.
        auto &frameRatePreference = platformWindow->frameRatePreference();
        frameRatePreference.update(window);
        if (frameRatePreference.shouldDeliverFrame(targetTimestamp, frameInterval)) {
            frameRatePreference.frameDelivered(targetTimestamp);
            qt_window_private(window)->updateRequestInterval =
                    frameRatePreference.effectiveFrameInterval(frameInterval);
            // The display link may have been restarted without going through
            // QCocoaWindow::requestUpdate(), e.g. after a screen change.
            platformWindow->stopFallbackUpdateTimer();
            platformWindow->deliverUpdateRequest();

            // platform window can be destroyed in deliverUpdateRequest()
            if (!platformWindow)
                continue;

            // Only valid during delivery, so that frames driven by other means,
            // such as expose events, don't use the paced interval.
            qt_window_private(window)->updateRequestInterval = 0;
        }

        // The update request delivery could result in another request
        // from the window, or the platform window could decide to not
        // deliver the request at this time.
        if (platformWindow->hasPendingUpdateRequest()) {
            anyPendingUpdateRequests = true;
            const auto range = platformWindow->frameRatePreference().update(window);
            frameRateRange = frameRateRange ? frameRateRange->unitedWith(range) : range;
        }
    }

    if (frameRateRange && m_displayLink)
        setDisplayLinkFrameRate(*frameRateRange);

    // A window we looked at before delivering to another one may have gotten an
    // update request in the meantime, e.g. when one window drives the frames of
    // another. Its request won't reach us again, as it's already pending, so look
    // at all the windows again before pausing.
    if (!anyPendingUpdateRequests)
        anyPendingUpdateRequests = updateDisplayLinkFrameRate();

    if (!anyPendingUpdateRequests && m_displayLink) {
        // Unlike a CVDisplayLink there's no thread to stop and start, so
        // pausing and resuming is cheap, and avoids waking up the main
        // thread for every display refresh when nothing is animating.
        qCDebug(lcQpaScreenUpdates)
                << "No pending update requests. Pausing display link for" << this;
        m_displayLink.paused = YES;
    }
}

bool QCocoaScreen::hasPendingUpdateRequests() const
{
    const auto windows = QGuiApplication::allWindows();
    for (auto *window : windows) {
        if (window->screen() != screen())
            continue;

        auto *platformWindow = static_cast<QCocoaWindow *>(window->handle());
        if (!platformWindow)
            continue;

        // We intentionally don't check updatesWithDisplayLink() here, as
        // that needs a fully constructed platform window. Timer based
        // requests will at most keep the display link running one more
        // frame, as deliverUpdateRequests() does take it into account.
        if (platformWindow->hasPendingUpdateRequest())
            return true;
    }
    return false;
}

// Updates the display link's frame rate range from the windows that have pending
// update requests, and returns whether there are any.
bool QCocoaScreen::updateDisplayLinkFrameRate()
{
    std::optional<QAppleFrameRateRange> frameRateRange;
    const auto windows = QGuiApplication::allWindows();
    for (auto *window : windows) {
        if (window->screen() != screen())
            continue;

        auto *platformWindow = static_cast<QCocoaWindow *>(window->handle());
        if (!platformWindow || !platformWindow->hasPendingUpdateRequest()
            || !platformWindow->updatesWithDisplayLink()) {
            continue;
        }

        const auto range = platformWindow->frameRatePreference().update(window);
        frameRateRange = frameRateRange ? frameRateRange->unitedWith(range) : range;
    }

    if (frameRateRange && m_displayLink)
        setDisplayLinkFrameRate(*frameRateRange);
    return frameRateRange.has_value();
}

void QCocoaScreen::setDisplayLinkFrameRate(const QAppleFrameRateRange &range)
{
    Q_ASSERT(m_displayLink);

    // CoreAnimation throws for invalid ranges. QAppleFrameRateRange
    // never produces those, but let's be defensive about it.
    if (!range.isValid()) {
        qCWarning(lcQpaScreenUpdates) << "Refusing to set invalid" << range << "on display link";
        return;
    }

    const CAFrameRateRange current = m_displayLink.preferredFrameRateRange;
    if (QAppleFrameRateRange(current.minimum, current.maximum, current.preferred) == range)
        return;

    qCDebug(lcQpaScreenUpdates) << "Setting display link frame rate for" << this << "to" << range;
    m_displayLink.preferredFrameRateRange =
            CAFrameRateRangeMake(range.minimum, range.maximum, range.preferred);
}

void QCocoaScreen::maybePauseDisplayLink()
{
    if (!m_displayLink || m_displayLink.paused)
        return;

    if (hasPendingUpdateRequests())
        return;

    qCDebug(lcQpaScreenUpdates) << "Pausing display link for" << this;
    m_displayLink.paused = YES;
}

void QCocoaScreen::invalidateDisplayLink()
{
    if (!m_displayLink)
        return;

    qCDebug(lcQpaScreenUpdates) << "Invalidating display link for" << this;
    [m_displayLink invalidate];
    [m_displayLink release];
    m_displayLink = nullptr;
}

// -----------------------------------------------------------

void QCocoaScreen::updateHdrWindows()
{
    if (@available(macOS 14, *)) {
        for (auto *window : QGuiApplication::allWindows()) {
            auto *platformWindow = static_cast<QCocoaWindow*>(window->handle());
            if (!platformWindow)
                continue;

            NSView *view = platformWindow->view();

            if (!view.layer.wantsExtendedDynamicRangeContent)
                continue;

            [view setNeedsDisplay:YES];
        }
    }
}

// -----------------------------------------------------------

QPlatformScreen::SubpixelAntialiasingType QCocoaScreen::subpixelAntialiasingTypeHint() const
{
    QPlatformScreen::SubpixelAntialiasingType type = QPlatformScreen::subpixelAntialiasingTypeHint();
    if (type == QPlatformScreen::Subpixel_None) {
        // Every OSX machine has RGB pixels unless a peculiar or rotated non-Apple screen is attached
        type = QPlatformScreen::Subpixel_RGB;
    }
    return type;
}

Qt::ScreenOrientation QCocoaScreen::orientation() const
{
    if (m_rotation == 0)
        return Qt::LandscapeOrientation;
    if (m_rotation == 90)
        return Qt::PortraitOrientation;
    if (m_rotation == 180)
        return Qt::InvertedLandscapeOrientation;
    if (m_rotation == 270)
        return Qt::InvertedPortraitOrientation;
    return QPlatformScreen::orientation();
}

QWindow *QCocoaScreen::topLevelAt(const QPoint &point) const
{
    __block QWindow *window = nullptr;
    [NSApp enumerateWindowsWithOptions:NSWindowListOrderedFrontToBack
        usingBlock:^(NSWindow *nsWindow, BOOL *stop) {
            if (!nsWindow)
                return;

            // Continue the search if the window does not belong to Qt
            if (![nsWindow conformsToProtocol:@protocol(QNSWindowProtocol)])
                return;

            QCocoaWindow *cocoaWindow = qnsview_cast(nsWindow.contentView).platformWindow;
            if (!cocoaWindow)
                return;

            QWindow *w = cocoaWindow->window();
            if (!w->isVisible())
                return;

            auto nativeGeometry = QHighDpi::toNativePixels(w->geometry(), w);
            if (!nativeGeometry.contains(point))
                return;

            QRegion mask = QHighDpi::toNativeLocalPosition(w->mask(), w);
            if (!mask.isEmpty() && !mask.contains(point - nativeGeometry.topLeft()))
                return;

            window = w;

            // Continue the search if the window is not a top-level window
            if (!window->isTopLevel())
                return;

            *stop = true;
        }
    ];

    return window;
}

/*!
    \internal

    Coordinates are in screen coordinates if \a view is 0, otherwise they are in view
    coordinates.
*/
QPixmap QCocoaScreen::grabWindow(WId view, int x, int y, int width, int height) const
{
    // ScreenCaptureKit brings down WindowServer on macOS 14 x86_64 VMs in CI
    if (!QGuiApplicationPrivate::platformIntegration()->hasCapability(
        QPlatformIntegration::ScreenWindowGrabbing)) {
        qCWarning(lcQpaScreen) << "Ignoring grabWindow to not bring down WindowServer";
        return {};
    }

    auto grabFromDisplay = [](CGDirectDisplayID displayId, const QRect &grabRect) -> QPixmap {
        QMacAutoReleasePool pool;

        const qreal scale = QCocoaScreen::nativeScreenForDisplayId(displayId).backingScaleFactor;

        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        auto cleanup = qScopeGuard([sem]() { dispatch_release(sem); });

        auto captureShareableContent = [sem](void (^capture)(SCShareableContent *)) {
            // Try capturing all applications first, as that's the expectation of
            // grabWindow. This will also trigger the permission system prompt on
            // first use, matching the behavior of CGDisplayCreateImageForRect.
            [SCShareableContent getShareableContentWithCompletionHandler:
                ^(SCShareableContent *content, NSError *error) {
                    if (error)
                        qCDebug(lcQpaScreen) << "Failed to capture all windows" << error;
                    if (content) {
                        capture(content);
                        return;
                    }
                    // Fall back to capturing only our app, again matching the behavior
                    // of CGDisplayCreateImageForRect when we don't have permission to
                    // capture all applications. This also includes the Dock and wallpaper.
                    [SCShareableContent getCurrentProcessShareableContentWithCompletionHandler:
                        ^(SCShareableContent *content, NSError *error) {
                            if (error)
                                qCWarning(lcQpaScreen) << "Failed to capture own windows" << error;
                            if (content)
                                capture(content);
                            else
                                dispatch_semaphore_signal(sem);
                        }
                    ];
                }
            ];
        };

        __block QImage image;
        captureShareableContent(^(SCShareableContent *content) {
            Q_ASSERT(content);

            QMacAutoReleasePool pool;

            SCDisplay *scDisplay = nil;
            for (SCDisplay *d in content.displays) {
                if (d.displayID == displayId) {
                    scDisplay = d;
                    break;
                }
            }
            if (!scDisplay) {
                qCWarning(lcQpaScreen) << "No SCDisplay for display" << displayId;
                dispatch_semaphore_signal(sem);
                return;
            }

            SCContentFilter *filter = [[[SCContentFilter alloc]
                initWithDisplay:scDisplay
                includingApplications:content.applications
                exceptingWindows:@[]] autorelease];
            filter.includeMenuBar = YES;

            SCStreamConfiguration *config = [[SCStreamConfiguration new] autorelease];
            config.sourceRect = grabRect.toCGRect();
            config.width = qRound(grabRect.width()  * scale);
            config.height = qRound(grabRect.height() * scale);
            config.showsCursor = NO;
            config.capturesAudio = NO;
            config.ignoreShadowsDisplay = NO;
            config.ignoreShadowsSingleWindow = NO;

            [SCScreenshotManager captureImageWithFilter:filter configuration:config
                completionHandler:^(CGImageRef cgImage, NSError *error) {
                    if (error)
                        qCWarning(lcQpaScreen) << "Failed screen capture" << error;
                    else if (cgImage)
                        image = qt_mac_toQImage(cgImage);
                    dispatch_semaphore_signal(sem);
                }
            ];
        });

        // Wait for screen capture to complete
        if (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0) {
            qCWarning(lcQpaScreen) << "Screen capture timed out for display" << displayId;
            return QPixmap();
        }

        QPixmap pixmap = QPixmap::fromImage(image);
        pixmap.setDevicePixelRatio(scale);
        return pixmap;
    };

    QRect grabRect = QRect(x, y, width, height);
    qCDebug(lcQpaScreen) << "input grab rect" << grabRect;

    if (view) {
        // Window local coordinates, so turn into global
        NSView *nsView = reinterpret_cast<NSView*>(view);
        NSPoint windowPoint = [nsView convertPoint:NSMakePoint(0, 0) toView:nil];
        NSRect screenRect = [nsView.window convertRectToScreen:NSMakeRect(windowPoint.x, windowPoint.y, 1, 1)];
        QPoint position = mapFromNative(screenRect.origin).toPoint();
        QSize size = QRectF::fromCGRect(NSRectToCGRect(nsView.bounds)).toRect().size();
        QRect windowRect = QRect(position, size);
        if (!grabRect.isValid())
            grabRect = windowRect;
        else
            grabRect.translate(windowRect.topLeft());
    } else {
        // Screen global coordinates
        if (!grabRect.isValid())
            grabRect = geometry();
    }

    // Find which displays to grab from
    const int maxDisplays = 128;
    CGDirectDisplayID displays[maxDisplays];
    CGDisplayCount displayCount;
    CGRect cgRect = grabRect.isValid() ? grabRect.toCGRect() : CGRectInfinite;
    const CGDisplayErr err = CGGetDisplaysWithRect(cgRect, maxDisplays, displays, &displayCount);
    if (err || displayCount == 0)
        return QPixmap();

    qCDebug(lcQpaScreen) << "final grab rect" << grabRect << "from" << displayCount << "displays";

    // Grab images from each display, accumulating the global bounding box of the
    // captured content. The output pixmap covers exactly that bounding box, so
    // empty virtual-desktop space inside grabRect is not padded into the result.
    QVector<QPixmap> pixmaps;
    QVector<QRect> globalGrabBounds;
    QRect outputRect;
    for (uint i = 0; i < displayCount; ++i) {
        auto display = displays[i];
        const QRect displayBounds = QRectF::fromCGRect(CGDisplayBounds(display)).toRect();
        const QRect grabBounds = displayBounds.intersected(grabRect);
        if (grabBounds.isNull()) {
            globalGrabBounds.append(QRect());
            pixmaps.append(QPixmap());
            continue;
        }
        const QRect displayLocalGrabBounds = QRect(QPoint(grabBounds.topLeft() - displayBounds.topLeft()), grabBounds.size());

        qCDebug(lcQpaScreen) << "grab display" << i << "global" << grabBounds << "local" << displayLocalGrabBounds;
        QPixmap displayPixmap = grabFromDisplay(display, displayLocalGrabBounds);
        // Fast path for when grabbing from a single screen only
        if (displayCount == 1)
            return displayPixmap;

        qCDebug(lcQpaScreen) << "grab sub-image size" << displayPixmap.size() << "devicePixelRatio" << displayPixmap.devicePixelRatio();
        pixmaps.append(displayPixmap);
        globalGrabBounds.append(grabBounds);
        outputRect = outputRect.united(grabBounds);
    }

    // Determine the highest dpr, which becomes the dpr for the returned pixmap.
    qreal dpr = 1.0;
    for (uint i = 0; i < displayCount; ++i)
        dpr = qMax(dpr, pixmaps.at(i).devicePixelRatio());

    // Allocate target pixmap and draw each screen's content
    qCDebug(lcQpaScreen) << "Create grap pixmap" << outputRect.size() << "at devicePixelRatio" << dpr;
    QPixmap windowPixmap(outputRect.size() * dpr);
    windowPixmap.setDevicePixelRatio(dpr);
    windowPixmap.fill(Qt::transparent);
    QPainter painter(&windowPixmap);
    for (uint i = 0; i < displayCount; ++i) {
        const QRect grabBounds = globalGrabBounds.at(i);
        if (grabBounds.isNull())
            continue;
        const QRect dest(grabBounds.topLeft() - outputRect.topLeft(), grabBounds.size());
        painter.drawPixmap(dest, pixmaps.at(i));
    }

    return windowPixmap;
}

bool QCocoaScreen::isOnline() const
{
    // When a display is disconnected CGDisplayIsOnline and other CGDisplay
    // functions that take a displayId will not return false, but will start
    // returning -1 to signal that the displayId is invalid. Some functions
    // will also assert or even crash in this case, so it's important that
    // we double check if a display is online before calling other functions.
    int isOnline = CGDisplayIsOnline(m_displayId);
    static const int kCGDisplayIsDisconnected = 0xffffffff;
    return isOnline != kCGDisplayIsDisconnected && isOnline;
}

/*
    Returns true if a screen is mirroring another screen
*/
bool QCocoaScreen::isMirroring() const
{
    if (!isOnline())
        return false;

    return CGDisplayMirrorsDisplay(m_displayId);
}

/*!
    The screen used as a reference for global window geometry
*/
QCocoaScreen *QCocoaScreen::primaryScreen()
{
    // Note: The primary screen that Qt knows about may not match the current CGMainDisplayID()
    // if macOS has not yet been able to inform us that the main display has changed, but we
    // will update the primary screen accordingly once the reconfiguration callback comes in.
    return static_cast<QCocoaScreen *>(QGuiApplication::primaryScreen()->handle());
}

QList<QPlatformScreen*> QCocoaScreen::virtualSiblings() const
{
    QList<QPlatformScreen*> siblings;

    // Screens on macOS are always part of the same virtual desktop
    for (QScreen *screen : QGuiApplication::screens())
        siblings << screen->handle();

    return siblings;
}

QCocoaScreen *QCocoaScreen::get(NSScreen *nsScreen)
{
    auto displayId = nsScreen.qt_displayId;
    auto *cocoaScreen = get(displayId);
    if (!cocoaScreen) {
        qCWarning(lcQpaScreen) << "Failed to map" << nsScreen
            << "to QCocoaScreen. Doing last minute update.";
        updateScreens();
        cocoaScreen = get(displayId);
        if (!cocoaScreen)
            qCWarning(lcQpaScreen) << "Last minute update failed!";
    }
    return cocoaScreen;
}

QCocoaScreen *QCocoaScreen::get(CGDirectDisplayID displayId)
{
    for (QScreen *screen : QGuiApplication::screens()) {
        QCocoaScreen *cocoaScreen = static_cast<QCocoaScreen*>(screen->handle());
        if (cocoaScreen->m_displayId == displayId)
            return cocoaScreen;
    }

    return nullptr;
}

QCocoaScreen *QCocoaScreen::get(CFUUIDRef uuid)
{
    for (QScreen *screen : QGuiApplication::screens()) {
        auto *platformScreen = static_cast<QCocoaScreen*>(screen->handle());
        if (!platformScreen->isOnline())
            continue;

        auto displayId = platformScreen->displayId();
        QCFType<CFUUIDRef> candidateUuid(CGDisplayCreateUUIDFromDisplayID(displayId));
        Q_ASSERT(candidateUuid);

        if (candidateUuid == uuid)
            return platformScreen;
    }

    return nullptr;
}

NSScreen *QCocoaScreen::nativeScreenForDisplayId(CGDirectDisplayID displayId)
{
    for (NSScreen *screen in NSScreen.screens) {
        if (screen.qt_displayId == displayId)
            return screen;
    }
    return nil;
}

NSScreen *QCocoaScreen::nativeScreen() const
{
    if (!m_displayId)
        return nil; // The display has been disconnected

    return nativeScreenForDisplayId(m_displayId);
}

CGPoint QCocoaScreen::mapToNative(const QPointF &pos, QCocoaScreen *screen)
{
    Q_ASSERT(screen);
    return qt_mac_flip(pos, screen->geometry()).toCGPoint();
}

CGRect QCocoaScreen::mapToNative(const QRectF &rect, QCocoaScreen *screen)
{
    Q_ASSERT(screen);
    return qt_mac_flip(rect, screen->geometry()).toCGRect();
}

QPointF QCocoaScreen::mapFromNative(CGPoint pos, QCocoaScreen *screen)
{
    Q_ASSERT(screen);
    return qt_mac_flip(QPointF::fromCGPoint(pos), screen->geometry());
}

QRectF QCocoaScreen::mapFromNative(CGRect rect, QCocoaScreen *screen)
{
    Q_ASSERT(screen);
    return qt_mac_flip(QRectF::fromCGRect(rect), screen->geometry());
}

#ifndef QT_NO_DEBUG_STREAM
QDebug operator<<(QDebug debug, const QCocoaScreen *screen)
{
    QDebugStateSaver saver(debug);
    debug.nospace();
    debug << "QCocoaScreen(" << (const void *)screen;
    if (screen) {
        debug << ", " << screen->name();
        if (screen->isOnline()) {
            if (CGDisplayIsAsleep(screen->displayId()))
                debug << ", Sleeping";
            if (auto mirroring = CGDisplayMirrorsDisplay(screen->displayId()))
                debug << ", mirroring=" << mirroring;
        } else {
            debug << ", Offline";
        }
        debug << ", " << screen->geometry();
        debug << ", dpr=" << screen->devicePixelRatio();
        debug << ", displayId=" << screen->displayId();

        if (auto nativeScreen = screen->nativeScreen())
            debug << ", " << nativeScreen;
    }
    debug << ')';
    return debug;
}
#endif // !QT_NO_DEBUG_STREAM

QT_END_NAMESPACE

#include "qcocoascreen.moc"

@implementation QCocoaDisplayLinkTarget {
    QT_PREPEND_NAMESPACE(QCocoaScreen) * m_screen;
}

- (instancetype)initWithScreen:(QT_PREPEND_NAMESPACE(QCocoaScreen) *)screen
{
    if ((self = [super init]))
        m_screen = screen;
    return self;
}

- (void)displayLinkDidFire:(CADisplayLink *)displayLink
{
    // FIXME: It would be nice if update requests would include timing info
    m_screen->deliverUpdateRequests(displayLink.targetTimestamp,
                                    displayLink.targetTimestamp - displayLink.timestamp);
}

@end

@implementation NSScreen (QtExtras)

- (CGDirectDisplayID)qt_displayId
{
    return [self.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
}

@end
