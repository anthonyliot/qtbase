# Code review of the patch set (2026-09-26)

Multi-agent review: 6 area reviewers (Cocoa display link lifetime, pacing math, iOS, QtGui private
API + Qt Quick driver, tests, upstream readiness), each finding checked by 2 independent
verifiers (one trying to refute it). 29 findings, 27 not refuted. Full report below.

## Status of the findings

| # | Finding | Status |
|---|---|---|
| 1 | Manual test used BSD SPDX under tests/ (CI license check fails) | fixed (license check passes) |
| 2 | Render-thread Animators stepped by the paced GUI interval (run too fast) | fixed in qtdeclarative; new test `animatorDurationWithPreferredFrameRate` |
| 3 | Pacing tie at k.5 frames decided by rounding noise | fixed: one `framesPerDelivery()` rule; 11 new unit test rows fail on the old code |
| 4 | Update request for an already-visited window during delivery lost, link pauses, window freezes | fixed (macOS + iOS); new test `requestUpdateForOtherWindowDuringDelivery` fails 3/3 on both the old CVDisplayLink and the new code before the fix, so it's a pre-existing bug |
| 5 | Test expectations wrong on 59.94/50/144 Hz | fixed (nearest rule, system snap to faster neighbour allowed) |
| 6 | swapInterval-0 check could not pass on iOS; vacuous timer test | fixed (moved into `requestUpdateSwapIntervalZero`, iOS skips the interval part) |
| 7 | Fallback timer never cancelled once the display link works again | fixed (`QCocoaWindow::stopFallbackUpdateTimer()`); no automated test (can't make the link fail on purpose) |
| 8 | Failed link recreation on display ID change never retried | open (follow-up) |
| 9 | `updateRequestInterval` stale after delivery (expose frames use paced interval) | fixed (reset after delivery, comment updated) |
| 10 | `unitedWith()` treated "no preferred" as slowest | fixed; unit test rows |
| 11 | Rate tests compare to nominal refresh, slow | mostly fixed (baseline from the link's reported interval, 500 ms windows, invalid tests without timing) |
| 12 | `static_cast` of custom animation drivers | fixed (`qobject_cast`) |
| 13 | Env var info line printed by default; property/env undocumented as internal | fixed (category defaults to warnings, `_p.h` comment); commit message wording to do at Gerrit prep |
| 14 | Event tap comment still mentions the GCD source | fixed |
| 15 | Preference re-read/re-parsed per tick | open (follow-up, <1% CPU) |
| 16 | WIP references in upstream-bound content; WIP commit is the root | test comment fixed; commit messages and dropping the WIP commits at Gerrit prep |
| 17 | Copyright holder string | **needs your decision** (Apple OSS process) |
| 18 | Screen removed during nested event loop in delivery (pre-existing UAF) | open (follow-up hardening) |

## Full report

# Final review: CADisplayLink / preferred frame-rate patch set

## 1. Confirmed issues (ordered by corrected severity)

### Blocker

**1. The manual test uses the wrong SPDX license, so Coin's license check fails.** qtbase `tests/manual/displaylink/main.cpp:2`
- **What's wrong:** The header says `LicenseRef-Qt-Commercial OR BSD-3-Clause`. `licenseRule.json` maps `tests/` to `LicenseRef-Qt-Commercial OR GPL-3.0-only`. BSD is only allowed under `examples/`, `snippets/` and `tests/manual/qnx/foreignwindows/`.
- **Evidence:** Both verifiers ran `qtqa/tests/prebuild/license/tst_licenses.pl` and got `not ok 9904 ... wrong license SPDX expression`. `CMakeLists.txt` passes (`ok 9903`). The qt5 `coin/platform_configs/default.yaml` turns on `LicenseCheckV2`, which runs `run_license_check.yaml`.
- **Impact:** Every change staged from 6527194bc72 onward fails integration.
- **Fix:** In 6527194bc72, change line 2 to `// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only`. Autosquash rebases cleanly, because f48f930cd3c only touches the file from line 17 onward. Leave `CMakeLists.txt` as BSD-3-Clause.

### Major

**2. Render-thread Animators advance by the paced GUI interval on every free-running render-thread frame, so they run refresh/preferred times too fast.** qtdeclarative `src/quick/scenegraph/qsgthreadedrenderloop.cpp:556` and `:756-761`
- **Where the value comes from:** `sync()` copies `updateRequestInterval` (for example 33.3 ms at a 30 fps preference) into `QSGRenderThread::frameInterval`. `syncAndRender()` applies it to `animatorDriver` on every pass, including repaint-only passes.
- **Why the render thread free-runs:** While Animators run, `QQuickAnimatorController::advance()` calls `m_window->update()` (`qquickanimatorcontroller.cpp:77`, reached from `qquickwindow.cpp:667`). That becomes `requestRepaint()` (`:1500`, `:258-264`), so `run()` never sleeps (`:1000`). The render thread therefore free-runs at the Metal swapchain rate, i.e. the display refresh.
- **Why nothing catches it:** `QSGDefaultAnimationDriver` in VSyncMode adds `m_time += frameInterval` per frame. The deltas are about one vsync, well under `1.25*frameInterval`, so lag detection never trips.
- **Effect:** An OpacityAnimator or XAnimator of 1000 ms finishes in about 500 ms on 60 Hz and about 125 ms on 240 Hz. `QQuickAnimatorProxyJob` (duration -1) ends only when the render-thread job ends, so `finished` fires early too. The default-preference path is unaffected. This is the feature's main use case, and PLAN.md admits the path is untested.
- **Fix:**
  - Stop passing the paced interval to the render-thread driver. Either drop the call at 758 together with the `frameInterval` member and its copy at 556, or pass `1000 / window->screen()->refreshRate()` captured in `sync()`. The second option also fixes the old primary-screen `m_vsync` inaccuracy.
  - Do not apply the interval "only on sync frames". Those frames also arrive one swapchain interval after the previous one.
  - Live resize (`allowsIndependentThreadedRendering()` false) falls back to TimerMode, as it did before this patch. That is acceptable.
  - Document that Animators still render at panel rate, which costs power. A proper fix would pace the present (`presentDrawable:afterMinimumDuration:` or CAMetalDisplayLink), as a follow-up.
  - Add a tst_qquickanimations case: OpacityAnimator or XAnimator, 500 ms, `_q_preferredFrameRateRange=30`, threaded loop, Apple only. Time `setRunning(true)` to `finished` with QElapsedTimer and assert it takes at least 0.8x the duration.

**3. The pacing threshold sits exactly on a vsync whenever refresh/requested is a half-integer, so `shouldDeliverFrame()` is decided by rounding noise and disagrees with `effectiveFrameInterval()`.** qtbase `src/gui/platform/darwin/qappleframerate.cpp:191` and `:204`. This merges the "pacing-math" finding and the "tests / half-integer" finding.
- **The tie:** Delivery happens when `delta >= interval - L/2`. For interval/L = k+0.5 that threshold is exactly k·L, the same as a real vsync gap. `effectiveFrameInterval()` breaks the tie with `ceil(... - 1e-6)` toward k frames. `shouldDeliverFrame()` has no tie-break.
- **Replays of the unit test's own jitter loop:**

  | Case | Delivered | `effectiveFrameInterval` implies |
  |---|---|---|
  | 24@60 | 20/s | 30/s |
  | 48@120 | 40/s | 60/s |
  | 96@240 | 80/s | 120/s |
  | 30@75 | 25/s | 37.5/s |

- **With tick-exact mach timestamps:** 24@60 gives a random mix of 2- and 3-frame gaps (22-28 fps depending on host uptime). One tick of jitter in L is enough to flip `effectiveFrameInterval` itself, because the 1e-6 bias is too small.
- **Where it shows up:**
  - Mixed-window links, e.g. a 24 fps video next to a default-rate UI on 60 Hz.
  - Single windows where CA resolves the tie toward the faster rate, e.g. 40@60.
  - The wrong interval goes into `updateRequestInterval`, and Qt Quick now trusts it. Mixed gaps keep resetting `m_bad`/`m_lag`, so animations stay about 15-20% slow instead of falling back to TimerMode. The "33% slow" claim is overstated: all-3-frame gaps do trip TimerMode after about 7 frames.
- **Existing tests miss it:** `pacing_data` (tst_qappleframerate.cpp:199-217) contains no tie rows.
- **Fix:**
  - Compute the frame count once in a shared static helper: `n = max(1, floor(interval/L + 0.5 - 1e-3))`. This mirrors CA's `roundf(x - 0.001)` and is large relative to timestamp jitter.
  - Deliver when `delta >= (n - 0.5)*L`, or equivalently `qRound(delta/L) >= n`.
  - Return `n*L` from `effectiveFrameInterval()`.
  - When L <= 0, keep the current `delta >= interval - 0.5ms` fallback.
  - This matches every existing row: 100@240→2, 24@120→5, 60@240→4, 120@60→1.
  - Add jittered and jitter-free (large host-time offset) `pacing_data` rows 24@60, 40@60, 48@120, 80@120, 96@240, 160@240, 30@75. For each, assert delivered == `qRound(1/effective)` and that there is a single gap size.
  - Add a tst_qwindow mixed-window variant with 24 fps next to a default-rate window.
  - Fix the "rounds up" wording in README.md:43, CLAUDE-NOTES.md:49 and PLAN.md:116. The actual rule is nearest, with ties going to the faster rate.

**4. An update request made during delivery for a window already visited in the loop is lost to the pause decision, so that window freezes.** qtbase `src/plugins/platforms/cocoa/qcocoascreen.mm:404-459`; same shape in `src/plugins/platforms/ios/qiosscreen.mm:381-421`
- **Mechanism:** The pause decision and the frame-rate union use a local flag (404, 442-446). That flag only covers windows re-checked after their own delivery, taken from an `allWindows()` snapshot (407). `window_list` is prepended, so newer windows come first. If older window B's UpdateRequest handler calls `A->requestUpdate()` on newer window A, which the loop has already skipped at 417:
  - `QCocoaScreen::requestUpdate()` skips the rate update (371), and its un-pause does nothing mid-callback.
  - The unconditional `paused = YES` (452-458) then pauses the link.
  - A keeps `updateRequestPending`, so every later `requestUpdate()` returns early (qwindow.cpp:2919).
  - A stays frozen until some other window on that screen requests an update. Windows created during delivery are missed the same way.
- **Regression status:** The base code had the same overwrite (`m_pendingUpdateRequests = pendingUpdateRequests`). But a CVDisplayLink tick racing the GCD handler could recover it by chance. With main-run-loop delivery and the recursion guard, the freeze is now deterministic. That makes it major on macOS.
- **iOS:** The same stall already existed, so it is minor there. The patch does add a one-frame rate/latency glitch on iOS, because `m_deliveringUpdateRequests` defers rate selection to the incomplete end-of-loop union.
- **Scope:** QWidget windows are mostly unaffected (they post UpdateRequest events). Qt Quick multi-window animation runs off `m_animation_timer`. The affected case is QWindow, QOpenGLWindow, RHI or QQuickWindow setups where one window's frame updates another, newer window.
- **Fix:**
  - Make `updateDisplayLinkFrameRate()` return whether any live window on this screen is pending and `updatesWithDisplayLink()`. It already applies that filter at 495-496.
  - After the loop, call it once and use `paused = !result` in place of both the local union (449-450) and the local flag (452).
  - Run the rescan only on the about-to-pause path, so animating frames don't pay for a second scan.
  - Do not use `hasPendingUpdateRequests()` (462-481) for this. It counts swapInterval-0 timer windows and would keep the link awake indefinitely.
  - Rename the local `hasPendingUpdateRequests`, which shadows the member function.
  - Apply the same change to `QIOSScreen::deliverUpdateRequests` (replace 417-421).
  - Add a tst_QWindow case: create window1, then window2. window1's UpdateRequest handler calls `window2.requestUpdate()` once and does not re-request itself. `QTRY_VERIFY` that window2 receives an UpdateRequest.

**5. The test helpers `achievableRate()` / `expectedStep` model the wrong rounding, so the new tests fail on 59.94, 50, 144, 85 and 119.88 Hz displays (test-only).** qtbase `tests/auto/gui/kernel/qwindow/tst_qwindow.cpp:3348-3354`; qtdeclarative `tests/auto/quick/qquickanimations/tst_qquickanimations.cpp:2143-2145`. This merges the "rounds up" and "non-integer refresh" findings.
- **The mismatch:** The helpers use `floor(refresh/requested + 0.001)`, i.e. "round up to the faster divisor". Qt's pacing rounds to nearest, and it runs for every window, including single windows. CA uses `roundf(x - 0.001)` and then snaps down to its interval table.
- **Failures:**
  - **59.94 Hz:** the 0.001 epsilon predicts 59.94 fps for a 30 fps request, but 29.97 fps is delivered. `preferredFrameRate` (30/list/map/string), RuntimeChange, MixedWindows, `UpdateRequestInterval(30)` (expects 16.7 ms, gets 33.4 ms) and `stepsWithPreferredFrameRate` all fail every time.
  - **50 Hz:** expects 50, gets 25.
  - **144 Hz:** gets 28.8 fps against an expected 36. That lands exactly on the 0.8x lower bound, so it is flaky. The interval tests fail outright (34.7 ms vs 27.8 ms).
  - **200 Hz:** the finding's claim is wrong here. CA snaps 7→6, which happens to match the current helper.
  - Only 240 Hz and the 60 Hz simulator were ever run.
- **Fix:**
  - Stop predicting a single divisor. Check that `window.lastUpdateRequestInterval` is an integer multiple k of 1/refresh (within a few percent) and within one vsync of 1/requested.
  - Then check the measured rate against 1/lastUpdateRequestInterval.
  - If you keep explicit expectations:
    - Use a relative integer snap (within about 1%) so fractional refresh rates like 59.94 are handled.
    - For the mixed-window (Qt-paced) phase, use Qt's rule from fix #3.
    - For single-window (CA-paced) rows, accept either neighbouring divisor.
    - QSKIP near-ties.
  - Share one helper with tst_qquickanimations.
  - Add `pacing_data` rows 30@144, 30@50 and 30@59.94.

**6. The swapInterval-0 half of `preferredFrameRateUpdateRequestInterval` cannot pass on iOS, and `requestUpdateSwapIntervalZero` is vacuous (test-only).** qtbase `tests/auto/gui/kernel/qwindow/tst_qwindow.cpp:3596-3604` and `:3445-3457`
- **Why it fails:** `QIOSWindow::requestUpdate()` (qioswindow.mm:435-438) always drives the screen's CADisplayLink and never looks at swapInterval. `qiosscreen.mm:400` sets a nonzero interval, and the value from the first half of the test persists anyway. So `QCOMPARE(lastUpdateRequestInterval, 0.0)` fails on every row. `REQUIRE_DISPLAY_PACED_UPDATES` admits "ios".
- **Why "27/27" is not evidence:** The iOS binary predates 53f2184ac65 and does not contain this function.
- **The vacuous test:** `requestUpdateSwapIntervalZero` only checks `rate > 10`, which passes on either path. It never proves the timer fallback.
- **Fix:**
  - Move the swapInterval-0 check out of the data-driven test, where it runs four times, into `requestUpdateSwapIntervalZero`.
  - On cocoa, reset `lastUpdateRequestInterval = -1` and then assert `== 0.0` after the rate check.
  - On iOS, QSKIP with the reason "iOS always paces update requests with the display link", or assert a non-zero interval.
  - Do not change QIOSWindow behaviour to satisfy the test.
  - Rebuild the iOS test, rerun the full set of new tests on the simulator, and correct "27/27" in PLAN.md.

### Minor

**7. The timer fallback is never cancelled once the display link works again, so a window gets both timer and link update requests.** qtbase `src/plugins/platforms/cocoa/qcocoawindow.mm:1884-1886`
- **Mechanism:** When `QCocoaScreen::requestUpdate()` fails (screen not online, no NSScreen yet, which is a new path, or link creation failed), the repeating `QPlatformWindow::updateTimer` starts: 5 ms, or 1 ms at 240 Hz because of int truncation. It stops only when nothing is pending after a timer delivery (qplatformwindow.cpp:472-480). An animating window re-requests through the now-working link, so the timer keeps firing.
- **Effects:** Timer deliveries skip `shouldDeliverFrame()`, so the frame-rate cap is ignored. They also reuse the last link-set `updateRequestInterval`, so Qt Quick animations run several times too fast. If the link consumes the request before the timer fires, `Q_ASSERT(hasPendingUpdateRequest())` (qplatformwindow.cpp:839) trips in debug builds.
- **Fix:**
  - Add `void stopFallbackUpdateTimer() { d_ptr->updateTimer.stop(); }` to QCocoaWindow. `d_ptr` is protected; `Q_D` won't compile because `d_func()` is private.
  - Call it when the screen request succeeds in `QCocoaWindow::requestUpdate`, and in `QCocoaScreen::deliverUpdateRequests` just before `deliverUpdateRequest()`. The second call covers link restarts that bypass `QCocoaWindow::requestUpdate`.
  - Optionally, make `QPlatformWindow::windowEvent` stop the timer and return when nothing is pending.

**8. When the display ID changes, a failed link recreation is ignored and never retried, stranding pending windows.** qtbase `src/plugins/platforms/cocoa/qcocoascreen.mm:216-226`. This merges the ":225" and ":222 missing-coverage" findings.
- **Mechanism:**
  - `update()` invalidates the link and calls `requestUpdate()` before the "NSScreen not yet available" check (232-236). It ignores the `false` return when `nativeScreen()` is nil, which is a new dependency.
  - Later same-ID `update()` calls skip the branch.
  - Pending windows keep `updateRequestPending` and have no link and no timer.
  - They recover only through `windowDidChangeScreen` or another window's request.
- **Scope:** Narrow, because `get(uuid)` skips offline screens. It needs a GPU/port remap while the old ID still reports online. This is new with the patch (base never recreated the link) and is listed as unverified in PLAN.md.
- **Fix:**
  - Simply moving the invalidate below the NSScreen check is not enough, because `m_displayId` is already updated.
  - Record `m_displayLinkDisplayId` and keep the old link until the new NSScreen exists.
  - After the NSScreen check (and at the top of `requestUpdate()`), recreate the link if the IDs differ, or if a deferred-restart flag is set and windows are pending.
  - Optionally add a per-window timer fallback when recreation fails. It would depend on fix #7 to avoid double delivery.
  - Add a manual checklist item: GPU switch or display remap while `tests/manual/displaylink` animates, with `qt.qpa.screen.updates` logging on.

**9. `updateRequestInterval` stays set after delivery, so expose-driven frames (live resize) step animations by a stale paced interval.** qtbase `qcocoascreen.mm:430`, `qiosscreen.mm:400`, `src/gui/kernel/qwindow_p.h:157-161`; qtdeclarative `qsgthreadedrenderloop.cpp:1712-1715` and `:556`
- **Mechanism:** The value is only reset on the timer path (qplatformwindow.cpp:799). During live resize, `displayLayer` sends an expose per step, which queues `advanceAnimations` and `sync(inExpose)` reading the stale 33.3 ms instead of `m_vsync`.
- **Effect:** Animations run about 3-5x too fast while resizing, for opt-in windows only. The pre-existing double-advance during live resize is out of scope.
- **Fix:**
  - Reset the value to 0 in the platform loops right after `platformWindow->deliverUpdateRequest()` returns, behind the existing QPointer check.
  - Not in `QPlatformWindow::deliverUpdateRequest`: `QCocoaWindow` can defer and skip the base, and the window can be deleted during delivery.
  - In `polishAndSync()`, capture the interval by value before queueing, and use 0 when `inExpose`. Do the same in `sync(inExpose)`.
  - Update the qwindow_p.h comment to "valid only during UpdateRequest delivery".

**10. `unitedWith()` treats preferred == 0 as the lowest rate, so the documented "min,max" form gets throttled by another window.** qtbase `src/gui/platform/darwin/qappleframerate.cpp:155-158`
- **Example:** (30,120,0) united with (24,24,24) gives (30,120,30). The link runs at 30 Hz, so window A gets 30 fps instead of 120 and B gets 30 instead of 24.
- **Inconsistency:** This contradicts Qt's own `frameInterval()` (line 166, 0 means maximum) and CA, which never picks the slowest rate.
- **Fix:**
  - When exactly one side has preferred 0 and a finite maximum, use that maximum as its effective preferred rate, then take the max and clamp. (30,120,0)+24 then gives (30,120,120), and B is paced at exactly 24.
  - Keep 0 when both sides are 0.
  - Treat an infinite maximum as unbounded.
  - Update the "clamps preferred" row to (100,120,120). Add rows for (30,120,0)+24 and (30,120,0)+60.
  - Picking a common multiple of the rates is a separate power/design follow-up, not a bug fix.

**11. Rate assertions compare against the absolute `QScreen::refreshRate()`, which is flaky on CI and adds about 40 s to tst_qwindow.** qtbase `tests/auto/gui/kernel/qwindow/tst_qwindow.cpp:3366-3372`, used at 3388, 3406-3407, 3499, 3524, 3544, 3556, 3589-3594 and 3636. This merges the two flakiness findings.
- **The problem:** With a default range, CA picks the rate, and `refreshRate()` is the nominal mode rate. PLAN.md:119-121 already records a 120/s measurement against an expected 240. There are about 30 measurements at about 1.25 s each.
- **Corrections to the finding:** The bench scripts do not export `QT_APPLE_PREFERRED_FRAME_RATE_RANGE`. The invalid rows do not use the environment default. iOS CI is simulator-only.
- **Fix:**
  - Take the baseline from a default window's `lastUpdateRequestInterval` (the real link interval).
  - Keep the upper bound tight; loosen or retry the lower bound.
  - QSKIP when the link runs below `refreshRate()`.
  - Drop timing from `preferredFrameRateInvalid` and from the parser-variant rows; tst_qappleframerate already covers those. Assert the warning, that updates keep arriving, and that the interval equals the unthrottled interval.
  - Shorten `kMeasureMs` to 300-500 ms.
  - Optionally `qunsetenv` the variable in `initTestCase`.

**12. `setFrameIntervalForAnimationDriver()` static_casts drivers it may not have created.** qtdeclarative `src/quick/scenegraph/qsgcontext.cpp:428-431` (the cast is at 430)
- **Mechanism:** An out-of-tree adaptation whose `createAnimationDriver()` returns its own `QAnimationDriver` (necessarily not a `QSGAnimationDriver`, which is file-local) previously only had to override `isVSyncDependent()`. It now gets an unchecked 4-byte write on every advance (lines 715/758). This is silent undefined behaviour.
- **Fix:**
  - Use `if (auto *d = qobject_cast<QSGDefaultAnimationDriver *>(driver)) d->setFrameInterval(interval);`. The class has Q_OBJECT and its moc is included.
  - Optionally move `m_frameInterval` into `QSGDefaultAnimationDriver`.
  - Document next to `createAnimationDriver()` that overriding it means overriding all three driver hooks.

**13. The environment variable prints an info line by default, and the env var and property are pitched to apps but undocumented.** qtbase `src/gui/platform/darwin/qappleframerate.cpp:20` and `:229`
- **Logging:** `qt.*` categories only suppress debug, so the `qCInfo` at 229 prints on every run that sets the variable.
- **Fix:**
  - Declare the category as `Q_STATIC_LOGGING_CATEGORY(lcFrameRate, "qt.qpa.framerate", QtWarningMsg)`, the cocoa plugin convention.
  - In the 07923f8f3d0 and 8e35d2b83e2 commit messages and the `_p.h` comment, state that `_q_preferredFrameRateRange` and `QT_APPLE_PREFERRED_FRAME_RATE_RANGE` are internal, unsupported, and to be replaced by public API. Do not add ChangeLog entries for them.
  - Add a `[ChangeLog][macOS]` entry on f7240d14d39 for the real behaviour change: CADisplayLink, main-run-loop delivery, and pausing when idle.

**14. The live-resize event tap comment still refers to the removed GCD source.** qtbase `src/plugins/platforms/cocoa/qcocoascreen.mm:333-336`
- **What's wrong:** Line 335 says "prevent the GCD source from being prioritized". Line 325-326 of the same comment block was updated, so the comment now contradicts itself. The rationale has not been re-validated for CADisplayLink (CLAUDE-NOTES.md:28-30, PLAN.md:127-129), and the f7240d14d39 message asserts "still relevant" without evidence.
- **Fix:**
  - Reword the comment to describe the CADisplayLink run-loop source and say the workaround is kept pending re-validation.
  - Align the commit message.
  - Run a real-mouse live-resize test with a renderer taking 8 ms or more, with and without the tap. If there is no difference, remove the tap in a separate follow-up commit.
  - The FIXME at line 1003 is still accurate: public UpdateRequest timing doesn't exist. Keep it, or reword it.

**15. The frame-rate preference is re-read twice per tick, and QML `property var` arrays and objects are re-parsed every time.** qtbase `src/gui/platform/darwin/qappleframerate.cpp:241-249` and `:75-86`; callers at `qcocoascreen.mm:427/444` and `qiosscreen.mm:397/412`
- **Mechanism:** `property var` returns a fresh QJSValue, which never compares equal, so each read runs a V4 conversion, a string join, and a re-parse.
- **Cost:** About 120 re-parses per second per window at 60 Hz (not 480 as claimed), with a CPU cost well under 1%.
- **Fix:**
  - Reuse the range from the pre-delivery `update()` when the window was not delivered this tick.
  - Build the range in `fromNumbers()` directly from the doubles, keeping an explicit `|d| <= FLT_MAX` check.
  - Longer term: invalidate on `DynamicPropertyChange` or the notify signal instead of polling.

**16. Upstream-bound content references WIP-only files, and the WIP notes commit is the root of the chain.** qtbase `tests/auto/gui/platform/qappleframerate/tst_qappleframerate.cpp:61`; commit message of 04eccb2734a; root commit 1183cae7f6a
- **What's wrong:**
  - The comment `(see wip-cadisplaylink/probes/valid.m)` and the message text "(see the WIP API proposal)" will dangle upstream.
  - 1183cae7f6a is the parent of efae5dc0bdf, so pushing HEAD would upload it. Nine of its committed files fail `tst_licenses.pl`.
- **Fix:**
  - Replace the probe reference with an inline statement of the measured constraints on macOS 27 and the iOS simulator: finite, non-negative, min <= max, preferred 0 or within [min, max]. Don't claim other OS versions.
  - Drop the WIP reference from the 04eccb2734a message, or replace it with a QTBUG link.
  - Commit or stash the staged WIP files, run `git rebase --onto 25d8223e59f 1183cae7f6a f48f930cd3c`, and push that tip rather than HEAD.
  - Task-number footers are optional.

**17. New files authored at Apple carry "Copyright (C) 2026 The Qt Company Ltd." (legal/process).** qtbase `qappleframerate.cpp:1`, `qappleframerate_p.h:1`, `tests/auto/gui/platform/qappleframerate/{CMakeLists.txt,tst_qappleframerate.cpp}:1`, `tests/manual/displaylink/{CMakeLists.txt,main.cpp}:1`
- **What's wrong:** CI doesn't check the holder, and Qt has merged external files with this line before. But the CLA grants a licence, not copyright, and Apple's OSS approval may require its own holder string.
- **Fix:** Confirm the holder string and CLA with Apple's OSS process, then amend line 1 in efae5dc0bdf and 6527194bc72. Keep the SPDX lines as they are.

**18. A screen removed during a nested event loop inside delivery leaves `deliverUpdateRequests()` running on a freed QCocoaScreen (pre-existing).** qtbase `src/plugins/platforms/cocoa/qcocoascreen.mm:397/410/449-458`
- **Mechanism:** `handleScreenRemoved` deletes the screen synchronously. The outer loop then calls `screen()`, reads `m_displayLink`, and writes through `QScopedValueRollback`, all on freed memory.
- **Regression status:** Base code had the same exposure, so this is not a regression. The autorelease and link-release sub-claim is refuted (see section 2).
- **Fix, as a separate hardening change and also for iOS:**
  - Take `QPointer<QScreen> qscreen = screen();` before the loop and compare windows against it.
  - `return` right after each `deliverUpdateRequest()` if it is null.
  - Replace `QScopedValueRollback` with a manual set/clear that is skipped on that path.

## 2. Refuted findings

- **`frameDelivered()` recorded before QCocoaWindow defers (qcocoascreen.mm:429), both copies.** Treated as not a defect. The mechanism is real, but:
  - With a single paced window the link already runs at the window's rate, so the next tick passes anyway.
  - In the mixed-rate case every deferral comes with a `displayLayer` expose that renders the window.
  - The suggested fix could add a redundant frame about 4 ms later.
  - At most, add a comment saying so.
- **visionOS nil display link and tests not skipping there.** Update requests were never delivered on visionOS (pre-existing since d5bf42f75b0). The scan runs about once per window, not per request. Tests aren't built for visionOS, and the existing `requestUpdate` test would fail there too. Only the WIP-only API-PROPOSAL.md:45 wording needs fixing.
- **QWindowPrivate padding and the qtdeclarative dependency pin.** The padding costs 8 bytes per QWindow, a nit: optionally move the double after `transientParentPropertySet`. The pin is the normal Qt cross-module flow, and the commit message already records the dependency.
- **"Can't build in Coin" and "reorder qtbase so the interval comes before pacing".** Coin simply rejects early staging. Reordering doesn't close the qt5-level window. The feature is opt-in, and the driver reaches TimerMode after about 3 frames.
- **Sub-claims refuted inside confirmed findings:**
  - Autorelease in `invalidateDisplayLink()`: releasing the link inside its own callback is safe, and autorelease would drain in the nested pool anyway.
  - "FIXME at 1003 is stale": wrong, public UpdateRequest timing still doesn't exist.
  - "bench/*.sh export the env var": false.
  - "200 Hz fails" (finding 5): wrong, CA snaps 7→6, which matches the current helper.
  - "33% slow" (finding 3): overstated.

## 3. Overall assessment

Not ready for Gerrit yet. The core design is sound and none of the findings dispute it:
- one NSScreen-based CADisplayLink per QCocoaScreen;
- delivery on the main run loop;
- pausing instead of stopping;
- the shared QAppleFrameRateRange helper.

**Required before pushing:**
- The license blocker (#1).
- The four product defects that break the new feature or regress existing behaviour: #2 render-thread Animators, #3 the pacing tie rule, #4 the pause rescan on macOS (iOS in the same change), and #7 the fallback timer.
- The two test defects that would fail CI or developer machines deterministically: #5 and #6.
- Rerunning the full new test set on the iOS simulator.

**Cheap, should land with the series:** #9 (scope the interval to delivery), #12 (qobject_cast), #13 (logging category and wording), #14 (tap comment), #16 (WIP references and dropping the root WIP commit), #17 (copyright confirmation), and the #10 `unitedWith` fix.

**Can be separate follow-ups:** #8 (display-ID recreation plus manual check), #11 (test hardening and runtime), #15 (polling cost), #18 (UAF hardening).

With the required and cheap items fixed, the series is ready for Gerrit review.
