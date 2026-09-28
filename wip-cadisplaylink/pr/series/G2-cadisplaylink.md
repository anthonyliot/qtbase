# G2 cocoa: Replace CVDisplayLink with CADisplayLink for update requests

| | |
|---|---|
| Files | `src/plugins/platforms/cocoa/{qcocoascreen.h,qcocoascreen.mm,qcocoawindow.h,qcocoawindow.mm,CMakeLists.txt,qcocoa_plugin_pch.h}`, `tst_qwindow.cpp` |
| From | old 03, 16, 17, 20, 28, 29; round 1 fixes R1-1 (watchdog), R1-4, R1-5 |

## What
* One `CADisplayLink` per `QCocoaScreen`, from `-[NSScreen displayLinkWithTarget:selector:]`, on
  the main run loop in common modes; paused when no window on the screen has a pending display-link
  update request, resumed by `QCocoaScreen::requestUpdate()`.
* Delivery (plain, no pacing yet): snapshot the screen's display-link windows as `QPointer`s, deliver
  pending ones, then a second pass for windows that got a request while delivering to a window after
  them; pause if nothing is pending.
* Display ID change: recreate the link; if the NSScreen isn't there yet, fall back to timer based
  update requests (`fallBackToTimerBasedUpdateRequests()`).
* `QCocoaWindow::stopFallbackUpdateTimer()` when the link takes over.
* One watchdog `QTimer`: during delivery (only fires in a nested event loop) → timer fallback until
  the delivery returns; between deliveries, while the link runs with pending requests, no callback
  for ten frames (≥ 1 s, backing off to 8 s) → recreate the link, unless `CGDisplayIsAsleep()`.
* `updatesWithDisplayLink()` uses the requested format's swap interval, not `format()` (which parses
  the ICC color space).
* The link's frame interval is reported to the window during delivery, in the new private
  `QWindowPrivate::updateRequestInterval`, so tests compare against the link's real rate from G2 on
  (R2-2).
* A second watchdog recovery in a row marks the link as stalled: windows use timer based update
  requests until a real callback arrives, bounding a freeze to about 3 s (R2-1).
* CoreVideo no longer linked; comments updated; live-resize event tap kept (FIXME: not
  re-validated).
* Tests added: `requestUpdateForOtherWindowDuringDelivery`, `requestUpdateDuringNestedEventLoop`.

## Why
Request #1 (CVDisplayLink is deprecated; CADisplayLink needs macOS 14, the minimum is 14.4), and the
prerequisite for frame-rate intent (G5). Pausing when idle avoids up to 240 wakeups/s.

## Risks
See old 03 doc; the stall recovery is defensive (the stall was only seen with explicit ranges, G5).

## Verified
TESTING.md, series section.
