# G5c cocoa: Pace update requests to the windows' preferred frame rates

| | |
|---|---|
| Files | `src/plugins/platforms/cocoa/{qcocoascreen.h,qcocoascreen.mm,qcocoawindow.h,qcocoawindow.mm}`, `src/gui/kernel/qwindow.cpp` (doc), `tst_qwindow.cpp` |
| From | the cocoa parts of old 04, 10, 23, 25 |

## What
* The G2 delivery loop is replaced by `QAppleDisplayLinkDelivery`; the link's range follows the
  pending windows (`setDisplayLinkFrameRate()`, `updateDisplayLinkFrameRate()`);
  `tryDeliverUpdateRequest()` reports the Metal-layer deferral;
  `setPreferredFrameRate()`/`pacesUpdateRequests()` (preference, and vsync on).
* `QWindow::preferredFrameRate` doc: the macOS/iOS exact rates, windows that can't be exact
  together, the Qt Quick behavior (with qtdeclarative D1), and which platforms pace to the display.
* Tests: the frame-rate `tst_qwindow` tests (private preference, mixed windows, runtime change,
  interval, public API rows, video + UI, change while pending, per screen), with exact pacing checks.

## Verified
TESTING.md, series section.
