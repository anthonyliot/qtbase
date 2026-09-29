# Round 5 review — qtmultimedia QVideoWindow frame-rate integration + multi-display audit

Reviewer: qt-cadisplaylink-pr-reviewer (independent, strict)
Scope:
- TASK A: one commit, qtmultimedia `wip/cadisplaylink`
  Commit: `0c6ed5e9c` "QVideoWindow: Drive the window's preferred frame rate from the video"
  File: `src/multimedia/video/qvideowindow.cpp`
- TASK B: multi-display correctness of the three display-link usages in play.

Base: upstream `635067497` ("Update dependencies on 'dev' in qt/qtmultimedia").
Depends on: `QWindow::preferredFrameRate` (qtbase `wip/cadisplaylink`, Qt 6.13).

---

# TASK A — QVideoWindow preferred-frame-rate integration

## The change

```cpp
void QVideoWindow::setVideoFrame(const QVideoFrame &frame)
{
    ...
    d->m_texturePool.setCurrentFrame(frame);

    const qreal streamFrameRate = frame.surfaceFormat().streamFrameRate();
    if (streamFrameRate >= 0)
        setPreferredFrameRate(streamFrameRate);

    if (d->isExposed)
        requestUpdate();
}
```
(`qvideowindow.cpp:518-535`)

`QVideoWindow` is a `QWindow` (`qvideowindow_p.h:91`), so `setPreferredFrameRate`
is `QWindow::setPreferredFrameRate`.

## Verification

### 1. Threading — on the GUI thread (CONFIRMED, no regression)

`setPreferredFrameRate` touches `d->platformWindow` and emits
`preferredFrameRateChanged`; like `requestUpdate()` it must run on the GUI
thread. `setVideoFrame` is invoked only via
`QObject::connect(m_sink, &QVideoSink::videoFrameChanged, q, &QVideoWindow::setVideoFrame)`
(`qvideowindow.cpp:67`), a default (auto) connection. `QVideoWindow` and its
`m_sink` live on the GUI thread; a decoder emitting `videoFrameChanged` from a
worker thread therefore delivers `setVideoFrame` as a queued call on the GUI
thread. This is exactly the invariant the pre-existing `requestUpdate()` on the
line below already relies on, so the new call adds no new threading assumption.

### 2. Value safety — `streamFrameRate()` is safe to pass (CONFIRMED)

* `QVideoFrameFormat::streamFrameRate()` returns `d->frameRate`
  (`qvideoframeformat.cpp:561`), which defaults to `0.0`. `0` = no preference —
  the documented default of `QWindow::preferredFrameRate`
  (`qwindow.cpp:1323`). A frame with unknown rate correctly imposes no preference.
* `QWindow::setPreferredFrameRate` itself hardens the input:
  `if (!qIsFinite(fps) || fps < 0) { qWarning(...); fps = 0; }`
  (`qwindow.cpp:1351-1355`). So even a NaN/negative/infinite rate can't reach
  CoreAnimation as an invalid range; qtbase clamps to 0.
* Redundant-call cost is bounded: `setPreferredFrameRate` early-returns on an
  unchanged value (`if (fps == d->preferredFrameRate) return;`,
  `qwindow.cpp:1356`) before touching the platform window or emitting. For a
  steady stream the per-frame cost is one `qreal` comparison plus a
  `frame.surfaceFormat()` construction (implicitly shared, cheap) — negligible
  against per-frame texture upload and render.

### 3. Pause/stop behavior (CONFIRMED correct on stop)

On stop / layer teardown the darwin renderer pushes an empty frame:
`AVFVideoRendererControl::setLayer(...)` → `m_sink->setVideoFrame(QVideoFrame())`
(`avfvideorenderercontrol.mm`). A null frame's
`surfaceFormat().streamFrameRate()` is `0`, so the preference resets to "no
preference" — the window stops constraining the display rate. Good.
On *pause* frames merely stop arriving; the last preference lingers, but the
window also stops calling `requestUpdate()`, so the screen's display link
pauses anyway (`QCocoaScreen::maybePauseDisplayLink`). A stale hint with no
pending updates has no effect. Acceptable.

### 4. Is QVideoWindow the right hook? (YES)

- `QVideoSink` is the natural frame funnel but is **not** a window and holds no
  window handle — it can't set a per-window rate, and a sink may drive a custom
  renderer with no `QWindow` at all. `QMediaPlayer` is further still from any
  window. `QVideoWindow` is the one place that both owns the frame stream and
  *is* the `QWindow` that renders it. Hooking here is correct.
- **QVideoWidget is covered for free**: it renders through an internal
  `QVideoWindow` (`qvideowidget.cpp:63`, embedded via
  `QWidget::createWindowContainer`), and its sink is that window's sink
  (`qvideowidget.cpp:87`). So the same `setVideoFrame` path sets the preference
  on the widget's video window. See finding A5-2 for the one caveat.

