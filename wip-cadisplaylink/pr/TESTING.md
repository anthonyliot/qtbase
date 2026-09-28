# Test results

All on macOS 27.2, Apple M5 Max, debug developer builds (see README "Building and testing").
"Activation" failures are `QTest::qWaitForWindowActive()` failing because another application
(the terminal, or the user) has focus; they fail the same way on the unmodified baseline
(`qt5-build-cadisplaylink/baseline-tst_qwindow.txt`) and pass when nothing else has focus.

## 2026-09-28, 240 Hz external display (Odyssey G95SC), branch head

| Suite | Result |
|---|---|
| tst_qappleframerate | 136 passed |
| tst_qwindow | 106 passed, 3 failed (activation/cursor: activateDeactivateEvent, enterLeaveOnWindowShowHide x2), 8 skipped (platform-specific, and preferredFrameRatePerScreen: one screen) |
| tst_qwidgetrepaintmanager | 17 passed, 2 failed: scrollWithOverlap (activation), pacedUpdates(QRhiWidget) once ("not unpaced after resetting the preference"; 0 failures in 14 reruns, and the check now reports the rates and skips if the window was covered) |
| tst_qquickwindow | 119 passed, 8 failed (all activation; the user was using the machine), 1 skipped |
| tst_qquickanimations | 73 passed |
| animatorDurationWithPreferredFrameRate + stepsWithPreferredFrameRate, 10 runs | 0 failures |

Before commit 30 (supported rates), `tst_qwindow::preferredFrameRateApi(25)` failed on this
display: Qt asked for 240 / 9 = 26.67, the system delivered 30.

## 2026-09-26, 120 Hz ProMotion built-in display

| Suite | Result |
|---|---|
| tst_qappleframerate | 123 passed (before commit 30) |
| tst_qwindow | 106 passed, 3 failed (activation, same as baseline), 7 skipped |
| tst_qwidgetrepaintmanager | 19 passed |
| tst_qquickwindow | 127 passed, 1 skipped |
| tst_qquickanimations | 72 passed |
| animatorDurationWithPreferredFrameRate, 15 runs | 0 failures (after the settle fix; 3 in 18 before) |

## iOS simulator (iPhone 18 Pro, iOS 27, 60 Hz), 2026-09-26

| Suite | Result |
|---|---|
| tst_qappleframerate | 123 passed |
| tst_qwindow (display link and frame-rate tests) | 39 passed, 5 skipped (60 Hz: 24 and 60 not both exact; no timer path; nested loops; one screen; swap interval 0) |

## Not run

* `preferredFrameRatePerScreen` (needs two screens connected at once).
* Wayland/xcb/Windows: the timer-path pacing test has only run on cocoa (it's in the allow-list).
* Real-mouse live resize with the event tap removed.
