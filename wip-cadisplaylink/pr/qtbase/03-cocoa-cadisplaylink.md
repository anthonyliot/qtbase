# 03 cocoa: Replace CVDisplayLink with CADisplayLink for update requests

| | |
|---|---|
| Commit | `f7240d14d39` (qtbase) |
| Files | `src/plugins/platforms/cocoa/qcocoascreen{.h,.mm}`, `qcocoawindow.mm` |
| Plan | Keep; squash 17 (fallback timer), 20 (comment), 28 (CoreVideo) into it |
| Later changed by | 04, 10, 16, 17, 18, 23, 29 |

## What
`QCocoaScreen` drives update requests with a `CADisplayLink` from
`-[NSScreen displayLinkWithTarget:selector:]` instead of a `CVDisplayLink`.

## Why
CVDisplayLink is deprecated. CADisplayLink is the supported API, available from macOS 14; Qt's
minimum is 14.4 (`.cmake.conf`), so no runtime fallback is needed. It's also what allows frame-rate
intent (`preferredFrameRateRange`), which CVDisplayLink doesn't have.

## How
* Still **one link per screen** (not per view), so that windows that are created but not visible
  still get their update requests, as before. A per-view link stops when the view is off screen
  (measured, AUDIT.md), which would strand pending requests.
* The callback now comes on the **main run loop** (added in `NSRunLoopCommonModes`, like the main
  GCD queue the old code dispatched to), so the GCD source, the cross-thread atomics
  (`m_pendingUpdateRequests`, `m_pendingDisplayLinkUpdates`) and the "missed updates" warning are
  gone.
* A small ObjC target (`QCocoaDisplayLinkTarget`) forwards to
  `QCocoaScreen::deliverUpdateRequests()`; the link retains the target, the target holds a raw
  pointer to the screen, and the screen invalidates the link in its destructor.
* **Paused when idle**: after a delivery pass with no pending request on the screen, the link is
  paused, and `requestUpdate()` resumes it. The old code kept the CVDisplayLink thread running
  forever once started (up to 240 wakeups/s when idle).
* The link is recreated when the screen's display ID changes (`QCocoaScreen::update()`), keeping
  pending requests.
* A recursion guard skips a display link callback while a delivery is on the stack.
* The live-resize event tap workaround is kept (comment updated in 20).

## Risks and edge cases
* Behavior during live resize, menus and modal sessions depends on the common modes (checked by
  hand, PLAN.md; the event tap is not re-validated).
* Screen removal while a delivery (nested loop) is on the stack would delete the screen under
  the call; the old GCD handler had the same exposure.
* Delivery iterates `QGuiApplication::allWindows()` as raw pointers, as before.

## Tests
07 (`requestUpdate*` tests: rate at the refresh rate, main thread, multiple windows, created but
hidden, hide/show, swap interval 0) pass before and after this commit. 16 adds the "window driving
another window" test.

## Verify
`tst_qwindow requestUpdate requestUpdateRate requestUpdateMultipleWindows requestUpdateCreatedButHidden requestUpdateAfterHideAndShow requestUpdateSwapIntervalZero`;
the manual test `tests/manual/displaylink`; idle wakeups with `bench/crt-ab.sh`/`qqem-ab.sh`.

## Questions for the reviewer
* Is pausing when idle safe for every path that sets a pending request without calling
  `QCocoaScreen::requestUpdate()`? (16 and the `windowDidChangeScreen` path are the known ones.)
