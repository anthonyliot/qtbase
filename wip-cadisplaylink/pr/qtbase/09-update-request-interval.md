# 09 Track the expected interval between paced update requests

| | |
|---|---|
| Commit | `04eccb2734a` (qtbase) |
| Files | `src/gui/kernel/qwindow_p.h`, `qplatformwindow.cpp`, `src/gui/platform/darwin/qappleframerate{.cpp,_p.h}`, `tst_qappleframerate.cpp` |
| Plan | Keep; squash 18 into it (or into 10) |
| Later changed by | 18 (only valid during delivery), 22 (set on the timer path with a preference) |

## What
`QWindowPrivate::updateRequestInterval` (seconds, 0 = unknown): the interval the platform paces
the window's update requests at. `QAppleFrameRateRange::effectiveFrameInterval(linkInterval)`
computes it for the Apple pacing.

## Why
Qt Quick advances vsync-driven animations by one vsync per frame. At 30 fps on a 240 Hz display
they would run 8 times too slow until the driver gives up and uses wall-clock time (see
qtdeclarative 01, which consumes this).

## How
Private member, set by the platform right before delivery. The timer path in
`QPlatformWindow::windowEvent()` reset it to 0.

## Risks
Private API between qtbase and qtdeclarative (same Qt version, allowed). Not a public timing API
(that's a follow-up, `API-PROPOSAL.md` section 2).

## Tests
`tst_qappleframerate::effectiveFrameInterval*`; 10 tests the value per window.
