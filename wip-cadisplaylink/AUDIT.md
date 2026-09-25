# Audit: CVDisplayLink usage in Qt and the path to CADisplayLink / CAMetalDisplayLink

Snapshot: qt5 superproject `dev` @ 39725828, qtbase @ 25d8223e59f (6.12 dev), audited 2026-09-25
on macOS 27.2 / Xcode 27.2, Apple M5 Max driving a 240 Hz external display.

## TL;DR

* Qt's minimum supported macOS is **14.4** (`.cmake.conf: QT_SUPPORTED_MIN_MACOS_VERSION`), iOS is
  **18**. `CADisplayLink` on macOS (`-[NSScreen/NSView/NSWindow displayLinkWithTarget:selector:]`)
  and `CAMetalDisplayLink` are both available from **macOS 14.0 / iOS 17**. So **CVDisplayLink can
  be removed outright**; no runtime fallback or `@available` check is needed.
* The only place in qtbase that uses CVDisplayLink is the Cocoa QPA plugin's implementation of
  `QWindow::requestUpdate()`. Everything that paces through update requests (Qt Quick's basic and
  threaded render loops, QRhi-based `QWindow`s, QOpenGLWindow/QOpenGLWidget via the backing store
  and so on) picks up the change automatically.
* Qt has **no API for an application to express a desired frame rate**. On a 240 Hz display every
  animating Qt window runs at 240 Hz. This is the core problem for the 240 Hz hardware, and it's
  independent of CVDisplayLink vs. CADisplayLink. CADisplayLink gives us the mechanism
  (`preferredFrameRateRange`). Qt needs a way to carry the intent. We can do that today without
  public API (dynamic property + env var), and a public API is proposed in `API-PROPOSAL.md`.
* iOS already uses CADisplayLink but never sets `preferredFrameRateRange`.
* qtmultimedia has a second, separate display link (video output polling) that still has a
  CVDisplayLink fallback that's dead code given the 14.4 minimum.

## Inventory

| Location | API | What it does | Action |
|---|---|---|---|
| `qtbase/src/plugins/platforms/cocoa/qcocoascreen.mm:268-509` | `CVDisplayLink` | Per-`QCocoaScreen` link driving `QWindow::requestUpdate()`. Callback on the CVDisplayLink thread, marshalled to the main thread through a `DISPATCH_SOURCE_TYPE_DATA_ADD` source, with atomics tracking pending/missed frames. Kept running once started. Stopped only when no window on the screen is exposed. | **Replace with CADisplayLink** |
| `qtbase/src/plugins/platforms/cocoa/qcocoascreen.h:14,99-104` | `CVDisplayLinkRef`, `<CoreVideo/CoreVideo.h>` | Members | Replace |
| `qtbase/src/plugins/platforms/cocoa/qcocoawindow.mm:278,1694-1705,1795,1878-1898` | – | `requestUpdate()` → screen, `updatesWithDisplayLink()` (`swapInterval != 0`), screen change restarts link, expose(false) stops link | Keep call sites. Semantics change from "stop" to "pause". |
| `qtbase/src/plugins/platforms/ios/qiosscreen.mm:32-47,195-197,305-348` | `CADisplayLink` (`UIScreen displayLinkWithTarget:`) | Per-screen link, paused when idle | Add frame-rate preference |
| `qtbase/src/gui/rhi/qrhi.cpp:7878-7883` | docs only | Mentions CVDisplayLink in `QRhi` docs | Update the doc text |
| `qtbase/examples/gui/rhiwindow/rhiwindow.cpp`, `tests/manual/rhi/hellominimalcrossgfxtriangle/window.cpp`, `tests/manual/graphicsframecapture/window.cpp` | comments | Mention CVDisplayLink/CADisplayLink in comments | Cosmetic |
| `qtmultimedia/src/plugins/multimedia/darwin/mediaplayer/avfdisplaylink.mm:91-116` | `CADisplayLink` on macOS ≥ 15, else `CVDisplayLink` | Polls `AVPlayerItemVideoOutput` | Drop the fallback. The `@available(macOS 15)` check is wrong anyway (the API is 14.0). Follow-up: use the correct screen instead of `NSScreen.mainScreen`, and set the range from the video's nominal frame rate. |
| `qtdeclarative/src/quick/doc/src/concepts/visualcanvas/scenegraph.qdoc` | docs | Mentions CVDisplayLink | Doc update |
| `qt3d/…/assimp/…/SimpleAssimpViewX`, `qtquick3d/…/assimp/…` | `CVDisplayLink` | 3rd-party sample, not built | Ignore |

### Qt Quick and QRhi Metal

* Qt Quick's threaded render loop (`qsgthreadedrenderloop.cpp`) drives frames from the GUI thread
  via `QWindow::requestUpdate()` → `polishAndSync()`. It blocks on the render thread for sync. The
  render thread itself is throttled by `-[CAMetalLayer nextDrawable]` (`qrhimetal.mm:3948`). So the
  display link rate *is* Qt Quick's animation rate on macOS.
* `QRhiSwapChain::NoVSync` → `layer.displaySyncEnabled = NO` (`qrhimetal.mm:8341`). The platform
  side uses `format().swapInterval() == 0` to fall back to the 5 ms timer
  (`QCocoaWindow::updatesWithDisplayLink`).
* Nothing in QRhi knows about CAMetalDisplayLink. See "CAMetalDisplayLink" below.

## Empirical findings (probe sources in `probes/`)

Measured on a 240 Hz display (`NSScreen.maximumFramesPerSecond == 240`):

