# G5a Add a shared model of display link frame rates for Apple platforms

| | |
|---|---|
| Files | `src/gui/platform/darwin/qappleframerate{.cpp,_p.h}`, `src/gui/CMakeLists.txt`, `tests/auto/gui/platform/{CMakeLists.txt,qappleframerate/*}` |
| From | old 02, 15, 30, the helper parts of 09 and 23; R1-1, R1-2, R1-3, R1-11, R1-12 |

## What
Platform independent QtGui code (Apple builds only), not used yet:
* `QAppleFrameRateRange`: CAFrameRateRange model; validation (CoreAnimation throws); parsing;
  `forPreferredFrameRate()` (slowest exact supported rate not below the preference, exact = refresh
  rate divided by one of its divisors); `unitedWith()` (gcd of exact rates); pacing
  (`shouldDeliverFrame()`, `effectiveFrameInterval()`).
* `QAppleFrameRatePreference`: `QWindow::preferredFrameRate`, else `_q_preferredFrameRateRange`,
  else `QT_APPLE_PREFERRED_FRAME_RATE_RANGE`; maximum-rate private ranges become the default range.
* `QAppleDisplayLinkDelivery`: the per-screen delivery (two passes, pacing, interval during
  delivery, deferral-aware, `QPointer` lifetime, range from all pending windows).

## Tests
`tst_qappleframerate`: 151 cases, no display needed; the delivery cases use synthetic display
link frames and never created windows.
