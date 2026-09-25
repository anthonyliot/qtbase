# Proposal: public Qt API for frame-rate intent (and CAMetalDisplayLink)

The branch ships a private mechanism (dynamic property + env var). This document is what we'd
propose upstream once public API changes are possible. It's written so the platform code in this
branch maps 1:1 onto it: `QAppleFrameRatePreference::update(window)` is the only place that
would switch from reading the property to reading the new API.

## 1. `QWindow` frame-rate hint (cross-platform)

```cpp
// qwindow.h
class QFrameRateRange   // or QWindow::FrameRateRange
{
public:
    constexpr QFrameRateRange() noexcept = default;                       // "no preference"
    constexpr explicit QFrameRateRange(qreal fps) noexcept;               // min = max = preferred
    constexpr QFrameRateRange(qreal minimum, qreal maximum, qreal preferred = 0) noexcept;
    qreal minimum() const; qreal maximum() const; qreal preferred() const;
    bool isNull() const; bool isValid() const;
};

class QWindow {
    Q_PROPERTY(QFrameRateRange preferredFrameRateRange READ preferredFrameRateRange
               WRITE setPreferredFrameRateRange RESET resetPreferredFrameRateRange
               NOTIFY preferredFrameRateRangeChanged REVISION(6, 13))
public:
    void setPreferredFrameRateRange(QFrameRateRange range);
    QFrameRateRange preferredFrameRateRange() const;
    ...
};

// qplatformwindow.h
virtual void setPreferredFrameRateRange(const QFrameRateRange &);  // default no-op
```

Semantics: a *hint* about how often the app wants `QEvent::UpdateRequest` while it keeps calling
`requestUpdate()`. The platform may deliver at a different rate (e.g. snapping to a divisor of
the refresh rate), and never faster than the display. A null range means "platform default".

Mapping:

| Platform | Mechanism |
|---|---|
| macOS 14+ | `CADisplayLink.preferredFrameRateRange` on the screen link (this branch). Pacing per window. |
| iOS/visionOS | `CADisplayLink.preferredFrameRateRange` (this branch) |
| Android | `Surface.setFrameRate()` / `ANativeWindow_setFrameRate` + Choreographer pacing |
| Wayland | pacing of `wl_surface.frame` callbacks, and `wp_fifo`/`wp_commit_timing` where available |
| Windows | pacing on top of DXGI waitable swap chain, or `DwmFlush` |
| Other/timer fallback | pacing in `QPlatformWindow::requestUpdate()` default implementation |

Also expose on `QQuickWindow` (inherits), plus QML `Window.preferredFrameRateRange`, and Qt Quick
could set it automatically when only low-rate animations run (future).

Open questions for review:
* Should `QSurfaceFormat` carry it? No: it's not a surface property and it changes at runtime.
* Should there be an application-wide default (`QGuiApplication::setDefaultFrameRateRange`)?
  The env var in this branch plays that role today.

## 2. Timing information on update requests

`QEvent::UpdateRequest` has no payload. Proposal: a `QUpdateRequestEvent : QEvent` subclass with

```cpp
std::chrono::nanoseconds timestamp() const;         // when this frame's vsync happened
std::chrono::nanoseconds targetTimestamp() const;   // when the frame will be displayed
std::chrono::nanoseconds frameInterval() const;     // target - timestamp
```

filled from `CADisplayLink.timestamp/targetTimestamp` on Apple platforms. This lets the Qt Quick
animation driver advance animations to the *presentation* time rather than "now", which is
what makes variable/low frame rates look smooth. Needs a `QEvent` subclass, so it's public API.

Private first step (done in this branch): `QWindowPrivate::updateRequestInterval`, the effective
interval between update requests, set by the Cocoa and iOS plugins before each delivery. Qt
Quick's threaded render loop uses it to step vsync based animations (qtdeclarative
`wip/cadisplaylink`). Without it, animations in a 30 fps window on a 240 Hz display ran 8x too
slow until the driver fell back to wall-clock time.

## 3. Per-view display links (opt-in)

`-[NSView displayLinkWithTarget:selector:]` follows the view across screens and stops when the
window isn't visible. That's the most power-efficient behavior, and it lets the system attribute
frame demand to a specific window. It changes the semantics of `requestUpdate()` on hidden
windows (the request stays pending until the window is visible again; today it's delivered).
Proposal: a `Qt::WA_`-style window flag / `QWindow` property, or make it the default in a major
release with the semantic change documented.

## 4. CAMetalDisplayLink for QRhi Metal

Opt-in at swap-chain level, because it changes `beginFrame()` semantics:

```cpp
enum QRhiSwapChain::Flag { ..., UsePlatformFrameTiming = 1 << N };   // name TBD
void QRhiSwapChain::setPreferredFrameLatency(int frames);             // CAMetalDisplayLink.preferredFrameLatency
```

Flow:
1. `QRhiMetal` swap-chain `createOrResize()` with the flag asks the platform window (via
   `QPlatformWindow`/`QMetalLayer`) to switch that window from the screen link to a
   `CAMetalDisplayLink` on its `QMetalLayer`, with the window's preferred frame-rate range.
2. `-metalDisplayLink:needsUpdate:` (main run loop) stores `update.drawable` and
   `update.targetPresentationTimestamp` in the `QMetalLayer` (under its existing `displayLock`) and
   delivers `QEvent::UpdateRequest` (with timing, see 2.).
3. `QRhiMetal::beginFrame()` takes the stashed drawable, if there is one, instead of calling
   `nextDrawable`. On Qt Quick's render thread this is the same hand-off the layer already does
   for `displayLayer`.
4. If no frame is rendered for a stashed drawable before the next callback, it's dropped.

Why not just do it: it's a cross-module change (QPA, `QMetalLayer` in QtGui, QRhi Metal),
the threaded render loop's sync/present ordering must be revalidated, and `beginFrame()` can then
be called without a drawable available (must fall back to `nextDrawable`).

## 5. Qt Multimedia

`AVFDisplayLink` should be created per video sink's screen (not `NSScreen.mainScreen`), with
`preferredFrameRateRange` = the asset's nominal frame rate (e.g. 23.976 → (23.976, 60, 23.976)).
That way 24p playback doesn't wake at 240 Hz.
