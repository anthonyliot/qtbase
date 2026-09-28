# 18 cocoa, ios: Only report the update request interval during delivery

| | |
|---|---|
| Commit | `e1368147955` (qtbase) |
| Files | `qwindow_p.h`, `qcocoascreen.mm`, `qiosscreen.mm` |
| Plan | Squash into 09/10 |

## What
Reset `updateRequestInterval` to 0 after `deliverUpdateRequest()` returns (if the platform window
still exists).

## Why
It stayed set, so frames driven by expose events (e.g. live resize) made Qt Quick advance
animations by the paced interval, too fast for low-rate windows.

## Tests
`preferredFrameRateUpdateRequestInterval` checks it's 0 outside delivery.
