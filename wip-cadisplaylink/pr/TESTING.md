# Test results

All on macOS 27.2, Apple M5 Max, debug developer builds (see README "Building and testing").
"Activation" failures are `QTest::qWaitForWindowActive()` failing because another application
(the terminal, or the user) has focus; they fail the same way on the unmodified baseline
(`qt5-build-cadisplaylink/baseline-tst_qwindow.txt`) and pass when nothing else has focus.

## Review round 1 fixes, 2026-09-28, 240 Hz display

### Soak under load (R1-2)

20 consecutive runs of every wall-clock test on the round 1 heads, while another workload (a Metal
shader build, a dozen `applegpu-nt` processes, not ours) kept the machine loaded. Per run: 43
tst_qwindow rows (display link and frame rate), 3 Widgets functions (`pacedUpdates` x2,
`pacedUpdatesSemantics`, `pacedUpdatesAfterRecreate`), 2 Qt Quick functions
(`stepsWithPreferredFrameRate`, `animatorDurationWithPreferredFrameRate`). Raw log:
`/tmp/r1/soak-results.txt`, per-run logs in `/tmp/r1/soak/`.

| Runs | Load averages (1, 5, 15 min) | Result |
|---|---|---|
| 1-19 | from 29.7/82.4/147.6 to 216.7/225.8/247.4 | all passed |
| 20 | 109.1/104.0/147.6 | tst_qwindow passed; Widgets skipped `pacedUpdates` (window got covered); `animatorDurationWithPreferredFrameRate` failed waiting for the animation |

Run 20's failure was the window being covered (the Widgets test skipped for that reason just
before): a covered window isn't rendered, so its Animator never finishes, and the test waited 5 s
before checking exposure. Fixed to skip in that case (qtdeclarative, staged; see below).

Before these fixes, on the same loaded machine: `requestUpdateRate` measured 130.9/s for 240 and
`requestUpdateMultipleWindows` 186.5/s, failing the old 80% bound.

### Other checks

* `tst_qappleframerate`: 151 passed (15 new delivery and preference cases).
* Full `tst_qquickwindow` 127 passed, 1 skipped; full `tst_qquickanimations` 73 passed.
* Reviewer's `/tmp/rvw/latency` (R1-3): driven window latency median 0.008 ms in both orders (was
  33.34 ms when visited before the driving window).
* Stall recovery (R1-1), simulated with a temporary patch ignoring a link's callbacks after 100: the
  manual test stopped at t≈0.9 s, "stopped delivering update requests. Recreating it" at t≈1.9 s,
  240 fps from the next sample. No false positives in 4 s runs with `--rate 1`, `--rate 30`, default.
* iOS simulator (iPhone 18 Pro, iOS 27): `tst_qappleframerate` 151 passed; `tst_qwindow` display
  link and frame-rate tests 39 passed, 5 skipped (60 Hz simulator: 24 and 60 not both exact; no
  timer path; no nested loops on iOS; one screen; swap interval 0).

### The Gerrit series, commit by commit (R1-7)

Separate worktree and build (`qt5-series-build`: Debug developer build, non-framework, tests on
demand, sql/network/dbus/printsupport off).

| Commit | Build | Tests at that commit |
|---|---|---|
| G1 | QtGui, cocoa plugin, tst_qwindow | 5 delivery tests pass **with the old CVDisplayLink plugin** |
| G2 | cocoa plugin, tst_qwindow | 9 delivery tests pass (+ driven window, nested loop) |
| G3 | QtGui | doc only |
| G4 | QtGui, cocoa plugin, tst_qwindow | 11 pass (+ property, timer pacing) |
| G5 | QtGui, cocoa plugin, tst_qwindow, tst_qappleframerate | tst_qappleframerate 151/151; tst_qwindow 43 passed, 1 skipped (two screens) |
| G6 | Widgets, tst_qwidgetrepaintmanager | 18 passed, 1 failed (`scrollWithOverlap`, `qWaitForWindowActive`, focus) |
| G7 | displaylink (standalone, against the series build) | `--rate 30` → 30.0/s |
| D1 | qtdeclarative (`qt5-series-build-qtdeclarative`, configured with the non-framework qtbase, whose tree is G7's) | `stepsWithPreferredFrameRate`, `animatorDurationWithPreferredFrameRate` pass; full tst_qquickanimations 73/73 |
| D2 | tst_qquickwindow | `preferredFrameRateFromQml`, `preferredFrameRateRevision`, `preferredFrameRateOwnProperty` pass. The full suite had 56 activation failures (`qWaitForWindowActive`, `requestActivate`, `isActive`) while other windows had focus; it passed 127/127 on the wip branch when nothing else was in front |

The D2 tree is the qtdeclarative wip branch plus the staged "Skip the Animator duration test when
covered" change. Note: add-on modules built against an uninstalled qtbase write their libraries
into its prefix, so the series and the main qtdeclarative build share `qt5-build-nofw/lib`; their
sources only differ in doc comments and the qquickwindow tests.

The G7 tree is identical to `wip/cadisplaylink` without `wip-cadisplaylink/` (`git diff --cached
wip/cadisplaylink -- . ':(exclude)wip-cadisplaylink'` is empty). Signing of the series commits G2
onwards is pending (AppleConnect); the tested states are recorded as file lists
(`/tmp/r1/series-g*.files`) and intermediate files (`/tmp/r1/g2/`, `/tmp/r1/tst_qwindow.g*.cpp`).

## 2026-09-28, 240 Hz external display (Odyssey G95SC), before round 1

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
* The stall (R1-1) on the ProMotion panel, and a CVDisplayLink A/B of it (panel not connected).
* A display ID change (R1-4): reasoned, not triggered.
* Wayland/xcb/Windows: the timer-path pacing test has only run on cocoa (it's in the allow-list).
* Real-mouse live resize with the event tap removed.
