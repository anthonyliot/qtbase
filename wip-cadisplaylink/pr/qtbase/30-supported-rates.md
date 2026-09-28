# 30 cocoa, ios: Only pick frame rates the display link supports exactly

| | |
|---|---|
| Commit | `13038efe719` (qtbase) |
| Files | `qappleframerate{.cpp,_p.h}`, `qwindow.cpp` (doc), `tst_qappleframerate.cpp`, `tst_qwindow.cpp` |
| Plan | Squash into 23 |

## What
* Exact rates are `displayRate / n` only where n divides the whole refresh rate
  (`wholeDisplayRate()`), in `forPreferredFrameRate()` and in `exactFramesPerDelivery()` (gcd union).
* `forPreferredFrameRate()`: n = largest divisor of the refresh rate with
  `displayRate / n >= 0.99 * fps`, searched from `min(displayRate / (0.99 fps), refresh rate)`
  down, so at most `refresh rate` steps; tiny rates give 1 fps.
* Tests: `framesForPreferredRate()` helper in `tst_qwindow` replaces two copies of the old formula;
  new rows in `tst_qappleframerate` from the measurements.
* `QWindow::preferredFrameRate` doc: says which rates are exact.
* Also: the `QAppleFrameRatePreference` class comment describes the public API (stale since 23).

## Why
Measured on a 240 Hz display (`wip-cadisplaylink/probes/divisors.m`, VIDEO.md): CoreAnimation
runs a link at 240 / n only when that's a whole rate; 26.67, 34.29, 21.82, 18.46 and 17.14 are
rounded up to 30, 40, 24, 20, 20. `preferredFrameRateApi(25)` failed on that display (Qt asked for
26.67 and expected it, the system gave 30).

The outcome for a single window was already right (30 is not below 25), but Qt's notion of exact
rates, used for the gcd union, didn't match the system's.

## Risks
* The rule was measured on one 240 Hz display (n = 1..16, 20, 24) and, earlier, on the 120 Hz
  ProMotion panel for n = 1..5 only. A display with a fractional nominal rate (59.94) uses the
  rounded whole rate (60) for the divisor check.

## Tests
`tst_qappleframerate` 136 pass; `tst_qwindow preferredFrameRateApi*` pass on 240 Hz.
