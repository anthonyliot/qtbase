# Plan: move Qt off CVDisplayLink and give apps control over their frame rate

Goal: on macOS use `CADisplayLink` (the supported API) for `QWindow::requestUpdate()`, and let
applications express their frame-rate intent so the system can pick an appropriate refresh rate
on high-refresh (240 Hz) panels instead of every Qt app running at the panel maximum. Keep
existing behavior unless the app opts in. Lay the ground for `CAMetalDisplayLink`.

Constraint: public Qt API can't be changed right now. The "now" solution uses a
QWindow dynamic property and an environment variable. `API-PROPOSAL.md` describes the public
API we'd want to upstream later, and the internals are shaped so the property can be swapped
for real API without touching the platform code again.

## Commits (branch `wip/cadisplaylink` in qtbase)

1. **WIP docs**: this directory. Drop before upstreaming.
2. **gui: Add QAppleFrameRateRange helper** (`src/gui/platform/darwin/qappleframerate_p.h/.cpp`)
   * Pure C++ value type mirroring `CAFrameRateRange` plus the CoreAnimation validation rules, so
     Qt never hands an invalid range to CoreAnimation (which would throw).
   * Parsing from a `QVariant` (number, list, map, string) and from the env var string syntax.
   * `unitedWith()` to aggregate several windows' requests into one link range.
   * Pacing helper: given a range and display-link timestamps, decide whether a window should
     get this frame.
   * `QAppleFrameRatePreference`: a small cache that reads the window property, re-parses only
     when the property changes, and warns once for invalid input.
   * Unit test `tests/auto/gui/platform/qappleframerate` (runs headless).
3. **cocoa: Replace CVDisplayLink with CADisplayLink**
   * Same structure (one link per `QCocoaScreen`), created via
     `-[NSScreen displayLinkWithTarget:selector:]` and added to the main run loop in common modes.
   * Delivery happens directly on the main thread. The GCD source, atomics and cross-thread
     accounting are removed.
   * The link is paused when no window on the screen has a pending update request, and unpaused
     by `requestUpdate()`. This is cheap for CADisplayLink (verified), unlike CVDisplayLink, where
     the old code kept the thread running.
   * Re-entrancy guard (update-request handlers can spin nested event loops).
   * Link is invalidated and recreated when the screen's display ID changes.
   * No public behavior change: same windows get update requests at the same rate.
4. **cocoa: Let windows express a preferred frame-rate range**
   * Per-window preference from `QWindow` property `_q_preferredFrameRateRange`, falling back to
     the `QT_APPLE_PREFERRED_FRAME_RATE_RANGE` environment variable, else the system default.
   * Screen link `preferredFrameRateRange` = union of the preferences of the windows with pending
     update requests (the system default if any of them has no preference).
   * Windows asking for less than the link rate are paced with `targetTimestamp`, so a 30 fps
     window next to a 240 fps window still gets 30 fps.
5. **ios: Honor the preferred frame-rate range** with the same helper, on the `UIScreen` link.
6. **tests: Add update-request regression and frame-rate tests** to `tst_qwindow`:
   * delivery rate roughly matches `QScreen::refreshRate()` (Apple platforms)
   * delivered on the main thread
   * delivered to several windows on the same screen
   * hidden-then-shown window keeps its request (existing) and a request on a created-but-hidden
     window is still delivered (semantics we deliberately keep)
   * `swapInterval == 0` still uses the timer path
   * preferred rate 30 → ~30 Hz, mixed windows 30 + default, runtime change, invalid values are
     ignored without crashing, env var default
7. **manual test** `tests/manual/displaylink`: window with FPS readout and presets
   (default/24/30/60/120/240), several windows, to eyeball pacing and check with Instruments.
8. **Docs**: update the CVDisplayLink mention in `qrhi.cpp`.

## Out of scope for this branch (tracked)

* CAMetalDisplayLink integration in QRhi (design in `API-PROPOSAL.md`).
* qtmultimedia `AVFDisplayLink` cleanup (drop CVDisplayLink fallback, correct screen, video
  frame-rate range). Small, separate repo/branch.
* Per-view (`NSView`) display links (semantic change for hidden windows).
* Timing info on `QEvent::UpdateRequest`.

## Status (2026-09-25)

Branch `wip/cadisplaylink`, on top of qtbase `25d8223e59f`:

| # | Commit | Status |
|---|---|---|
| 1 | WIP: Add CADisplayLink audit, plan and API proposal | this directory |
| 2 | Add QAppleFrameRateRange helper for display link frame-rate intent | done, unit test 73/73 on macOS and iOS simulator |
| 3 | cocoa: Replace CVDisplayLink with CADisplayLink for update requests | done |
| 4 | cocoa: Let windows express a preferred frame-rate range | done |
| 5 | Doc: Refer to CADisplayLink instead of CVDisplayLink | done |
| 6 | ios: Honor the preferred frame-rate range of windows | done, compiled and tested on iOS 27 simulator |
| 7 | tst_QWindow: Add tests for update request pacing and frame rates | done |
| 8 | Add manual test for display link pacing and frame-rate preferences | done |
| 9 | Track the expected interval between paced update requests | done (private `QWindowPrivate::updateRequestInterval`) |
| 10 | cocoa, ios: Report the update request interval to the window | done |

