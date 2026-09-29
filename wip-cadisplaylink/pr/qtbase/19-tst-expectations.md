# 19 tst_QWindow: Make the frame-rate expectations follow the pacing rules

| | |
|---|---|
| Commit | `9e05b1ccbba` (qtbase) |
| Files | `tst_qwindow.cpp` |
| Plan | Squash into 07 |

## What
`qtPacedRate()` (Qt's nearest-count pacing for windows on a shared link) and
`systemPacedRates()` (bounds allowing the system to snap a single window's link to the next faster
rate); default rates compared to the rate the link reports (`unthrottledRate()`) rather than
`QScreen::refreshRate()`; invalid-preference tests no longer timing dependent; interval checked
only during delivery; 500 ms measurements.

## Why
The first expectations assumed "always the next faster divisor" and failed on 59.94, 50 and
144 Hz displays, and in Low Power Mode.

## Note
These helpers are for the private property ranges. The public API's expectations use
`framesForPreferredRate()` (30).
