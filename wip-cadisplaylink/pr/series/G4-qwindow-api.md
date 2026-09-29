# G4 Add QWindow::preferredFrameRate

| | |
|---|---|
| Files | `src/gui/kernel/{qwindow.h,qwindow.cpp,qwindow_p.h,qplatformwindow.h,qplatformwindow.cpp,qplatformwindow_p.h}`, `tst_qwindow.cpp` |
| From | old 22 (generic parts); R1-6 |

## What
* Public: `Q_PROPERTY(qreal preferredFrameRate ... RESET ... NOTIFY ... REVISION(6, 13))`, not FINAL;
  setter warns on negative/non-finite and uses 0; no signal for the same value.
* QPA: `virtual void setPreferredFrameRate(qreal)` (default re-arms a pending timer request),
  `virtual bool pacesUpdateRequests() const` (default false).
* Timer platforms: next timer ≥ `1/fps - elapsed since the last delivery` (nanoseconds, capped at an
  hour); during delivery `QWindowPrivate::updateRequestInterval = max(1/fps, 1/refresh)`.
* Doc: what's true at this commit only (a hint, the timer platforms' minimum interval, others
  ignore it); the macOS/iOS pacing is documented in G5c, Widgets in G6 (R2-2).
* Tests: `preferredFrameRateProperty`, `preferredFrameRateTimerPacing` (allow-list of timer
  platforms).

## Verified
TESTING.md, series section.