qtdeclarative, branch `wip/cadisplaylink` (fork `anthonyliot/qtdeclarative`):

| # | Commit | Status |
|---|---|---|
| 1 | Advance vsync based animations by the window's frame interval | done |
| 2 | tst_qquickanimations: Test animation steps with a preferred frame rate | done |

Qt Quick findings:

* The **threaded** render loop (macOS default) advances animations with a vsync based driver
  that added a *fixed* 1/refresh (4.17 ms at 240 Hz) per frame. With a 30 fps window, that
  first made animations 8x too slow, then the driver's lag detection logged
  "animation driver switched to timer mode", and animations stepped by uneven wall-clock
  time from then on. With the fix, the driver steps by the frame interval the platform
  reports, stays in vsync mode, and each 30 fps frame advances exactly 33.3 ms (verified by the
  new test, which fails without the fix).
* The render-thread driver (Animator types) gets the same interval, copied during sync. That
  isn't covered by a test yet.
* The **basic** render loop has no custom driver (QtCore's 16 ms timer), so it's unaffected.
* `QPropertyAnimation` & co. outside Qt Quick use QtCore's 16 ms `QUnifiedTimer`, independent of
  the display link and of the preference.
* With several exposed windows, the threaded loop ticks animations from a timer at the vsync
  interval (4 ms at 240 Hz) regardless of preferences. Correct speed, but more ticks than needed.
  Follow-up: use the fastest window's interval for that timer.

Results:

* macOS 27.2, 240 Hz display: full `tst_qwindow` 90 pass / 3 fail / 7 skip. The 3 failures are
  pre-existing focus/activation failures from the baseline. New tests 27/27.
* The new tests on the **original CVDisplayLink code** (cocoa plugin from `25d8223e59f`): all 11
  pacing/regression tests pass, and all 16 frame-rate tests fail (always ~240/s). So the
  regression tests describe existing behavior, and the frame-rate tests describe the new feature.
* iOS 27 simulator (iPhone 18 Pro, 60 Hz): new tests 27/27, unit test 73/73. This run found that
  CA rounds 24 fps on 60 Hz up to 30 fps, and the tests now expect the achievable rate.
* Measured on 240 Hz: default 240.0/s, preference 30 → 30.0/s, 24 → 23.9/s, 60 → 59.9/s,
  env var `QT_APPLE_PREFERRED_FRAME_RATE_RANGE=30` → 30.0/s in the manual test.
* One run of `preferredFrameRateInvalid(min 0)` measured 120/s instead of 240/s while the iOS
  simulator was booted. The system lowered the panel rate. The default-rate expectations depend on
  what else is on screen, so treat those as potentially flaky on shared CI machines.

Hands-on checks (2026-09-25, 240 Hz Odyssey G95SC, A/B by swapping `libqcocoa.dylib` in the
build and verifying the loaded binary's UUID; `QT_QPA_PLATFORM_PLUGIN_PATH` does not override the
build's own plugin directory, so an earlier A/B round that relied on it was discarded):

* Live resize (synthetic drags, 3 trials per variant, light and 8 ms/frame rendering): no difference
  between old, new, and new without the event-tap workaround. The synthetic harness sometimes
  misses the resize handle in every variant. A manual check with a real mouse is still worth doing.
* Display reconfiguration 240 → 120 → 60 → 240 Hz while animating: old and new both follow
  the refresh rate, with no frame gaps while exposed (2 trials each).
* Sleep/wake: skipped, screen lock is set to "immediate".
* Stall soak, 80 runs per plugin: old 15 and new 13 runs stopped animating, **all** of them after
  macOS reported the window occluded (Qt stops painting non-exposed windows, and
  `QPaintDeviceWindow::update()` doesn't request updates while not exposed). No stalls while exposed
  in either plugin. One earlier new-plugin run stalled while reported exposed and wasn't reproduced
  again: still unexplained.

Benefit, manual test window 640x360 (`proc_pid_rusage`, 8 s windows, mean of 3 trials):

| Scenario | Plugin | fps | CPU % | wakeups/s | energy mW |
|---|---|---|---|---|---|
| animating, default | old | 240.0 | 35.3 | 435 | 17.1 |
| animating, default | new | 239.9 | 35.0 | 462 | 11.7 |
| animating, env 60 | old (ignored) | 240.0 | 35.4 | 430 | 17.4 |
| animating, env 60 | new | 60.0 | 12.2 | 68 | 4.2 |
| animating, env 30 | old (ignored) | 240.0 | 31.4 | 427 | 18.3 |
| animating, env 30 | new | 30.0 | 6.9 | 35 | 2.8 |
| idle after animating | old | 0 | 0.4 | 245 | 1.9 |
| idle after animating | new | 0 | 0.1 | 5 | 0.7 |
| 3 ms/frame, default | old | 240.0 | 90.2 | 241 | 12.9 |
| 3 ms/frame, default | new | 239.0 | 89.5 | 317 | 13.4 |
| 3 ms/frame, env 60 | old (ignored) | 240.0 | 89.4 | 241 | 10.6 |
| 3 ms/frame, env 60 | new | 59.5 | 26.4 | 103 | 4.4 |

The idle row is the benefit of the port by itself: the CVDisplayLink thread kept waking 240 times
a second for as long as a window was exposed, even with nothing animating. The capped rows are the
benefit of the frame-rate preference. The panel's own refresh rate doesn't change on this display
(fixed 240/120/60 Hz modes, no adaptive sync), so all the savings are app-side work.

Real app: Qt Quick Effect Maker (qtquickeffectmaker, Debug build against `../qt5-build-nofw`),
Wiggly example project, one window, plugin swapped per run (UUID verified), 10 s samples.
Script: `bench/qqem-ab.sh`. Runs where the window wasn't frontmost/visible were skipped (5), and one
run that stopped rendering during sampling (0 fps, 0% CPU) was discarded.

| Scenario | Plugin | runs | fps | CPU % | wakeups/s |
|---|---|---|---|---|---|
| idle (preview paused) | old | 3 | 0 | 0.3 | 242 |
| idle (preview paused) | new | 2 | 0 | 0.05 | 1 |
| playing, default | old | 2 | 94.6 / 112.3 | 42 / 26 | 374 / 377 |
| playing, default | new | 2 | 85.6 / 107.4 | 39 / 26 | 266 / 167 |
| playing, env 60 | old (ignored) | 1 | 91.6 | 41.6 | 369 |
| playing, env 60 | new | 2 | 40.4 / 56.2 | 22 / 16 | 189 |
| playing, env 30 | new | 3 | 27.9 | 8.4 | 95 |

The Debug build renders this effect at ~100 fps at most, so the default rate is app-bound, not
display-bound. With a 60 fps cap, frames that take longer than 16.7 ms wait for the next 60 Hz slot,
which gives 40-56 fps. That's what a real 60 Hz display does too; a Release build should hold 60.
The billed-energy figures were too noisy at 1 s granularity to report for this app.

Not verified yet (needs hands-on or more builds):

* Live window resize with the kept event-tap workaround, moving windows between displays,
  display sleep/wake, and display reconfiguration (display ID change path).
* Qt Quick (qtdeclarative isn't built here): threaded and basic render loops with a preference.
* Instruments confirmation that the panel actually drops its refresh rate when all animating
  windows ask for less.
* A real ProMotion iPhone/iPad (the simulator is 60 Hz).

Next steps:

1. Hands-on checks above, using `tests/manual/displaylink`.
2. qtmultimedia `AVFDisplayLink`: drop the dead CVDisplayLink fallback, use the video sink's screen,
   set the range from the video frame rate (separate branch in qtmultimedia).
3. Prototype CAMetalDisplayLink behind an opt-in (API-PROPOSAL.md section 4).
4. Take API-PROPOSAL.md section 1 to the Qt Project (QWindow::setPreferredFrameRateRange).

## Verification

iOS simulator build (after the host build exists):

```sh
cmake -S qt5/qtbase -B qt5-build-cadisplaylink-ios -G "Unix Makefiles" -DCMAKE_SYSTEM_NAME=iOS \
      -DCMAKE_OSX_SYSROOT=iphonesimulator -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DQT_HOST_PATH=$PWD/qt5-build-cadisplaylink -DFEATURE_developer_build=ON \
      -DQT_BUILD_TESTS=ON -DQT_BUILD_TESTS_BY_DEFAULT=OFF -DQT_BUILD_EXAMPLES=OFF -DFEATURE_sql=OFF
cmake --build qt5-build-cadisplaylink-ios --parallel --target tst_qwindow tst_qappleframerate
xcrun simctl boot "iPhone 18 Pro"
xcrun simctl install booted qt5-build-cadisplaylink-ios/tests/auto/gui/kernel/qwindow/tst_qwindow.app
xcrun simctl launch --console-pty booted com.yourcompany.<id>.tst_qwindow requestUpdateRate preferredFrameRate
```

(The host build needs `cmake --build . --target host_tools` first.)

* Baseline before any change: `tst_qwindow` = 64 passed, 6 failed, 7 skipped. All 6 failures are
  activation/modality tests that fail when run from a terminal that keeps focus
  (`modalDialogClosingOneOfTwoModal`, `modalWithChildWindow`, `modalWindowModality`,
  `activateDeactivateEvent`, `enterLeaveOnWindowShowHide(dialog|popup)`). They're unrelated.
* After each commit: build `QCocoaIntegrationPlugin`, run `tst_qwindow` and the new unit test,
  and compare against the baseline.
* Manual: `tests/manual/displaylink` on the 240 Hz panel; live resize; moving windows between
  displays; minimize/restore.
