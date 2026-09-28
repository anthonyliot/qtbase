# 07 tst_QWindow: Add tests for update request pacing and frame rates

| | |
|---|---|
| Commit | `1c4f0e03170` (qtbase) |
| Files | `tests/auto/gui/kernel/qwindow/tst_qwindow.cpp` |
| Plan | Keep; squash 19 into it |

## What
Tests for the display link behavior (no regression) and for the private frame-rate preference:
`requestUpdateRate`, `requestUpdateMultipleWindows` (main thread, several windows),
`requestUpdateCreatedButHidden`, `requestUpdateAfterHideAndShow`, `requestUpdateSwapIntervalZero`,
`preferredFrameRate` (number/list/map/string), `preferredFrameRateMixedWindows`,
`preferredFrameRateRuntimeChange`, `preferredFrameRateInvalid`.

## Why
The existing tests only checked that an update request arrives. The display link replacement and
pacing need their rates pinned down.

## How
* `AnimatingWindow` requests an update from each UpdateRequest; `measureUpdateRates()` runs a real
  `QEventLoop` (`QTest::qWait()` sleeps between events, which caps the rate).
* Rates are compared with a -20%/+10% tolerance (`QCOMPARE_RATE`): missed frames on a loaded
  machine are tolerated, overshooting is not.
* Display-paced tests are skipped on platforms other than cocoa/ios.

## Risks
* Timing tests: flaky if the window is covered (Qt stops rendering unexposed windows) or the
  machine is busy. Windows use `showAnimatingWindow()` and tests QSKIP when not exposed where it
  matters.
* The pacing tests passed with the CVDisplayLink implementation (no regression); the frame-rate
  tests fail with it (it always runs at the maximum), as expected.

## Verify
`tst_qwindow` on macOS with the display not in use; iOS simulator per PLAN.md.
