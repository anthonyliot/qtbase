# Review #2: QWindow::preferredFrameRate, Apple pacing, Widgets (2026-09-26)

Multi-agent review of the uncommitted public API batch (qtbase + qtdeclarative), with each finding
verified adversarially. Below: what was found and what was done about it.

## Major

| # | Finding | Done |
|---|---|---|
| M1 | `FINAL` on the property breaks QML Window subtypes that declare their own `preferredFrameRate` (the override check ignores REVISION) | Dropped `FINAL`. QML tests: an own property of that name loads, a `QtQuick 6.12` import doesn't see the property |
| M2 | On the timer path `updateRequestInterval` stayed 0, so Qt Quick animations ran at the wrong speed (e.g. about 81% at 50 fps on 60 Hz) | The timer branch sets `max(1/fps, 1/refresh)` during delivery and resets it afterwards |
| M3 | A nested event loop in paced delivery (modal dialog opened while painting) stopped every display-link window on the screen | Cocoa watchdog: a timer (it fires in the nested loop) switches the screen's windows to timer-based update requests until the loop returns. `tst_QWindow::requestUpdateDuringNestedEventLoop` |
| M4 | A paced delivery after `update()` + `repaint()` (buttons, progress bars) repainted the whole top-level again | Forward the update request only if ours was sent or something is dirty. `pacedUpdatesSemantics` checks for exactly one paint |
| M5 | A widget top-level lost its preference when its `QWidgetWindow` was recreated | Kept in `QTLWExtra` and reapplied in `createTLSysExtra()`. `pacedUpdatesAfterRecreate` (reparenting, and adding a QRhiWidget) |
| M6 | `preferredFrameRateTimerPacing` failed on Wayland, which doesn't use the timer path | Allow-list of timer-based platforms (xcb, offscreen, minimal, windows, android, eglfs, linuxfb, cocoa) |

## Minor

| # | Finding | Done |
|---|---|---|
| m1-m3 | Docs overpromised: platforms, Widgets (cocoa/ios with vsync only, repaint deferral), QML (Animators run at the panel rate, QQuickWidget only paces composition) | Docs rewritten |
| m4 | Timer interval truncated to whole ms (61.7/s at 60) | Nanosecond `QBasicTimer` interval, measured from the previous delivery |
| m5 | A rate change didn't re-arm a pending timer (up to 1 s delay from 1 fps) | Base hook restarts the timer. `preferredFrameRateChangeWhilePending` covers both the timer and display link paths |
| m6 | No lower bound: tiny rates hit undefined behaviour in the int conversions | Quotients clamped to 1e6, timer interval capped at one hour, warning text fixed |
| m7 | Nearest rounding can drop below the preference when mixed with a legacy `_q_preferredFrameRateRange`/env range (legacy 30-60 plus public 24 on 120 Hz gives 20) | **Documented, not fixed.** Only reachable with the private knobs, which are for experiments. Fix with the shared pacer refactor below |
| m8 | `unitedWith()` depends on window order with legacy ranges; the literals 23.976/29.97/59.94 in env ranges miss the 1e-3 tolerance | **Documented, not fixed**, same reason. The public API is order independent (gcd of exact rates) |
| m9 | iOS never reports refresh rate changes, so `QScreen::refreshRate()` can be stale next to the live value used for the gcd | **Documented, not fixed.** Fix: pass the platform screen's rate into `QAppleFrameRateRange::update()`, or emit `handleScreenRefreshRateChange` on iOS |
| m10 | Display-paced tests compared against the nominal refresh rate (fails in Low Power Mode) | Compare against the measured unthrottled rate. VideoAndUi skips when the link runs below the refresh rate |
| m11 | Exact `qRound` interval comparison flaky for x.5 rates | Half-a-refresh tolerance |
| m12 | QRhiWidget row didn't skip without Metal | `QRhi::probe(QRhi::Metal)` |
| m13 | Widgets routing only tested on cocoa/ios with a preference | **Follow-up**: a `QT_WIDGETS_PACED_UPDATES=1` test target covering the opt-outs (WA_DontShowOnScreen, paint-on-screen, native children), hide/recreate while pending, QOpenGLWidget `frameSwapped` |
| m14 | QML test missed revision gating and binding-to-undefined | Added, and the misplaced comment moved back |
| m15 | `stepsWithPreferredFrameRate` still used the old nearest rule | Uses the "closest, not below" rule without a fallback |
| m16 | QML data file untracked | Added |

## Refuted or overstated (not acted on)

* 48/80/120 not covered: `tst_qappleframerate` has 48@120→60, 80@120→default, 24@60→30.
* macOS stale refresh rate: QCocoaScreen and QScreen share the CoreGraphics mode rate.
* The ceil/`qCeil` suggestions for the timer interval: they undershoot the preferred rate.
* `RhiBasedRendering` capability check for the QRhiWidget skip: does nothing on cocoa.

## Also added after the review

* `tst_QWindow::preferredFrameRatePerScreen`: with two screens, each screen's display link runs at
  its own rate and follows only its windows' preferences, including after a window moves to the
  other screen. Skips with one screen, so it hasn't run yet (only the built-in panel was connected).

## Found while verifying the fixes

* `animatorDurationWithPreferredFrameRate` failed about 1 run in 6: right after a window is shown,
  the Metal swapchain doesn't block for a moment, and the render thread rendered ~30 frames in 6 ms,
  each advancing Animators by one refresh (a 500 ms OpacityAnimator finished after 101-153 ms). The
  test now waits for the first frame and 300 ms before starting the Animator: 0 failures in 15 runs.
  The burst frames are rendered by the render thread on its own (no GUI sync in between), so they
  don't come from update request pacing. Not checked against a build without these changes.
* On ProMotion the panel itself drops to the preferred rate (30 Hz for 30 fps), so while an
  Animator runs the render thread renders at 30, not 120, and the render thread's driver, which
  assumes the nominal 120 Hz, runs Animators slow until it switches to timer mode after about 3
  frames (~100 ms). A fix needs the display link's actual rate (see the timing follow-up).

## Follow-ups

* Shared pacing helper (the fold over windows is duplicated in cocoa and iOS), which is also where
  m7/m8 get fixed.
* Public frame timing (target presentation time) for video, see API-PROPOSAL.md section 2. The
  same data (the display link's actual rate) would let the render thread step Animators right when
  the panel runs below its maximum.
* Full pacing for QQuickWidget (its scene still renders from a 5 ms timer).
* iOS nested event loops in delivery (re-entrant delivery rather than a blocked link).
