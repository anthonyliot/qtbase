# 04 cocoa: Let windows express a preferred frame-rate range

| | |
|---|---|
| Commit | `07923f8f3d0` (qtbase) |
| Files | `src/plugins/platforms/cocoa/qcocoascreen{.h,.mm}`, `qcocoawindow.h` |
| Plan | Keep |
| Later changed by | 16 (re-scan before pausing), 23 (public API, gcd union with the display rate) |

## What
The display link's `preferredFrameRateRange` follows the windows' preferences, and windows are
paced individually on the shared link. The preference comes from the private
`_q_preferredFrameRateRange` property or the `QT_APPLE_PREFERRED_FRAME_RATE_RANGE` env var
(parsed by 02). The public API comes later (22/23).

## Why
Every animating window ran at the display's maximum (240 Hz). The system can only lower the
refresh rate if the application says what it needs.

## How
* Each `QCocoaWindow` has a `QAppleFrameRatePreference`.
* During delivery, each pending window's preference is re-read; `shouldDeliverFrame()` decides
  whether it gets this link frame (based on the link's target timestamp and frame interval, from
  the display link target).
* Windows still pending after the pass are united (`unitedWith()`) into the link's range, set with
  `setDisplayLinkFrameRate()` (skipped when unchanged, refused if invalid).
* `requestUpdate()` outside delivery updates the range right away, so that a fast window that
  starts animating isn't held back by a slow link for a frame.

## Risks and edge cases
* The range only reflects windows with pending requests, so an idle fast window doesn't keep the
  link fast.
* A 30 fps window next to a 240 fps window: the link runs at 240, the 30 fps window is paced to
  every 8th frame (tested in 07).

## Tests
07: `preferredFrameRate`, `preferredFrameRateMixedWindows`, `preferredFrameRateRuntimeChange`,
`preferredFrameRateInvalid`.

## Verify
`tst_qwindow preferredFrameRate preferredFrameRateMixedWindows preferredFrameRateRuntimeChange preferredFrameRateInvalid`
