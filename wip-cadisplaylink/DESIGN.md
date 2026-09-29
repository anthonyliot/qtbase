# Design panel output (2026-09-26)

Multi-agent design: three competing public API designs (minimal `qreal preferredFrameRate`,
full-fidelity `QFrameRateRange`, intent-based `QFrameRateHint`), scored by three judges (Qt API
reviewer, pro video app lead, platform maintainer). The minimal design won 2 of 3, with grafts.
The prototype on this branch implements the core of it: `QWindow::preferredFrameRate`, the QPA
hooks, exact-rate selection with the never-below rule, gcd-based sharing of the display link,
timer-path pacing, and opt-in Widgets pacing. Not done yet from this spec: the
`QFrameRatePacer` refactor, `UpdateRequestTiming`, QQuickWidget, and the nested event loop
handling for paced Widgets (see "Widgets plan", step 5).

Note: the panel-refresh caveat in the spec refers to a first, flawed measurement run; the
corrected run is in VIDEO.md.

## Judges' scores

* judge 1 winner: QWindow::preferredFrameRate, minimal-first (one qreal property; ranges and presentation ti
* judge 2 winner: QFrameRateRange: a full-fidelity frame-rate range value type, set through QWindow::preferr
* judge 3 winner: QWindow::preferredFrameRate, minimal-first (one qreal property)

## API spec

The bench run you started has finished. On this 120 Hz ProMotion MacBook Pro panel, 48 and 80 are not reachable: 48 comes out at 60 frames per second and 80 at 120. The run also found a problem: asking for exactly 120 stopped delivery. Below is the final spec: the minimal single-number design, which two of the three judges picked, plus the grafts they recommended. The one change from the original design is that Qt now picks an exact rate itself before asking CoreAnimation, so every mapping lands on a rate that was measured today.

# 0. What today's run measured

Results are in `/tmp/video-rates`, using strict (r,r,r) ranges set through `QT_APPLE_PREFERRED_FRAME_RATE_RANGE`. Rates are steady-state frames per second.

| Requested | Delivered |
|---|---|
| default | 119.8 |
| 23.976 | 24.0 |
| 24 | 24.0 (noisy, and its trace failed) |
| 25 | 24.0 |
| 29.97 | 29.8 |
| 30 | 29.8 |
| 40 | 40.0 |
| 48 | 60.0 |
| 50 | 59.4 |
| 59.94 | 60.0 |
| 60 | 60.0 |
| 80 | 120.0 |
| 120 | **0.00** |

- **CoreAnimation only runs this panel at 120/n.** At the 48 request the link never ran at 48 Hz: if it had, Qt's pacing would have delivered 48, not 60. Exact rates on this panel are 120, 60, 40, 30, 24, 20 and so on.
- **The 120 request stalled.** `/tmp/video-rates/120.log` shows 15 frames, then 1, then 0 for 11 seconds while the window stayed exposed, with lostupdates=0. The cause is unknown. The spec below never sends (M,M,M) to CoreAnimation; a request for the maximum becomes `CAFrameRateRangeDefault`, which is the "default" row (119.8).
- **The panel-refresh numbers from the xctrace Display traces don't match the delivered rates.** At 48, 50 and 59.94 the trace shows 100% 30 Hz intervals while 60 frames per second were delivered. Default shows a 37.9 Hz average while 120 were delivered. Until the panel rate is re-measured (for example with `wip-cadisplaylink/bench/panel-rate-ab.sh`), don't cite panel refresh rates, including "the panel drops to 60 Hz".

# 1. Header declarations (qtbase)

## `/Users/anthony.liot/Desktop/bitbucket/qt5/qtbase/src/gui/kernel/qwindow.h`

Place it after the `opacity` property. This is the only public API in this step: no new public header.

```cpp
    Q_PROPERTY(qreal preferredFrameRate READ preferredFrameRate WRITE setPreferredFrameRate
               RESET resetPreferredFrameRate NOTIFY preferredFrameRateChanged
               REVISION(6, 13))
public:
    qreal preferredFrameRate() const;
    void setPreferredFrameRate(qreal framesPerSecond);
    void resetPreferredFrameRate();
Q_SIGNALS:
    Q_REVISION(6, 13) void preferredFrameRateChanged(qreal preferredFrameRate);  // opacityChanged precedent
```

## `.../src/gui/kernel/qwindow.cpp`

```cpp
qreal QWindow::preferredFrameRate() const { Q_D(const QWindow); return d->preferredFrameRate; }

void QWindow::setPreferredFrameRate(qreal framesPerSecond)
{
    Q_D(QWindow);
    if (!qIsFinite(framesPerSecond) || framesPerSecond < 0) {
        qWarning("QWindow::setPreferredFrameRate: Ignoring invalid frame rate %g, using 0 (no preference)",
                 framesPerSecond);
        framesPerSecond = 0;
    }
    if (framesPerSecond == d->preferredFrameRate)
        return;
    d->preferredFrameRate = framesPerSecond;
    if (d->platformWindow)
        d->platformWindow->setPreferredFrameRate(framesPerSecond);
    emit preferredFrameRateChanged(framesPerSecond);   // emitted before create() too
}

void QWindow::resetPreferredFrameRate() { setPreferredFrameRate(0); }
```

## `.../src/gui/kernel/qwindow_p.h` (private)

`UpdateRequestTiming` replaces `double updateRequestInterval`. This is graft 3 and the groundwork for the later timing API.

```cpp
#include <chrono>
class Q_GUI_EXPORT QWindowPrivate : public QObjectPrivate {
    ...
    qreal preferredFrameRate = 0;                   // 0 = no preference
    struct UpdateRequestTiming {
        using Clock = std::chrono::steady_clock;
        Clock::time_point timestamp;                // refresh the link fired for (CADisplayLink.timestamp)
        Clock::time_point targetTimestamp;          // expected on-glass time; epoch if unknown
        std::chrono::nanoseconds refreshInterval{}; // link interval
        std::chrono::nanoseconds frameInterval{};   // this window's paced interval (n * refreshInterval)
        quint64 sequenceNumber = 0;                 // paced deliveries to this window
        bool isValid() const noexcept { return frameInterval.count() > 0; }
    };
    UpdateRequestTiming updateRequestTiming;        // valid only during paced delivery, reset afterwards
};
```

## `.../src/gui/kernel/qplatformwindow.h` (QPA hook, next to `setOpacity()`)

```cpp
    virtual void setPreferredFrameRate(qreal framesPerSecond);   // default implementation does nothing
```

Its QPA doc: called when `QWindow::preferredFrameRate` changes while the platform window exists. Platform windows read `window()->preferredFrameRate()` when they are created, when they recreate a native surface, and whenever they pace a request. Reimplement it to re-evaluate a running display link right away.

## `.../src/gui/kernel/qplatformwindow_p.h`

Add `QElapsedTimer lastUpdateRequestDelivery; quint64 updateRequestSequence = 0;` to `QPlatformWindowPrivate`.

## New `.../src/gui/kernel/qframeratepacer_p.h/.cpp`

QtGui-private, all platforms, plain C++ (graft 1). The pacing half of `qappleframerate.cpp` moves here.

```cpp
class Q_GUI_EXPORT QFrameRatePacer
{
public:
    struct Range {                                 // Hz, 0 = unset; same meaning as CAFrameRateRange
        qreal minimum = 0, maximum = 0, preferred = 0;
        constexpr bool isDefault() const noexcept { return !minimum && !maximum && !preferred; }
        static constexpr Range fromPreferredFrameRate(qreal fps) noexcept { return { fps, 0, fps }; }
    };
    void setRange(const Range &range) noexcept;
    const Range &range() const noexcept;
    //   n = max(1, floor(T/L + 0.5 - 1e-3)), T = 1/preferred, else 1/maximum, else n = 1  (today's rule)
    //   if minimum > 0: n = min(n, max(1, floor((1/minimum)/L * 1.01)))   (never below minimum, 1%)
    int framesPerDelivery(double linkInterval) const noexcept;
    bool shouldDeliverFrame(double targetTimestamp, double linkInterval) const noexcept; // elapsed >= (n-0.5)*L
    void frameDelivered(double targetTimestamp) noexcept;                                // ++sequence
    double effectiveFrameInterval(double linkInterval) const noexcept;                   // n * L
    quint64 sequenceNumber() const noexcept;
    // Shared-link rate. Returns 0 (system default) if any pending range is default or
    // g = gcd(n_i at L = 1/maximumRate) == 1; otherwise maximumRate / g.
    static qreal linkRate(QSpan<const Range> pending, qreal maximumRate) noexcept;
};
```

The public API maps to `{fps, 0, fps}`, so only the floor term applies. Ranges from the private property keep today's nearest rule. `L` is the link's nominal interval (`targetTimestamp - timestamp`), so decisions don't jitter. Picking the link rate by gcd (graft 2) means 24 next to 60 on 120 Hz gives gcd(5,2)=1, so the link stays at 120 and both windows are exact. 30 next to 60 gives gcd(4,2)=2, so the link runs at 60.

# 2. Semantics (qdoc, in qwindow.cpp)

```
/*!
    \property QWindow::preferredFrameRate
    \since 6.13
    \brief the rate, in frames per second, at which the window prefers to
    receive update requests.

    Set this property to tell the platform how often the window intends to
    render new frames while it keeps calling requestUpdate(), for example to
    match the frame rate of video content, or to limit an animated user
    interface to 60 or 30 frames per second to save power. On displays with a
    variable refresh rate the system can use it to choose a lower refresh rate.

    The rate is a hint. Update requests are delivered at a rate close to the
    preferred rate that the display can show with an even cadence. When the
    preferred rate can't be shown exactly, the next faster such rate is used, so
    that no frame of content at the preferred rate has to be skipped. For
    example, on a 120 Hz display 120, 60, 40, 30 and 24 are exact, 25 gives
    30 update requests per second, 48 and 50 give 60, and 80 gives 120. Rates
    within 1% of an exact rate count as exact, so 23.976 (24000/1001), 29.97 and
    59.94 give 24, 30 and 60. Update requests are never delivered faster than
    the display refreshes; a rate at or above the refresh rate gives one update
    request per refresh. Which rates are exact depends on the display and the
    operating system.

    The system may still deliver fewer update requests, for instance in low
    power mode, while the window is occluded, or when rendering a frame takes
    longer than the frame interval.

    Setting this property does not request an update. It only paces the update
    requests the window makes with requestUpdate(), including those made by
    QPaintDeviceWindow::update() and by Qt Quick. Each window is paced
    independently, so windows on the same screen can prefer different rates,
    and a window's preference never slows down another window. A change takes
    effect at the next display refresh. Qt Quick advances animations by the
    actual interval between frames, so they run at the same speed at any rate.

    The default value, 0, means no preference: update requests are delivered at
    the platform's default rate, usually the refresh rate of the display.
    Setting a negative or non-finite value prints a warning and sets the
    property to 0.

    For Qt Widgets, set this property on the top-level widget's window, see
    QWidget::windowHandle(), which exists once the widget is shown or
    QWidget::winId() has been called. Updates scheduled with QWidget::update()
    are then paced, including the content of QOpenGLWidget and QRhiWidget.
    QWidget::repaint() is not paced.

    \note This property is currently supported on macOS and iOS, and on
    platforms that deliver update requests with a timer, such as X11 (xcb),
    Android, eglfs and offscreen, where it sets a minimum interval between
    update requests that isn't aligned to the display refresh. Other platforms
    currently ignore it.

    \sa requestUpdate(), QScreen::refreshRate()
*/
```

Also add to the `QWindow::requestUpdate()` docs: "The rate of update requests can be limited with preferredFrameRate."

Behaviour the docs don't spell out:
- Setting the current value again emits nothing.
- Child windows don't inherit the value.
- `preferredFrameRate()` returns the stored value, not the effective rate.
- Update requests coalesce as they do today.
- A request made after idling is delivered at the next link tick; pacing measures from the previous delivery.

# 3. QML (qtdeclarative)

**Registration: none.** `QWindowForeign` (`QML_FOREIGN(QWindow) QML_ANONYMOUS`) in `/Users/anthony.liot/Desktop/bitbucket/qt5/qtdeclarative/src/quick/items/qquickwindowmodule_p.h` already exposes QWindow's members.
- After qtdeclarative is rebuilt against the new qtbase, the `REVISION(6, 13)` property and signal appear in QtQuick's qmltypes.
- They are visible to `import QtQuick` (unversioned, or 6.13 and later), not to 6.12 or older. This follows the `flagsChanged` 6.10 precedent.
- Not `FINAL` (changed after review #2, see REVIEW-API.md M1): with `FINAL`, existing QML Window subtypes declaring their own `preferredFrameRate` would fail to load under every import version, and qtdeclarative removed `FINAL` from QQuickWindow properties for that reason (d86bf31645).
- `RESET` makes assigning `undefined` reset it.
- `Window`, `ApplicationWindow`, `QQuickView` and `Window.window` all inherit it.
- If this lands after the 6.13 feature freeze, change every 6.13 to 6.14.

**Code changes**
1. `src/quick/scenegraph/qsgthreadedrenderloop.cpp:1717` reads the interval from the new struct:
   ```cpp
   const auto &t = QQuickWindowPrivate::get(window)->updateRequestTiming;
   const float frameInterval = window && t.isValid()
           ? std::chrono::duration<float, std::milli>(t.frameInterval).count() : 0.0f;
   ```
2. The QML doc, in `src/quick/items/qquickwindow.cpp`:
   ```
   /*!
       \qmlproperty real Window::preferredFrameRate
       \since 6.13

       The rate, in frames per second, at which the window prefers to render
       while it is animating. This is a hint that lets the system choose a lower
       display refresh rate, for example to match video content or to limit an
       animated user interface to 60 or 30 frames per second. Qt renders at a
       rate close to it that the display can show evenly, using the next faster
       such rate when it can't be shown exactly, and never faster than the
       display refreshes. Animations run at the same speed at any rate.

       The default, 0, means no preference. Assign 0 or \c undefined to return
       to the default.

       \code
       Window {
           preferredFrameRate: player.playing ? 24000 / 1001 : 60
       }
       \endcode

       \note Inside a QQuickWidget, set the property on the top-level widget's
       window instead. When only Animator types are running, the scene may still
       render at the display's refresh rate.

       \sa QWindow::preferredFrameRate
   */
   ```
3. The `tst_qquickanimations` tests at lines 2136 and 2211 change from `setProperty("_q_preferredFrameRateRange", 30)` to `view.setPreferredFrameRate(30)`.

**Example**, cycling through the three rates you want on the ProMotion panel:

```qml
import QtQuick

Window {
    width: 640; height: 360; visible: true
    property var rates: [0, 120, 60, 30]            // 0 = system default
    property int index: 0
    preferredFrameRate: rates[index]
    FrameAnimation { running: true; onTriggered: label.text =
        (1 / smoothFrameTime).toFixed(1) + " fps (asked " + (rates[index] || "default") + ")" }
    Text { id: label; anchors.centerIn: parent; font.pixelSize: 32 }
    TapHandler { onTapped: index = (index + 1) % rates.length }
}
// Video: preferredFrameRate: player.playing
//            ? (player.metaData.value(MediaMetaData.VideoFrameRate) ?? undefined) : 60
```

# 4. Consumption in the Apple plugins, plus the timer and Widgets paths

## `QAppleFrameRatePreference` (`.../src/gui/platform/darwin/qappleframerate_p.h`)

It keeps finding out which rate a window wants, and now owns a `QFrameRatePacer`. `update(window)` checks these in order:
1. `window->preferredFrameRate() > 0` (the public API) gives `Range::fromPreferredFrameRate(fps)`. This is a member read with no QVariant work, which fixes REVIEW #15 on the public path.
2. Otherwise the `_q_preferredFrameRateRange` property, parsed and cached as today (unsupported, for experiments).
3. Otherwise `QT_APPLE_PREFERRED_FRAME_RATE_RANGE` (unsupported, for experiments).
4. Otherwise the system default.

`fromString()`, `fromVariant()` and `isValid()` stay. `unitedWith()` is removed and replaced by `linkRate()`. The pacing member functions move to `QFrameRatePacer`.

## Cocoa (`.../src/plugins/platforms/cocoa/`)

- `-displayLinkDidFire:` calls `deliverUpdateRequests(displayLink.timestamp, displayLink.targetTimestamp)`, with `L = target - timestamp`.
- For each delivered window:
  - fill `qt_window_private(w)->updateRequestTiming = { toSteady(timestamp), toSteady(target), ns(L), ns(pacer.effectiveFrameInterval(L)), pacer.sequenceNumber() }`;
  - call `deliverUpdateRequest()`;
  - reset the struct after the existing `QPointer` check.
  - `toSteady()` is `steady_clock::time_point(duration_cast<nanoseconds>(duration<double>(t)))`. This assumes `CACurrentMediaTime` and libc++'s `steady_clock` share the `CLOCK_UPTIME_RAW` base. A test must check that, and if it fails, convert with an offset sampled at each callback.
- After the loop, and in `updateDisplayLinkFrameRate()`, set the link from `linkRate(pendingRanges, NSScreen.maximumFramesPerSecond)`:
  - 0 means `CAFrameRateRangeDefault`, including when a window asks for 120 or more on this panel, which avoids the stall;
  - `r` means `CAFrameRateRangeMake(r, r, r)`;
  - only assign when `!CAFrameRateRangeIsEqualToRange(...)`.
- The rest is unchanged: one link per screen in common modes, pausing when idle, the re-scan before pausing, and the fallback timer for swapInterval 0.
- The hook:
  ```cpp
  void QCocoaWindow::setPreferredFrameRate(qreal)
  {
      auto *s = static_cast<QCocoaScreen *>(screen());
      if (hasPendingUpdateRequest() && updatesWithDisplayLink() && !s->isDeliveringUpdateRequests())
          s->updateDisplayLinkFrameRate();   // during delivery the post-loop pass covers it
  }
  ```

**On your 120 Hz panel with this spec:**

| Preferred | Delivered | Status |
|---|---|---|
| 120, 80 | 120 | the default range (measured, 119.8) |
| 60, 59.94, 50, 48 | 60 | (60,60,60), measured |
| 40 | 40 | measured |
| 30, 29.97, 25 | 30 | 25 now goes to 30 instead of 24; (30,30,30) was measured |
| 24, 23.976 | 24 | measured |

## iOS (`qiosscreen.mm`, `qioswindow.h/.mm`)

- Same changes, using `UIScreen.maximumFramesPerSecond`, so the exact rates are M/n.
- ProMotion iPhones may also support 80 and 48 (the 240/n table). That is unverified and left for later.
- Log one `qCInfo` when a window asks for more than 60 on an iPhone whose Info.plist lacks `CADisableMinimumFrameDurationOnPhone`.

## Timer path (`qplatformwindow.cpp`)

This covers xcb, Android, eglfs, offscreen, and Windows without DXGI vsync.
- `requestUpdate()`:
  - if `fps > 0 && lastUpdateRequestDelivery.isValid()`, then `updateInterval = max(updateInterval, qint64(1000 / fps) - lastUpdateRequestDelivery.elapsed())`;
  - delete the branch's `updateRequestInterval = 0` line.
- `deliverUpdateRequest()` restarts `lastUpdateRequestDelivery` before `sendEvent`.
- The timer branch in `windowEvent()` fills `updateRequestTiming.frameInterval = 1/fps`, with the target unknown, around the delivery and resets it afterwards.

## Widgets (`qwidgetrepaintmanager.cpp` ~355, `qwidgetrepaintmanager_p.h`, `qwidgetwindow.cpp:386`)

This is opt-in and adds no API.
- In `sendUpdateRequest()`, for `UpdateLater`: if `widget->isWindow() && !shouldPaintOnScreen()` and `windowHandle()->preferredFrameRate() > 0`, set `updateRequestSent = pacedUpdateRequestPending = true`, call `windowHandle()->requestUpdate()`, and skip the `postEvent`.
- In `QWidgetWindow::event(UpdateRequest)`: if `std::exchange(rm->pacedUpdateRequestPending, false)`, send `QEvent(QEvent::UpdateRequest)` to `m_widget`. That reaches `QWidget::event` and then `syncBackingStore()`, the same as the posted path. Otherwise keep `m_widget->repaint()`.
- The `UpdateNow` throttle uses `max(1000/refresh, 1000/preferredFrameRate)`.

# 5. Left for later, and minimal tests

## Later, all additive; none changes `preferredFrameRate`

1. **Public timing.** `QFrameTiming` (steady_clock: `timestamp`, `targetPresentationTime`, `refreshInterval`, `frameInterval`, `sequenceNumber`), read through `QWindow::frameTiming()` during paced delivery. That includes Qt Quick's polishAndSync and the paced widget sync, so `QRhiWidget::render()` and `paintGL()` can use it. Use an accessor, not a `QUpdateRequestEvent`, because plain `QEvent(UpdateRequest)` events are still posted. The field set is already in the private struct.
2. **Hard caps.** `minimumFrameRate` and `maximumFrameRate` properties.
3. **Content kind.** A small content-type enum property (default/video) for "exact multiple or every refresh", Android `FIXED_SOURCE`, and Wayland `wp_content_type`.
4. **Rate discovery.** `QPlatformScreen::supportedFrameRates()` and later `QScreen::supportedFrameRates()`, including the iPhone 240/n table.
5. **Other backends.** Windows DXGI pacing, Wayland frame-callback pacing, and Android `ANativeWindow_setFrameRate` (API 30, resolved at runtime) plus Choreographer. All use `QFrameRatePacer`.
6. **Widgets and Qt Quick follow-ups.**
   - A `QWidget` convenience stored in `QTLWExtra`, so the value survives window recreation.
   - QQuickWidget rendering in the paced sync instead of its 5 ms timer.
   - Pacing scenes where only render-thread Animators run.
   - A Qt Multimedia contribution mechanism.
7. **Before Gerrit.**
   - Drop `_q_preferredFrameRateRange`.
   - Replace the Apple env var with an undocumented cross-platform `QT_PREFERRED_FRAME_RATE`.
   - Find the cause of the (120,120,120) stall, and file Apple feedback if it reproduces.

## Minimal tests

1. **`tst_qwindow::preferredFrameRateProperty`** (headless). Check that:
   - the default is 0;
   - setting 60 emits once, and setting 60 again emits nothing;
   - reset gives 0 and emits;
   - -1, NaN and inf warn (`ignoreMessage`) and give 0;
   - a value set before `create()` survives it;
   - `QMetaProperty` has `isFinal()`, `isResettable()`, and revision `QTypeRevision::fromVersion(6, 13)`.
2. **`tst_qframeratepacer`** (headless; moved from `tst_qappleframerate`).
   - `framesPerDelivery` rows:

     | Link | Preferred → frames per delivery |
     |---|---|
     | 120 Hz | 120→1, 80→1, 60→2, 50→2, 48→2, 40→3, 30→4, 29.97→4, 25→4, 24→5, 23.976→5 |
     | 60 Hz | 60→1, 50→1, 30→2, 25→2, 24→2, 120→1 |
     | 59.94 Hz | 60→1, 30→2 |
     | 240 Hz | 48→5, 80→3, 25→9 |

   - Keep the existing nearest-rule rows for the legacy ranges.
   - `linkRate` on M=120: [60]→60, [30,60]→60, [24,60]→0, [24,30]→0, [120]→0, [default,30]→0, [30]→30.
   - Jitter rows for `shouldDeliverFrame`.
3. **`tst_qwindow::preferredFrameRate*`** (display-paced; existing tests switched to the setter).
   - 30/60/24 rows, plus 120 and "above refresh" rows expecting every refresh.
   - Mixed windows.
   - A change while a request is pending takes effect through the hook.
   - `updateRequestTiming` is valid during delivery (frameInterval equals the effective interval) and invalid after.
   - When both are set, the public API wins over the private property.
4. **Timer path** (`QT_QPA_PLATFORM=offscreen`).
   - At 30: 25 to 31 update requests per second.
   - At 0: unchanged.
   - The first request after idling is delivered in 5 ms or less.
5. **Widgets.**
   - A top-level at 30 with a continuously updating child gets about 30 paints per second, routed through `windowHandle()` UpdateRequests.
   - With no preference, the posted path is unchanged.
   - `repaint()` stays synchronous.
6. **Clock.** `|steady_clock::now() - toSteady(CACurrentMediaTime())| < 1 ms`, on macOS and iOS.
7. **qtdeclarative `tst_qquickwindow::preferredFrameRate`.**
   - A value set in QML reads back in C++.
   - A binding to `undefined` gives 0 and emits once.
   - An `import QtQuick 6.12` file that assigns it fails to load.
   - Plus the updated `tst_qquickanimations` tests.
8. **Manual and bench.** Add a `--rate` option to `tests/manual/displaylink` that uses `setPreferredFrameRate`. Re-run `video-rates.sh` for 23.976 to 120: check that 120 no longer stalls and 25 gives 30. Re-measure the panel refresh rate a different way, then add the 240 Hz display rows (48, 80, 25).

## Widgets plan

# Plan: let Qt Widgets top-level windows honor the window's preferred frame rate (opt-in)

Paths are relative to `/Users/anthony.liot/Desktop/bitbucket/qt5/qtbase` unless marked `qtdeclarative:`. Line numbers are from HEAD `37bfe3328a5`; `src/widgets` is unchanged from base. I read the code only; nothing was modified or built.

## 0. The short version

- **One decision point:** a new function, `QWidgetRepaintManager::usesPacedUpdateRequests()`, decides whether a top-level is paced.
- **One changed path:** when it returns true, the top-level's `UpdateLater` request calls `QWindow::requestUpdate()` instead of posting an event.
- **Delivery:** the display-link delivery reaches `QWidgetWindow::event()`. For requests the repaint manager made, that handler does a dirty-only sync instead of today's full `repaint()`.
- **Unchanged:**
  - `repaint()` (`UpdateNow`)
  - the synchronous expose and resize syncs
  - paint-on-screen widgets
  - every platform without the new hook
- **Size:** about 60 lines in qtbase for phase 1. QQuickWidget needs a separate qtdeclarative change (section 7).

## 1. Opt-in rule

A top-level is paced only when all of these hold. The check runs on every request, so changing the property at runtime works.

1. `QT_WIDGETS_PACED_UPDATES` is not `0`. Setting it to `1` forces pacing on for testing and A/B comparisons.
2. The top-level has a platform window.
3. It is not paint-on-screen and not `WA_DontShowOnScreen`.
4. It is not embedded in a graphics proxy.
5. The platform says `pacesUpdateRequests()`, which is true in these cases:
   - **Cocoa:** `updatesWithDisplayLink()` (swapInterval != 0) and the preference is not default. The preference comes from the property or from `QT_APPLE_PREFERRED_FRAME_RATE_RANGE`.
   - **iOS:** the preference is not default.

## 2. Changes

### Step 1: a QPA hook, so QtWidgets doesn't depend on the Darwin-only code
In `src/gui/kernel/qplatformwindow.h`, next to `requestUpdate()` at line 119, and in `qplatformwindow.cpp`:
```cpp
virtual bool pacesUpdateRequests() const;
// Returns whether requestUpdate() is paced to the display and the window's preferred
// frame rate, so clients that schedule their own repaints (Qt Widgets) should use it.
bool QPlatformWindow::pacesUpdateRequests() const { return false; }
```
In `src/plugins/platforms/cocoa/qcocoawindow.h` (lines 115-117 and 271) and `qcocoawindow.mm`, next to `updatesWithDisplayLink()` at line 1907:
```cpp
bool pacesUpdateRequests() const override;
mutable QAppleFrameRatePreference m_frameRatePreference; // update() caches the parse

bool QCocoaWindow::pacesUpdateRequests() const
{
    return updatesWithDisplayLink() && !m_frameRatePreference.update(window()).isDefault();
}
```
In `src/plugins/platforms/ios/qioswindow.h` (lines 56-57 and 75) and `qioswindow.mm`:
```cpp
bool QIOSWindow::pacesUpdateRequests() const
{ return !m_frameRatePreference.update(window()).isDefault(); }
```
When the public `QWindow::preferredFrameRateRange` lands, only these two overrides change.

### Step 2: let a QWidget set the preference, and keep it across window re-creation
QWidget already forwards `_q_platform_*` dynamic properties to its QWidgetWindow, both at create and on change (qwidget.cpp:1242-1245 and 9399-9400). So in `src/gui/platform/darwin/qappleframerate.cpp:257`, `update()` should also accept that name:
```cpp
static constexpr const char *widgetPropertyName = "_q_platform_preferredFrameRateRange";
QVariant value = window->property(propertyName);
if (!value.isValid())
    value = window->property(widgetPropertyName);
```
With this, `topLevel->setProperty("_q_platform_preferredFrameRateRange", 30)` works before `show()` and survives `setWindowFlags()`/`setParent()` re-creation. Resetting it to an invalid `QVariant` turns it off. It must be set on `widget->window()`; child widgets have no `windowHandle()`.

For upstream, store the range in `QTLWExtra` and apply it in `createTLSysExtra` (qwidget.cpp:1389-1418, the same pattern as min/max size and opacity).

### Step 3: the repaint manager
In `src/widgets/kernel/qwidgetrepaintmanager_p.h`, next to `updateRequestSent` at line 108:
```cpp
public:
    bool usesPacedUpdateRequests() const;                       // also used by QQuickWidget
    bool takeWindowUpdateRequest() { return std::exchange(windowUpdateRequested, false); }
    bool isUpdateRequestSent() const { return updateRequestSent; }
private:
    bool windowUpdateRequested = false; // the pending QWindow update request is ours
```
In `src/widgets/kernel/qwidgetrepaintmanager.cpp`: add `#include <qpa/qplatformwindow.h>`, move `hasPlatformWindow()` (line 375) above `sendUpdateRequest`, then add:
```cpp
bool QWidgetRepaintManager::usesPacedUpdateRequests() const
{
    static const int mode = qEnvironmentVariableIsSet("QT_WIDGETS_PACED_UPDATES")
            ? qEnvironmentVariableIntValue("QT_WIDGETS_PACED_UPDATES") : -1;
    if (mode == 0 || !hasPlatformWindow(tlw))
        return false;
    QWidgetPrivate *d = tlw->d_func();
    if (d->shouldPaintOnScreen() || tlw->testAttribute(Qt::WA_DontShowOnScreen))
        return false;
#if QT_CONFIG(graphicsview)
    if (d->extra && d->extra->proxyWidget)
        return false;
#endif
    return mode == 1 || tlw->windowHandle()->handle()->pacesUpdateRequests();
}
```
In `sendUpdateRequest()`, at `case UpdateLater:` (line 357), before the existing post:
```cpp
    case UpdateLater:
        if (widget == tlw && usesPacedUpdateRequests()) {
            QWindow *window = tlw->windowHandle();
            QWindowPrivate *wd = QWindowPrivate::get(window);
            // Someone else's pending requestUpdate() keeps its full-repaint semantics,
            // which covers our dirty state too.
            if (!wd->updateRequestPending)
                windowUpdateRequested = true;
            window->requestUpdate();
            if (wd->updateRequestPending) {
                updateRequestSent = true;
                break;
            }
            windowUpdateRequested = false; // request was dropped: fall back to posting
        }
        // existing code unchanged (postEvent ... Qt::LowEventPriority)
```
- The downgrade from `UpdateNow` to `UpdateLater` for texture windows (lines 341-354) now goes through this paced branch automatically.
- Do **not** clear `windowUpdateRequested` in `sync()` or `paintAndFlush()` (lines 648, 872, 886). The flag means "the pending window request is ours", and that is still true after an expose sync.

### Step 4: QWidgetWindow
Replace the handler in `src/widgets/kernel/qwidgetwindow.cpp:386-390` with:
```cpp
    case QEvent::UpdateRequest:
        if (m_widget->isWindow()) { // native children share the top-level's repaint manager
            auto *rm = QWidgetPrivate::get(m_widget)->maybeRepaintManager();
            // Take the flag before syncing, so an update() during the sync (e.g. from
            // QOpenGLWidget::frameSwapped) schedules the next frame as ours.
            if (rm && rm->takeWindowUpdateRequest()) {
                // Sync like a posted request, via QWidget::event() so event filters and
                // overrides still see it. Skip if an expose/repaint() already synced
                // (avoids an empty GPU compose, qwidgetrepaintmanager.cpp:992-996).
                if (rm->isUpdateRequestSent())
                    QCoreApplication::forwardEvent(m_widget, event);
                return true;
            }
        }
        m_widget->repaint(); // unchanged for external windowHandle()->requestUpdate()
        return true;
```
This also removes a possible full-repaint loop: an external request → `repaint()` → throttle downgrade → paced request → the next delivery is ours → dirty-only sync, then it stops.

### Step 5: nested event loops inside delivery (needed before shipping or recommending the env var)
- **Problem:**
  - `QCocoaScreen::deliverUpdateRequests` skips recursive callbacks (qcocoascreen.mm:397-401; iOS is similar).
  - Widget user code now runs inside the display-link callback: `paintEvent`, `initializeGL`/`paintGL`, and `frameSwapped`/`aboutToCompose` slots.
  - If that code calls `QDialog::exec()`, `QMessageBox`, or `processEvents()`, every paced window on the screen stops updating until the loop returns. A paced dialog opened that way freezes after its first expose. With today's posted events, updates keep flowing in nested loops.
- **Probe first:** check whether a CADisplayLink fires again at all while its callback is on the stack. Use `QT_LOGGING_RULES=qt.qpa.screen.updates.debug=true` and a paced QWindow that runs a `QEventLoop` for 1 s in its UpdateRequest, then look for "Skipping recursive display link callback".
- **(a) If it does fire again:**
  - Replace the per-screen guard with a per-window one: skip windows whose `QCocoaWindow::m_deliveringUpdateRequest` is set.
  - Still count skipped windows as pending, and let only the outermost pass pause the link. Otherwise the nested pass can pause it for good.
  - Iterate over `QPointer<QWindow>` and hold a `QPointer<QScreen>` (REVIEW #18).
- **(b) If it doesn't:** at the start of delivery, arm a one-shot timer of about two link intervals and cancel it on return. If it fires, we are in a nested loop, so serve the other pending windows through their fallback timers. `stopFallbackUpdateTimer()` already switches them back on the next link frame.
- Put this in a separate commit: it also affects QWindow and QQuickWindow apps.

### Step 6 (optional)
- **a. swapInterval 0:** QOpenGLWidget copies its swapInterval to the top-level (qopenglwidget.cpp:881-889). With `swapInterval(0)`, `updatesWithDisplayLink()` is false (qcocoawindow.mm:1907-1911), so the window silently isn't paced. Proposal: `updatesWithDisplayLink()` returns `swapInterval != 0 || preference is not default`. The risk is low because the preference is new, so no existing app sets both.
- **b. `UpdateNow` throttle (lines 341-354):** for paced windows, compare against `max(1000/refresh, paced interval)` so that `repaint()`-driven texture windows don't present faster than the preference. This needs a `QWindowPrivate::lastPacedUpdateInterval` that is set at qcocoascreen.mm:434 and not reset.
- **c. Presentation time for video:** add `QWindowPrivate::updateRequestTargetTimestamp`, set and reset next to `updateRequestInterval` (qcocoascreen.mm:434/447, qiosscreen.mm:403/413).
  - `paintGL()`, `render()` and `paintEvent` can read it, because the sync now runs inside delivery. It is 0 for expose- and resize-driven frames.
  - Document the clock (CACurrentMediaTime) or convert it to the steady clock.
  - This is the private first step toward API-PROPOSAL §2.

## 3. Behavior for opted-in windows
- **`update()`:** paints on the next paced frame. There is no posted UpdateRequest any more, so `sendPostedEvents(…, UpdateRequest)` and `QGraphicsViewPrivate::dispatchPendingUpdateRequests()` (qgraphicsview_p.h:157-163) do nothing.
- **`repaint()`:** stays synchronous and unpaced. For texture windows the existing throttle may defer it to the paced frame.
- **Expose and resize:** stay synchronous.
- **External `windowHandle()->requestUpdate()`:** still a full repaint, except when it coalesces with a pending repaint-manager request; then only the dirty regions sync. Document this.
- **Scope:** the whole top-level is paced, including text input and the timeline, not just the video view.
- **Native child widgets:** they are flushed during the top-level's sync, so they follow its pace.

## 4. Risks and mitigations
1. **Nested loops freeze paced windows:** high if the app-wide env var is used, medium with a per-window property. Mitigated by step 5.
2. **Latency:** up to one paced frame for every widget in the window, about 42 ms at 24 fps.
   - Keep the UI at 60 Hz or more, or 120 on ProMotion (24p content maps 5:1 to 120 Hz with no judder), and pick video frames by target timestamp (6c).
   - Set low rates only on viewer windows, or only during playback; changing it at runtime works.
   - Or host the video in a `createWindowContainer` QWindow.
3. **The env var opts in every widget window,** including menus, tooltips and dialogs, which would all run at 24/30. Recommend the per-window property. Optionally exclude `Qt::Popup`/`Qt::ToolTip` windows from the env-derived default.
4. **Code that assumes posted events** (tst_qwidget.cpp:7885-7893, `destroyBackingStore` at 11328-11353, QGraphicsView): only affects opted-in windows. Run the test suites in forced mode to list the cases.
5. **A lost request leaving `updateRequestSent` stuck:**
   - The platform-window check plus the "still pending?" check after `requestUpdate()` falls back to posting.
   - Re-creation replaces the repaint manager (qwidget.cpp:1170), and `QWindowPrivate::create` re-requests a pending update (qwindow.cpp:552-613).
   - An event filter that swallows the window's UpdateRequest behaves the same as one swallowing today's posted event.
6. **Event-loop starvation** (commit 0f6a6b2bffb): heavy paints at 120 Hz run inside the link callback. Measure input latency with 30 ms paints.
7. **Live resize:** the QMetalLayer display-lock deferral (qcocoawindow.mm:1916-1931) keeps the request pending. Verify with texture children.
8. **Two paced windows at 30 fps can land on different vsyncs:** cosmetic; per-screen phase alignment is optional.

## 5. Too risky: not part of this change
- Making this the default or removing the opt-in.
- Pacing `repaint()`, expose or resize.
- Changing the full-repaint behavior of external `requestUpdate()` (effc6b4cd15, `tst_QOpenGLWidget::requestUpdate`).
- A custom `QAnimationDriver` for QQuickWidget or for widgets. Drivers are per thread, would conflict with the one the threaded render loop installs (qsgthreadedrenderloop.cpp:1027-1032), and would affect every GUI-thread animation.
- Combining preferences declared on child widgets into the top-level's.
- Routing on platforms whose `requestUpdate()` is only a timer. That adds up to 5 ms latency for nothing; the hook keeps them off.
- Relaxing the recursion guard without QPointer iteration (REVIEW #18 use-after-free).

## 6. Tests
**A. Logic tests, headless-ish.** Run with `-platform offscreen` on macOS or any CI, and also on cocoa.
- Add a second target, e.g. `tst_qwidgetrepaintmanager_paced`: the same source with `QT_WIDGETS_PACED_UPDATES=1` set in `initMain()`, since the mode is read once. It uses the existing `TestWidget` (`paintedRegions`, `updateRequests`) from tst_qwidgetrepaintmanager.cpp:21-80.
1. `update(rect)`:
   - `QWindowPrivate::get(win)->updateRequestPending` is true.
   - `sendPostedEvents(&w, QEvent::UpdateRequest)` paints nothing.
   - `waitForPainted()` then shows a painted region equal to `rect`, with `updateRequests == 1`.
2. Three `update()` calls give one UpdateRequest, and the painted region is their union.
3. `repaint(rect)` paints before any event processing.
4. `update()` followed by `repaint()`: once the request is no longer pending, there is no second paint and no second UpdateRequest.
5. `windowHandle()->requestUpdate()` with nothing dirty gives a full-rect paint, then no more paints for 200 ms (no loop). Add a variant with a QRhiWidget child to exercise the throttle downgrade (on cocoa, Metal).
6. `WA_DontShowOnScreen` stays on the posted path.
7. `setWindowFlags()` re-creation and hide/show while a request is pending: afterwards, `update()` still paints.
8. A `WA_NativeWindow` child's `update()` paints only the child region.
9. The existing `paintOnScreenUpdates` test is unchanged.
10. A QOpenGLWidget or QRhiWidget that calls `update()` from `frameSwapped`/`frameSubmitted` keeps producing frames, and a raster sibling's paint count stays 0.
11. A `paintEvent` that calls `update()` on another top-level: that window repaints (the REVIEW #4 case).
- **Control:** without the property or env var, all existing suites run unchanged in CI.
- **Informational:** run tst_qwidget, tst_qwidgetrepaintmanager, tst_qopenglwidget, tst_qrhiwidget, tst_qgraphicsview and tst_qquickwidget with `=1` to list the order-dependent tests.

**B. Cocoa cadence tests** (macOS GUI session), reusing the `REQUIRE_DISPLAY_PACED_UPDATES` / `measureUpdateRates` / `systemPacedRates` approach from tst_qwindow.cpp:3542-3583:
- Set the property on the top-level to 30, 60, 24 and the refresh rate. Drive a raster widget with `update()` from a 1 ms timer and a QRhiWidget with `update()` in `render()`, and check their rates are within `systemPacedRates`.
- Inside `render()`, `updateRequestInterval` should be about 1/rate.
- Toggle at runtime: 30, then reset, then the window is back on the posted path.
- The property works when set before `show()` and after re-creation.
- Nested loop test (after step 5): paced window A runs a `QEventLoop` for 300 ms in its paint while paced window B keeps painting.
- On the 120 Hz panel, 30, 60 and 120 must be exact. For 48 and 80, accept `systemPacedRates`: 48 may give 48 or 60, and 80 may give 80 or 120 (pacing ties go to the faster rate).

**C. qtdeclarative `tst_qquickwidget`:** in a top-level paced at 30 with a running NumberAnimation, renders per second should be about 30 (about 60 today).

**D. Manual tests:** add a Widgets mode (raster, QRhiWidget, QOpenGLWidget, QQuickWidget) to tests/manual/displaylink and run it with `QT_DEBUG_FPS=1` and `qt.qpa.screen.updates` logging.
- On the ProMotion panel, measure the panel rate, CPU use and wakeups at 24/30/48/60/120.
- Check that raster-only widget windows also make the panel drop to the lower rate; this is not verified yet.
- Measure input latency with 30 ms paints.
- Check live resize with texture children.

## 7. What each GPU widget needs beyond the routing
- **QOpenGLWidget:**
  - Pacing needs nothing more. `paintGL` runs in `paintEvent` inside the sync (qopenglwidget.cpp:1528-1539), and a `frameSwapped` → `update()` chain lands on the next paced frame.
  - It does need 6a, because `swapInterval(0)` turns pacing off, and 6c for video timing.
  - `initializeGL` can now run inside delivery, so don't open dialogs there (step 5).
- **QRhiWidget:** the same; `render()` runs in `paintEvent` (qrhiwidget.cpp:257-285). The docs saying "update() in render() is throttled by vsync" should add "and by the window's preferred frame rate".
- **QQuickWidget** (qtdeclarative: src/quickwidgets/qquickwidget.cpp): routing alone only paces the composition. The scene still renders from the 5 ms timer (lines 1971-1987) and animations from the 16 ms `QUnifiedTimer`. Phase 1:
  ```cpp
  bool QQuickWidgetPrivate::usesPacedUpdates() const
  { Q_Q(const QQuickWidget);
    auto *rm = useSoftwareRenderer ? nullptr : QWidgetPrivate::get(q->window())->maybeRepaintManager();
    return rm && rm->usesPacedUpdateRequests(); }

  // triggerUpdate(): after d->updatePending = true;
  if (d->usesPacedUpdates()) { update(); return; } // the paced sync batches like the timer

  // paintEvent(), QRhi path:
  if (d->updatePending && !d->eventPending && d->usesPacedUpdates()) {
      d->updatePending = false;
      if (isVisible() && !d->fakeHidden)
          d->render(true); // composited by this same sync
  }
  ```
  - Do not call `renderSceneGraph()` from the paint. Its `q->update()` (line 504) would post a `QUpdateLaterEvent` and render continuously.
  - A `renderRequested` during render still correctly schedules the next paced frame.
  - Phase 2: call `QUnifiedTimer::instance()->updateAnimationTimers()` in the paced paint before rendering, so animations are sampled at frame time and 120 fps becomes possible. It is time-based and a no-op under a vsync driver. Measure before adopting.
  - Not now: a paced per-top-level animation driver (see section 5).
  - If the QQuickWidget is itself the top-level, set the property on the QQuickWidget.

## 8. Commit order
1. QPA hook, Cocoa and iOS overrides, and the property alias. No behavior change on its own.
2. Widgets routing (repaint manager and QWidgetWindow) with the logic tests from 6A.
3. Nested-loop handling in QCocoaScreen/QIOSScreen, plus the REVIEW #18 hardening, with its test.
4. Cocoa cadence tests and the Widgets mode of the manual test.
5. Optional 6a, 6b, 6c.
6. The qtdeclarative QQuickWidget change.

In the upstream pitch, quote the commits where the maintainer asks for this direction: 697e1b03972, 9507edddf23 and d24c8ba5f7f.

**Available today without any of this:** put the video in a QWindow via `QWidget::createWindowContainer` and set the property on that window.

Key files:
- /Users/anthony.liot/Desktop/bitbucket/qt5/qtbase/src/widgets/kernel/qwidgetrepaintmanager.cpp
- /Users/anthony.liot/Desktop/bitbucket/qt5/qtbase/src/widgets/kernel/qwidgetrepaintmanager_p.h
- /Users/anthony.liot/Desktop/bitbucket/qt5/qtbase/src/widgets/kernel/qwidgetwindow.cpp
- /Users/anthony.liot/Desktop/bitbucket/qt5/qtbase/src/gui/kernel/qplatformwindow.h
- /Users/anthony.liot/Desktop/bitbucket/qt5/qtbase/src/gui/kernel/qplatformwindow.cpp
- /Users/anthony.liot/Desktop/bitbucket/qt5/qtbase/src/plugins/platforms/cocoa/qcocoawindow.mm
- /Users/anthony.liot/Desktop/bitbucket/qt5/qtbase/src/plugins/platforms/cocoa/qcocoascreen.mm
- /Users/anthony.liot/Desktop/bitbucket/qt5/qtbase/src/plugins/platforms/ios/qioswindow.mm
- /Users/anthony.liot/Desktop/bitbucket/qt5/qtbase/src/gui/platform/darwin/qappleframerate.cpp
- /Users/anthony.liot/Desktop/bitbucket/qt5/qtbase/tests/auto/widgets/kernel/qwidgetrepaintmanager/tst_qwidgetrepaintmanager.cpp
- /Users/anthony.liot/Desktop/bitbucket/qt5/qtdeclarative/src/quickwidgets/qquickwidget.cpp
