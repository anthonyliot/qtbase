# 10 cocoa, ios: Report the update request interval to the window

| | |
|---|---|
| Commit | `53f2184ac65` (qtbase) |
| Files | `qcocoascreen.mm`, `qiosscreen.mm`, `tst_qwindow.cpp` |
| Plan | Keep |
| Later changed by | 18 |

## What
Before delivering to a window, the screen sets `updateRequestInterval` to
`frameRatePreference.effectiveFrameInterval(linkFrameInterval)`.

## Tests
`tst_qwindow::preferredFrameRateUpdateRequestInterval` (default, 30, 24, 60): the interval is a
whole number of refreshes, within one refresh of the requested interval, consistent with the
measured rate, and 0 outside delivery.