### 5. Build (CONFIRMED)

`cmake --build /Users/anthony.liot/Desktop/bitbucket/qtmm-build --target
Multimedia` → `[100%] Built target Multimedia`, no errors. The changed TU is
genuinely rebuilt: `qvideowindow.cpp.o` mtime is newer than the source at HEAD.

### 6. Commit message and Qt style (GOOD)

Imperative subject with `QVideoWindow:` area prefix; body gives *why* (wasted
power, VRR panels can't follow cadence) before *how*; states the 24 Hz/ProMotion
example and the reset-on-unknown behavior; records the cross-module dependency
("Requires QWindow::preferredFrameRate (Qt 6.13)"). Body wraps ~72 cols,
Change-Id present, license header untouched, no WIP content.

## Findings (TASK A)

### A5-1 — minor — `streamFrameRate >= 0` guard leaves a stale preference for a bogus rate instead of resetting

`qvideowindow.cpp:530-531`. The guard calls `setPreferredFrameRate` only when
`streamFrameRate >= 0`. For a negative rate — and, because `NaN >= 0` is false,
for a NaN — the call is skipped, so any previously-set preference *persists*
rather than being cleared. `QWindow::setPreferredFrameRate` already clamps
negative/NaN/inf to 0 with a warning (`qwindow.cpp:1351`), so the guard is
redundant *and* slightly wrong: the safer behavior on a garbage rate is to reset
to no-preference, which is what an unguarded call would do. Impact is low
(decoders don't emit negative/NaN stream rates in practice), hence minor. Fix:
drop the guard and call `setPreferredFrameRate(streamFrameRate)` unconditionally
— qtbase does the validation — or, if a guard is wanted for clarity, reset
explicitly on the bad-value branch. Resolved when a non-finite/negative stream
rate provably yields `preferredFrameRate() == 0` rather than the prior value.

### A5-2 — minor — QML `VideoOutput` is not addressed; embedded `QVideoWidget` path is untested; document the asymmetry

The hook only fires for content rendered through `QVideoWindow`. The QML
`VideoOutput` (`QQuickVideoOutput`) composites into the application's shared
`QQuickWindow` scene graph (`qquickvideooutput.cpp` uses `window()` /
`QQuickWindow`, never a `QVideoWindow`) and gets no preference — so a 24 fps clip
in a Quick app does not lower the window's rate. That is a *defensible* scope
decision, not a bug: a `VideoOutput` is one item among many in a window shared
with other animations and possibly other videos, so setting a whole-window rate
from one item is a policy choice, not an obvious win (exactly the reasoning that
makes the per-window `QVideoWindow` the safe place to act). Separately, the
`QVideoWidget` path routes through an *embedded child* `QVideoWindow`
(`createWindowContainer`, `qvideowidget.cpp:65`); the preference is set on it,
but per-screen pacing of a container-embedded child window is not exercised by
any test in this PR. Neither is blocking. Ask: a one-line note in the
`preferredFrameRate` docs (or the commit/known-limitations) that QML
`VideoOutput` intentionally does not drive the window rate, and — nice to have —
a smoke test that a `QVideoWidget` actually paces. Resolved when the QML
limitation is documented.

---

# TASK B — Multi-display correctness of the three display-link usages

Setup considered: a multi-display macOS machine, the video window on a display
that is **not** the focused / "main" one, plus moving the window between
displays while playing.

## 1. qtbase Cocoa `QCocoaScreen` display link — CORRECT per-screen

`src/plugins/platforms/cocoa/qcocoascreen.mm`. Each `QCocoaScreen` owns its own
`CADisplayLink`, created from **its own** `NSScreen`:
`m_displayLink = [[nsScreen displayLinkWithTarget:target ...] retain]` where
`nsScreen = nativeScreen()` resolves this screen's `NSScreen` from its
`m_displayId` (`qcocoascreen.mm:304-317`, `nativeScreen()` at :1036-1041). The
per-window preferences are unioned **per screen** in `updateDisplayLinkFrameRate`
/ `QAppleDisplayLinkDelivery::pendingRange` (:609-616) and applied only to that
screen's link. When the window's `m_displayId` changes, `QCocoaScreen::update`
recreates the link against the new `NSScreen` without stranding pending updates
(:221-228), and the window follows via `windowDidChangeScreen`. The stored
preference is reapplied to the platform window through
`QPlatformWindow`'s creation/relocation path (`qplatformwindow.cpp:475`), so the
new screen's link picks it up. **Directly tested** by
`tst_QWindow::preferredFrameRatePerScreen`
(`tests/auto/gui/kernel/qwindow/tst_qwindow.cpp`), which on a two-screen rig
proves: (a) each screen runs at its own rate, (b) a preference on one screen does
not slow the other, and (c) moving an animating window to the second screen moves
its paced updates there and applies the preference on the destination screen
(`QSKIP` when <2 screens). Claim holds.

## 2. qtmultimedia `AVFDisplayLink` — `NSScreen.mainScreen`, once at construction — PRE-EXISTING, out of scope, does not break the display story

`src/plugins/multimedia/darwin/mediaplayer/avfdisplaylink.mm:96-99`. The link is
created from `NSScreen.mainScreen`, chosen once in the constructor and never
re-evaluated.

- **Is it the focused screen, not the video's?** Yes. `NSScreen.mainScreen` is
  "the screen containing the window that is currently receiving keyboard events"
  — the focused screen, which on a multi-display setup is frequently *not* the
  display the video window sits on.
- **Does it follow window moves?** No. It is fixed at construction and there is
  no `windowDidChangeScreen` equivalent here — `AVFDisplayLink` has no window at
  all.
- **Pre-existing?** Yes. Against base `635067497`, the macOS-15 branch already
  used `[NSScreen.mainScreen displayLinkWithTarget:...]` and the macOS-14 branch
  used `CVDisplayLinkCreateWithCGDisplay(kCGDirectMainDisplay, ...)` — both a
  "main display" clock. Branch commit `2152cdbd8` only deleted the dead
  CVDisplayLink fallback (reviewed in round 4); it did **not** introduce the
  main-screen choice.
- **Does it matter?** No, for correctness of *what the user sees*. `AVFDisplayLink`
  is the **decode-side clock** inside `AVFVideoRendererControl`: its `tick`
  drives `updateVideoFrame`, which only *polls* `AVPlayerItemVideoOutput` and
  early-returns when there is no new pixel buffer
  (`avfvideorenderercontrol.mm`, `copyPixelBufferFromLayer` → `if (!pixelBuffer)
  return;`). It is fully decoupled from the display window and the window's own
  screen link. If `mainScreen` runs faster than the video window's display, the
  only effect is more frequent (mostly no-op) polling; it never fabricates extra
  frames, and it never sets the panel refresh rate. Display pacing is owned
  entirely by usage #3 below.

  The realistic downside is minor and pre-existing: on a machine where the
  focused display is *slower* than the video's display, decode polling is capped
  at the slower rate — a latency/throughput nit for the decode clock, not a
  rendering defect. Round 4's R4-1 already flags the related `mainScreen == nil`
  headless edge.

## 3. New `QVideoWindow` integration — MULTI-DISPLAY-CORRECT BY CONSTRUCTION

Commit `0c6ed5e9c` sets the preference on the *window*, not on any display. It
therefore inherits usage #1's per-screen machinery wholesale: the preference is
applied on whichever screen the `QVideoWindow` currently occupies, and follows
the window across displays (window recreation/relocation reapplies the stored
value, and `preferredFrameRatePerScreen` proves the move case). The commit
message's claim ("follows the window across displays") is accurate. This is the
right layer to have chosen precisely because it delegates all multi-display
reasoning to the platform.

## Multi-display conclusion

The multi-display story **holds** for the feature the PR is about — driving the
display refresh rate from video. The only usage that constrains actual on-screen
pacing is #3, which is per-screen-correct and move-correct by delegating to #1,
and #1 is per-screen-correct and covered by a real two-screen test. Usage #2's
`NSScreen.mainScreen` is a **pre-existing decode-clock detail**, decoupled from
display pacing, not introduced or worsened by this PR. It does **not** warrant a
fix in this PR: fixing it (tracking the rendering window's screen for the decode
link) is a separate, pre-existing improvement with no visible-behavior payoff for
the stated goal, and would expand scope. Recommend recording it as an accepted,
pre-existing, out-of-scope limitation (alongside R4-1).

---

# Verdict

## TASK A: APPROVE

Severity counts: blocker 0, major 0, minor 2, nit 0.

- A5-1 — minor — `streamFrameRate >= 0` guard leaves a stale preference for a
  negative/NaN rate instead of resetting; guard is redundant with qtbase's own
  clamp.
- A5-2 — minor — QML `VideoOutput` intentionally not addressed and the embedded
  `QVideoWidget` pacing is untested; document the QML limitation.

The integration is correct: right thread (same invariant as the existing
`requestUpdate()`), safe value (`0` = no preference, negatives/NaN clamped by
qtbase), resets on stop via the null frame, cheap redundant calls (early-return),
right hook (`QVideoWindow` is the only window-aware funnel; `QVideoWidget` comes
along for free), builds clean, good commit message.

## TASK B multi-display assessment: HOLDS

The display-pacing path (#3 → #1) is per-screen-correct and follows window moves,
proven by `tst_QWindow::preferredFrameRatePerScreen`. `AVFDisplayLink`'s
`NSScreen.mainScreen` (#2) is a pre-existing decode-side clock decoupled from
display pacing; it does **not** warrant a fix in this PR and should be recorded
as an accepted pre-existing out-of-scope limitation.
