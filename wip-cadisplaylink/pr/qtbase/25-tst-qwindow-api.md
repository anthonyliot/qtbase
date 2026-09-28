# 25 tst_QWindow: Test QWindow::preferredFrameRate

| | |
|---|---|
| Commit | `0da9df72c2f` (qtbase) |
| Files | `tst_qwindow.cpp` |
| Plan | Keep |
| Later changed by | 30 (`framesForPreferredRate()`) |

## What
* `preferredFrameRateProperty`: default, change signal, same value doesn't emit, reset, invalid
  values warn and give 0, survives `create()`, metadata (resettable, notify, revision 6.13).
* `preferredFrameRateApi` (30, 24, 23.976, 25, 60, refresh rate): delivered rate and reported
  interval match the expected exact rate; n = 1 compares to the unthrottled rate.
* `preferredFrameRateApiVideoAndUi`: 24 + 60 both exact (skips if not both exact on the display,
  or if the link runs below the refresh rate).
* `preferredFrameRateTimerPacing`: timer platforms (allow-list) cap at the preference.
* `preferredFrameRateChangeWhilePending`: a change applies to a pending request within 500 ms, on
  the timer path and the display link path.
* `requestUpdateDuringNestedEventLoop`: another window keeps updating (≥ 10 fps) while a nested
  loop runs in delivery (skipped on iOS).
* `preferredFrameRatePerScreen`: with two screens, each link follows its own windows, and a
  window moving screens keeps updating at the new screen's rate (skips with one screen; has not
  run yet).

## Verify
`tst_qwindow` with the display not in use. Last results: see `../TESTING.md`.
