# 15 QAppleFrameRateRange: Round pacing to the nearest frame count

| | |
|---|---|
| Commit | `a901ccb10aa` (qtbase) |
| Files | `qappleframerate{.cpp,_p.h}`, `tst_qappleframerate.cpp` |
| Plan | Squash into 02 |

## What
* `framesPerDelivery()`: link frames between deliveries, rounded to the nearest count with ties
  to the faster rate (bias 1e-3, large compared to timestamp jitter), used by both
  `shouldDeliverFrame()` and `effectiveFrameInterval()`.
* `unitedWith()`: a range without a preferred rate means "up to the maximum", not "the lowest".
* `qt.qpa.framerate` logs from warnings up by default.

## Why
For intervals exactly between two multiples (24 fps on 60 Hz, 48 on 120, 96 on 240), the
threshold landed on a vsync, so frame gaps alternated with timestamp rounding, and disagreed with
the interval reported to Qt Quick. And a slower window could throttle a window asking for "up to
the maximum".

## Tests
Tie and non-integer refresh rate rows; every frame gap checked, with and without jitter.

## Note
The public API (23, 30) never produces non-exact rates, so rounding only matters for the private
property / env var ranges and for windows paced below a shared link's rate.
