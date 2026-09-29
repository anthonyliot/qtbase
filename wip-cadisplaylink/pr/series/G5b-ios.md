# G5b ios: Pace update requests to the windows' preferred frame rates

| | |
|---|---|
| Files | `src/plugins/platforms/ios/{qiosscreen.h,qiosscreen.mm,qioswindow.h,qioswindow.mm}` |
| From | old 06, and the iOS parts of 10, 16, 18, 23; R1-9, m9 |

## What
The iOS display link delivery uses `QAppleDisplayLinkDelivery` (from G5a), with the platform
screen's live refresh rate; the link's range follows the pending windows; `setPreferredFrameRate()`
applies to a pending request and calls the base; `pacesUpdateRequests()` is false without a display
link (visionOS). Also fixes a request that came in during another window's delivery staying pending
(the link was paused afterwards).

## Verified
iOS isn't built in the macOS series build. The iOS sources at G5b are the final ones, built and run
on the simulator at the final state (TESTING.md); what differs at G5b is only the cocoa plugin, the
Widgets code, and the `QWindow` doc.