```
screen link default                          callbacks/s= 240.0 main=1 interval=4.17ms
screen link range(30,30,30)                  callbacks/s=  30.0 main=1 interval=33.33ms
screen link range(60,60,60)                  callbacks/s=  60.0 main=1 interval=16.67ms
screen link range(120,120,120)               callbacks/s= 120.0 main=1 interval=8.33ms
screen link range(24,24,24)                  callbacks/s=  24.0 main=1 interval=41.67ms
screen link range(48,48,48)                  callbacks/s=  48.0 main=1 interval=20.83ms
screen link range(100,100,100)               callbacks/s= 120.0 main=1 interval=8.33ms   <- snapped up to a divisor
screen link range(10,60,60)                  callbacks/s=  60.0
screen link range(1,60,30)                   callbacks/s=  30.0
screen link paused / unpaused                0 / 240 (restart is immediate)
view link, view not in window                0
view link, window created not shown          0
view link, window visible                    ~240
view link, window visible range 30           30
view link, window ordered out                0
view link, window miniaturized               0
two screen links (30 / default)              a=31 b=239   <- independent ranges coexist
```

Consequences:

1. **Out of the box, every animating Qt app runs at the panel's maximum rate on 240 Hz hardware.**
   The CVDisplayLink behaves the same way, and it can't be told otherwise.
2. **Callbacks arrive on the thread whose run loop the link is added to (main).** The whole
   GCD/atomic marshalling layer in `QCocoaScreen::deliverUpdateRequests()` goes away, along with its
   "missed updates" accounting.
3. **`NSView`/`NSWindow` links stop firing when the window isn't on screen.** Today Qt delivers
   update requests to *all* windows on a screen with a pending request, including hidden ones
   (`keepPendingUpdateRequests` relies on requests surviving hide/show). Switching to per-view
   links would silently stall update requests on hidden, minimized or not-yet-shown windows. That
   would be a behavior change with deadlock potential for code that waits for a frame.
   **Decision: keep a per-screen `NSScreen` link.** Per-view links are listed as a future option in
   `API-PROPOSAL.md` (they'd be the right default for power, but need an explicit semantic change).
4. **`preferredFrameRateRange` throws `NSInvalidArgumentException` for invalid ranges.** Qt must
   validate anything coming from applications. Validation rules observed (`probes/valid.m`):

   | range (min,max,pref) | result |
   |---|---|
   | (0,0,0) | ok (= `CAFrameRateRangeDefault`) |
   | (0,0,30), (0,60,30), (30,0,0), (-1,60,60), (nan,60,60) | **throws** |
   | (30,60,0), (10,60,0) | ok (preferred 0 = no preference) |
   | (10,60,5), (10,60,70), (60,30,30), (10,60,nan) | **throws** |
   | (0.5,60,60), (1000,1000,1000), (10,inf,60) | ok |

   So: all-zero, or `0 < min <= max` (max may be +inf), and `preferred == 0 || min <= preferred <= max`.

## CAMetalDisplayLink

`CAMetalDisplayLink` (macOS 14 / iOS 17) is attached to a `CAMetalLayer` and hands the client a
*drawable* along with the target present time, and it has `preferredFrameLatency` and
`preferredFrameRateRange`. It's the best fit for Metal renderers: it fixes the
"`nextDrawable` blocks at an unknown point" problem and gives explicit latency control.

Qt's frame model is *pull based*: the app calls `QWindow::requestUpdate()`, gets
`QEvent::UpdateRequest`, and QRhi's `beginFrame()` calls `[layer nextDrawable]` (possibly on Qt
Quick's render thread). CAMetalDisplayLink is *push based* (it gives you the drawable in its
callback, on the run loop it's scheduled on). Integrating it properly means:

* the QPA plugin owns a `CAMetalDisplayLink` per `QMetalLayer` (the window's layer) instead of the
  screen link, when the window is Metal-backed and opted in;
* the callback stashes `update.drawable` / `update.targetPresentationTimestamp` on the
  `QMetalLayer` and delivers the update request;
* `QRhiMetal::beginFrame()` consumes the stashed drawable instead of calling `nextDrawable`. The
  threaded render loop requires the handoff to be thread-safe (`QMetalLayer` already has a
  `displayLock` read/write lock used for the same kind of coordination);
* dropped frames: if the app doesn't render in response, the drawable has to be released.

That's a cross-module change (QPA + QtGui `QMetalLayer` + QRhi Metal backend) and needs a
QRhi-level opt-in, because the behavior of `beginFrame()` changes. It isn't implemented in this
branch. The design and proposed API are in `API-PROPOSAL.md`. The CADisplayLink work here is a
prerequisite, since it moves timing onto the main run loop and establishes the frame-rate intent
plumbing that CAMetalDisplayLink would reuse.

## Missing API / limitations identified

1. No cross-platform way for an app to say "I only need N fps" (`QWindow`, `QSurfaceFormat`,
   `QQuickWindow` have nothing). **Worked around now** with a dynamic property; public API proposed.
2. `QEvent::UpdateRequest` carries no timing information (the `FIXME` in `qcocoascreen.mm:296`).
   CADisplayLink gives `timestamp`/`targetTimestamp`, which Qt Quick's animation driver could use
   for better pacing. Proposed.
3. Hidden-window update-request semantics prevent using per-view links. Proposed as an explicit
   opt-in.
4. iPhone needs `CADisableMinimumFrameDurationOnPhone` in Info.plist for >60 Hz. That's an app
   decision, so it's documented, not changed.
5. qtmultimedia always uses the main screen's link (wrong on multi-display setups) and never tells
   the system the video frame rate.
