# 06 ios: Honor the preferred frame-rate range of windows

| | |
|---|---|
| Commit | `8e35d2b83e2` (qtbase) |
| Files | `src/plugins/platforms/ios/qiosscreen{.h,.mm}`, `qioswindow.h` |
| Plan | Keep |
| Later changed by | 10, 16, 18, 23 |

## What
Same mechanism as 04 on iOS, whose display link already was a CADisplayLink: the link's range is
the union of the pending windows' preferences, and windows are paced individually.

## Why
On ProMotion iPads/iPhones every animating window ran at up to 120 Hz.

## How
* `deliverUpdateRequests(CADisplayLink *)` gets the link to read `targetTimestamp`/`timestamp`.
* `setUpdatesPaused(false)` (the iOS equivalent of the screen's `requestUpdate()`) updates the
  range outside delivery; a `m_deliveringUpdateRequests` flag defers that during delivery.
* The applicationStateChanged path calls `deliverUpdateRequests(m_displayLink)` with the link's
  last timestamps.

## Risks and edge cases
* iPhones only run above 60 Hz with `CADisableMinimumFrameDurationOnPhone` in Info.plist.
* The iOS link is in `NSDefaultRunLoopMode` (unchanged): no delivery during UIKit tracking modes.
* No recursion guard on iOS: a nested loop in delivery can re-enter `deliverUpdateRequests`
  (see README, known limitations).
* When called from applicationStateChanged the timestamps are stale; `shouldDeliverFrame` then
  either delivers (time went backwards / first frame) or skips one frame.

## Tests
07's frame-rate tests run on the iOS simulator (60 Hz); last run 39 pass, 5 skip.
