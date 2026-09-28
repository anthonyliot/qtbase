# Round 1 review: CADisplayLink and QWindow::preferredFrameRate

Reviewer: independent, round 1. Scope: every non-WIP commit on `wip/cadisplaylink` in qtbase
(base `25d8223e59f`, head `f171c157cc4` + WIP `9f7d196a2bb`) and qtdeclarative (base `ec2f2fdea8`,
head `d57406c0b8`), the net diffs, and the PR documents in `pr/`, checked against the original
request. `file:line` references are at the branch heads.

## Summary

The core of the PR is sound. The CVDisplayLink to CADisplayLink switch is correct on the things
that usually go wrong. Everything runs on the main thread (asserted). The manual reference counting
is right: the link is retained, the target is autoreleased and retained by the link, and the link is
invalidated before the screen goes away. Every range is validated before it reaches CoreAnimation.
Pausing when idle is safe on the paths I traced. The frame-rate model (whole divisors of the refresh
rate, "slowest not below", gcd union) matches the author's measurements and my probes. The public
API is small and conventional, and the Qt Quick and Widgets integration is careful. The builds and
the targeted tests pass here (see "What I verified").

What stops me from approving:

* **An unexplained stall** (update requests stop while the window stays exposed) was seen at least
  three times on the new code. It is recorded only in the WIP notes (VIDEO.md, DESIGN.md,
  PLAN.md). The PR README and TESTING.md don't mention it, and it hasn't been root-caused (R1-1).
* **The rate-measuring autotests** (about 30 wall-clock measurements in tst_qwindow, plus the
  Widgets and Qt Quick ones) have never run on Coin. By the author's own records they already fail
  intermittently on an idle developer machine (R1-2).

The minor findings are real but small. Two are worth fixing before Gerrit: a latency and pacing
leak between windows that contradicts the public docs (R1-3), and a new path that strands update
requests on a display ID change (R1-4). Also, the squash plan in the README can't be applied as
written (R1-7).

## What I verified (evidence for the "OK" parts)

* Built `QCocoaIntegrationPlugin tst_qwindow tst_qappleframerate tst_qwidgetrepaintmanager` in
  `qt5-build-cadisplaylink`, and `tst_qquickanimations tst_qquickwindow` in the nofw builds: all up
  to date and linking.
* `tst_qappleframerate`: 136 passed.
* `tst_qwindow`, all 22 new functions (41 rows): 41 passed and 1 skipped
  (`preferredFrameRatePerScreen`, one screen). Took 33 s. 240 Hz Odyssey G95SC, the only display
  connected.
* `tst_qwidgetrepaintmanager pacedUpdates pacedUpdatesSemantics pacedUpdatesAfterRecreate`: 6 passed,
  with the warnings discussed in R1-8.
* `tst_qquickanimations stepsWithPreferredFrameRate animatorDurationWithPreferredFrameRate` and
  `tst_qquickwindow preferredFrameRate*`: all pass.
* CADisplayLink timestamps (`/tmp/rvw/resume.m`). `targetTimestamp - timestamp` equals the link's
  current interval on the first callback after creation, after a 1 s pause, and after range
  changes. So neither the watchdog interval nor the interval reported to Qt Quick blows up after
  idle. After switching to 30 fps, the first callback came 24 ms later, aligned to a global 30 Hz
  phase.
* Mapping edge cases (`/tmp/rvw/edge.cpp`, linked against the branch's QtGui):
  `forPreferredFrameRate()` for fps from 1e-9 to 1e9 on 240, 120, 60, 59.94, 144, 165, 100, 75, 50
  and 47.952 Hz. All results are valid ranges, except when `displayRate` is infinite (unreachable,
  and refused by `setDisplayLinkFrameRate()`). `unitedWith()` gcd cases behave as documented.
  Notable outputs that are correct by the rule but surprising: 60 fps on 165 Hz gives the system
  default (165), and 30 fps on 100 Hz gives 50.
* The per-frame watchdog `QTimer::start()`/`stop()` costs about 3.5 µs per frame on the Cocoa
  dispatcher (`/tmp/rvw/timercost.cpp`, debug Qt). That's negligible, so it isn't a finding.
* License headers on the new sources are correct. No non-WIP commit touches `wip-cadisplaylink/`.
* I tried to reproduce the stall of R1-1: 20 launches of `tests/manual/displaylink` with
  `QT_APPLE_PREFERRED_FRAME_RATE_RANGE=240` and `=1,240`, `--log --on-top`, 2.5 s each. No
  stall on the 240 Hz display (see R1-1).

## Findings

| ID | Severity | Title | Commit(s) |
|---|---|---|---|
| R1-1 | major | Unexplained update-request stall on the new code, undisclosed and not root-caused | 03, 04 (cocoa) |
| R1-2 | major | Wall-clock rate autotests are likely flaky on Coin and have never run there | 07, 10, 16, 19, 24, 25, 32; qtdecl 02, 05, 06 |
| R1-3 | minor | A request made during another window's delivery is left out of the link rate: up to one paced interval of latency | 04, 06, 16 |
| R1-4 | minor | Display ID change can strand pending update requests (new path) | 03 |
| R1-5 | minor | Every Widgets update on macOS now parses an ICC profile and looks up a dynamic property | 23, 24 |
| R1-6 | minor | Public docs overpromise on Qt Quick animation speed, power, and default rate | 22, 30; qtdecl 05 |
| R1-7 | minor | Squash plan can't be applied as written; WIP reference in a commit message | all; 09 |
| R1-8 | minor | `pacedUpdatesAfterRecreate` doesn't test what it claims | 24 |
| R1-9 | minor | visionOS: `pacesUpdateRequests()` is true, but update requests are never delivered there | 23 |
| R1-10 | minor | CVDisplayLink still documented in qtdeclarative, and still used by qtmultimedia on macOS 14 | request #1 |
| R1-11 | nit | Pacing state is recorded before a delivery that QCocoaWindow may defer | 04 |
| R1-12 | nit | `updateRequestInterval` isn't reset if the platform window dies during delivery | 18 |
| R1-13 | nit | `QT_WIDGETS_PACED_UPDATES` is an untested, undocumented env var in production code | 24 |

---

### R1-1 (major) Unexplained update-request stall on the new code, undisclosed and not root-caused

* **Commits:** 03 `f7240d14d39`, 04 `07923f8f3d0` (cocoa display link path).
* **Where:** `src/plugins/platforms/cocoa/qcocoascreen.mm:285-393` (`requestUpdate`) and
  `:404-505` (`deliverUpdateRequests`).
* **What:** The author's own notes record update requests stopping while the window stays exposed
  and `lostupdates=0`, which rules out the known QPaintDeviceWindow occlusion case:
  * `wip-cadisplaylink/DESIGN.md:46`: "The 120 request stalled … 15 frames, then 1, then 0 for 11
    seconds while the window stayed exposed … The cause is unknown."
  * `wip-cadisplaylink/VIDEO.md` ("Other findings"): seen again with `120` and `1,120` right after
    startup. "Still not root-caused."
  * `wip-cadisplaylink/PLAN.md:136`: "One earlier new-plugin run stalled while reported exposed …
    still unexplained." The configuration isn't recorded.

  None of this is in `pr/README.md` "Known limitations" or in `pr/TESTING.md`. That's the
  information a Gerrit reviewer needs most.
* **Failure scenario:** 120 Hz ProMotion. An application with `QT_APPLE_PREFERRED_FRAME_RATE_RANGE=120`
  (or `1,120`) starts animating, or so it seems from the notes. After a few frames the window's
  request stays pending and no further UpdateRequest arrives: the window freezes while exposed.
  The design's mitigation for the public API is to never send (M,M,M) and map to the default
  instead (DESIGN.md:46, 313). That is a hypothesis, not a root cause:
  * `1,120` is not (M,M,M).
  * The PLAN.md occurrence may have had no preference at all.
  * The private property and the env var can still send both ranges.
* **Evidence:** the three notes above. My attempt, 20 launches on 240 Hz with `240` and `1,240`
  (`/tmp/rvw/stall/*.log`), didn't reproduce it. That rules out nothing on ProMotion.
* **Leads, unverified:**
  * An NSScreen-created link could stop firing when AppKit replaces its NSScreen objects shortly
    after launch (screen parameter change). The link isn't recreated on a same-ID `update()`.
  * An explicit (M,M,M) or (1,M,0) range on a ProMotion panel could hit a CoreAnimation edge
    case.
  * In both cases `requestUpdate()` keeps returning true while nothing fires, so nothing recovers.
* **Proposed fix:**
  1. Root-cause it on the ProMotion machine. The manual test's `--trace` helps. Also log in
     `deliverUpdateRequests` the last callback time, `paused`, and the link's
     `preferredFrameRateRange`, dumped by the manual test at exit.
  2. Run the same soak on the CVDisplayLink baseline with the same configurations, to show whether
     it's pre-existing.
  3. Until it's understood, sanitize the private ranges like the public ones (max ≥ refresh rate
     with no lower preferred rate → default). Consider a safety net: if a screen has pending
     display-link requests and no callback for, say, 10 intervals, log it and recreate the link,
     or fall back to the timer.
  4. Disclose it in README "Known limitations" and in TESTING.md.
* **Resolved when:** there is a root cause with a fix (and a test if feasible). Or: a baseline A/B
  shows it's pre-existing, it's disclosed, and a safety net is in place. If it reproduces with
  default settings or through the public API, this becomes a blocker.

### R1-2 (major) Wall-clock rate autotests are likely flaky on Coin and have never run there

* **Commits:** qtbase 07, 10, 16, 19, 24, 25, 32; qtdeclarative 02, 05, 06.
* **Where:**
  * `tests/auto/gui/kernel/qwindow/tst_qwindow.cpp:3290-3420` (helpers, `QCOMPARE_RATE*` at
    `:3418-3428`) and the tests that use them.
  * `tests/auto/widgets/kernel/qwidgetrepaintmanager/tst_qwidgetrepaintmanager.cpp:1150-1230`.
  * qtdeclarative `tst_qquickanimations.cpp` (`stepsWithPreferredFrameRate`,
    `animatorDurationWithPreferredFrameRate`).
* **What:** About 30 test rows measure delivered frame rates over 200-500 ms windows. They require
  at least 80% of the expected rate (tst_qwindow and the Widgets test), or at most 2 off-cadence
  steps (qtdeclarative), and they need an exposed, uncovered window on a real display.
  * They have only run on the author's idle machine. `pr/TESTING.md` already records intermittent
    failures there: `pacedUpdates(QRhiWidget)` "once", `animatorDurationWithPreferredFrameRate`
    3 in 18 before a settle delay was added, and failures whenever the user uses the machine.
  * Coin's macOS VMs have virtual displays, loaded hosts, and possibly no real vsync. Timing tests
    like these typically end up blacklisted.
  * The bounds also can't tell adjacent exact rates apart where only the rate is checked. The
    ratio of 24 to 30, 48 to 60, and 96 to 120 is exactly 0.8. So, for example,
    `tst_QWidgetRepaintManager::pacedUpdates` (`:1204`, `pacedRate > 30 * 0.8`) accepts a
    regression that delivers 24 fps instead of 30.
* **Failure scenario:** A Coin macOS VM under load delivers 45 of 60 expected frames in a 500 ms
  window. `requestUpdateRate` fails, and so do the `preferredFrameRate*` rows and `pacedUpdates`.
  They get blacklisted, and the regression protection the request asks for (#4) is gone.
* **Evidence:** the TESTING.md entries above, and the tolerance macro at `tst_qwindow.cpp:3423`.
  The 41 rows ran 33 s here on an idle machine.
* **Proposed fix:**
  * Test the delivery decision deterministically: factor the per-screen fold (union, pace,
    interval, pause decision) into the shared helper the author already plans (REVIEW-API.md
    "Follow-ups"). Unit test it with synthetic callbacks (timestamps, windows with preferences,
    re-requests during delivery), like `tst_qappleframerate`.
  * Keep a few end-to-end smoke tests with relative bounds (paced < 0.6 × unpaced; delivered
    interval equal to the link-reported n/refresh, as `preferredFrameRateApi` already does) and a
    retry.
  * Move the strict rate tables to `tests/manual` or a benchmark, or gate them behind an env var.
  * State which tests are expected to run on Coin, and why they'll be stable there.
* **Resolved when:** the pacing logic has deterministic unit coverage, and the remaining wall-clock
  tests either pass repeatedly under load (for example 20 consecutive runs with a background load
  on all cores, results in TESTING.md) or are clearly opt-in.

### R1-3 (minor) A request made during another window's delivery is left out of the link rate

* **Commits:** 04 `07923f8f3d0` (union at the end of the pass), 06 (iOS), 16 `7862556b859` (re-scan
  only when nothing is pending).
* **Where:** `src/plugins/platforms/cocoa/qcocoascreen.mm:476-494`;
  `src/plugins/platforms/ios/qiosscreen.mm:414-434`.
* **What:** The link's range is the union of windows that are pending *when the loop visits them*.
  A window visited earlier in the pass, which then gets a request during a later window's delivery,
  isn't in the union. The partial union is kept whenever any window is pending, so the re-scan
  added in 16 doesn't run.
* **Failure scenario:** Window A has `preferredFrameRate = 30` and animates. From its UpdateRequest
  it calls `B->requestUpdate()` (a controls or overlay window driven by the video frame). B has no
  preference and is newer, so it comes first in `allWindows()`. The link stays at 30 and B's
  request waits for the next 30 Hz callback. This contradicts the doc: "one window's preference
  doesn't slow down another window" (`qwindow.cpp:1309-1310`). How much it costs depends on
  window order.
* **Evidence:** `/tmp/rvw/latency.cpp` (branch build, 240 Hz):
  ```
  order B visited before A  A frames/s 29.3  B latency ms: n 17 median 33.34 max 33.41
  order B visited after A   A frames/s 31.3  B latency ms: n 18 median 0.08  max 0.14
  ```
* **Proposed fix:** At the end of a pass, compute the range from all pending windows. The simplest
  way is to always call `updateDisplayLinkFrameRate()`. It's one more loop over the windows per
  frame. Or set a flag in `requestUpdate()`/`setUpdatesPaused()` when a request arrives during
  delivery, and re-scan only then. Optionally deliver to such windows in the same pass if they're
  due. Add a test: a variant of `requestUpdateForOtherWindowDuringDelivery` where the driving
  window has a 30 fps preference, checking that the other window's latency is below 2
  unthrottled frames in both creation orders.
* **Resolved when:** the fix is in and the new test passes in both orders.

### R1-4 (minor) Display ID change can strand pending update requests (new path)

* **Commit:** 03 `f7240d14d39`.
* **Where:** `src/plugins/platforms/cocoa/qcocoascreen.mm:217-237` together with `:298-308`.
* **What:**
  * `update()` sets the new display ID, invalidates the link, and calls `requestUpdate()`. That
    call returns false if `nativeScreen()` is nil ("No NSScreen …"), and `update()` ignores the
    result.
  * The same function then handles exactly that state three lines later: "Corresponding NSScreen
    not yet available. Deferring update".
  * Later same-ID `update()` calls don't retry.
  * The pending windows keep `updateRequestPending`, with no link and no fallback timer: 17 stopped
    the timer when the link took over. `QWindow::requestUpdate()` returns early while a request is
    pending, so the application can't unstick them either.
  * The base code never recreated the link, so this path is new. It's REVIEW.md finding #8,
    "open (follow-up)", but it isn't in the PR README's known limitations.
* **Failure scenario:** A GPU switch on a dual-GPU Intel MacBook Pro, or a port remap, while a
  Qt Quick window animates. The display gets a new ID for the same UUID. The
  CGDisplayReconfiguration callback runs before AppKit has updated `NSScreen.screens`. The window
  freezes until something else on that screen makes a fresh request, or AppKit happens to post
  `windowDidChangeScreen`.
* **Evidence:** code reading of the lines above. I couldn't trigger a display ID change on this
  machine.
* **Proposed fix:** When `requestUpdate()` fails in `update()`, move the pending display-link
  windows to `QPlatformWindow::requestUpdate()`, like `handleNestedEventLoopInDelivery()` does. Or
  keep a "restart pending" flag and retry after the NSScreen check, in `update()` and in
  `requestUpdate()`. Either way, list the case in the README if it isn't tested.
* **Resolved when:** there's a code fix and a manual check (or a reasoned argument) that the
  window keeps updating across a display ID change.

### R1-5 (minor) Every Widgets update on macOS now parses an ICC profile and looks up a dynamic property

* **Commits:** 23 `cbace1505b6` (`QCocoaWindow::pacesUpdateRequests`), 24 `1060540e5eb` (caller).
* **Where:**
  * `src/widgets/kernel/qwidgetrepaintmanager.cpp:343-357` calls
    `QCocoaWindow::pacesUpdateRequests()` (`qcocoawindow.mm:1906-1913`).
  * That checks `updatesWithDisplayLink()` *first*, which calls `format()`.
  * `format()` (`qcocoawindow.mm:281-293`) runs `QColorSpace::fromIccProfile()` on the view's color
    space. That falls back to the window's color space (`qnsview_drawing.mm:72-75`), so it's
    practically always set.
* **What:** For every Widgets application on macOS, *including those that don't use the feature*,
  each `sendUpdateRequest(tlw, UpdateLater)` (about once per frame with updates) now costs an ICC
  parse plus a `QObject::property()` lookup. `updateDisplayLinkFrameRate()` does the same per
  pending window on every `requestUpdate()` outside delivery.
* **Evidence:** `/tmp/rvw/icc.mm` (branch QtGui, debug build): 10.2 µs per ICC parse of this
  display's 3376-byte profile. That's small in absolute terms (about 0.25% CPU at 240 updates/s),
  but it's a new per-frame cost for everyone, and the checklist asks for none.
* **Proposed fix:** Check the preference first (`preferredFrameRate() > 0 || property`) and
  `updatesWithDisplayLink()` last. Make `updatesWithDisplayLink()` use
  `window()->requestedFormat().swapInterval()`, since the color space is irrelevant there. That
  also removes the parse from the existing per-frame calls in `deliverUpdateRequests()`.
* **Resolved when:** there's no `format()` or ICC work on the non-paced Widgets path.

### R1-6 (minor) Public docs overpromise on Qt Quick animation speed, power, and default rate

* **Commits:** 22 `71f67301a9b` and 30 `13038efe719` (`src/gui/kernel/qwindow.cpp:1306-1315`);
  qtdeclarative 05 `14a08b8318` (`src/quick/items/qquickwindow.cpp:3831-3862`).
* **What:**
  * "Qt Quick advances animations by the actual interval between frames, so they run at the same
    speed at any rate" (`qwindow.cpp:1310-1312`) isn't true for render-thread Animators on
    ProMotion. They run slow for about 100 ms each time they start, a limitation the author
    documents in README and REVIEW-API.md. The QML doc only says the scene "may still be rendered
    at the display's refresh rate", not that Animators may run slow.
  * The power motivation ("to limit an animated user interface to 60 or 30 frames per second to
    save power") doesn't hold for two or more exposed Qt Quick windows. The threaded render loop
    then drives animations from a timer at the display's vsync interval
    (`qsgthreadedrenderloop.cpp:1145-1148`: a 4 ms timer at 240 Hz), whatever the preferences.
    This is only in VIDEO.md's guidance.
  * "The default value, 0, … usually the refresh rate of the display" (`:1315`) doesn't match the
    timer platforms the same doc lists: about 5 ms, so about 200 per second, on a 60 Hz X11
    display.
  * "one window's preference doesn't slow down another window": see R1-3.
* **Proposed fix:** Say that Animators can run slow briefly when the panel follows a lower
  preferred rate on variable refresh displays, that several visible Qt Quick windows still tick
  animations at the display rate, and that the default rate is platform dependent.
* **Resolved when:** the wording is corrected in both the QWindow and QML docs.

### R1-7 (minor) Squash plan can't be applied as written; WIP reference in a commit message

* **Commits:** all; 09 `04eccb2734a`.
* **What:**
  * I replayed the README "Upstreaming" order with `git cherry-pick`, in a scratch clone
    (`git clone --shared` to `/tmp`, since removed; the real repositories weren't touched).
  * These commits conflict on their own, because they were written against later code:
    * 15 `a901ccb10aa`: needs 09's `effectiveFrameInterval`.
    * 17 `925147b8de0`: needs 04 and 10.
    * 16 `7862556b859`: placed before 04, but modifies `updateDisplayLinkFrameRate()` from 04 and
      the tst_qwindow slot list from 07.
    * 10 `53f2184ac65`: its test needs 07's `AnimatingWindow`.
    * 19 `9e05b1ccbba`: modifies 10's and 16's tests.
  * 23, 29 and 30 also conflict after those.
  * 30's `qwindow.cpp` doc belongs in 22 and its `tst_qwindow` hunk in 25, not in 23.
  * 26 must come after 22, but the plan puts 08 (which 26 squashes into) before 22.
  * The Gerrit series therefore doesn't exist yet. The per-commit review and "each commit builds"
    can't be checked on what will actually be submitted.
  * Commit 09's message says "(see the WIP API proposal)".
* **Proposed fix:** Produce the actual Gerrit series on a separate branch with interactive rebase
  and fixups. Build each commit (at least QtGui, the cocoa and ios plugins, and the touched tests)
  and run the touched tests per commit. Update the README commit map with the new hashes, and drop
  WIP wording from the messages. I'll review that series in round 2.
* **Resolved when:** the series exists, builds commit by commit (log in TESTING.md), and the README
  maps to it.

### R1-8 (minor) `pacedUpdatesAfterRecreate` doesn't test what it claims

* **Commit:** 24 `1060540e5eb`.
* **Where:** `tests/auto/widgets/kernel/qwidgetrepaintmanager/tst_qwidgetrepaintmanager.cpp:1288-1324`.
* **What:**
  * The doc of 24 says it covers "reparenting, adding a QRhiWidget". In my run, adding the
    QRhiWidget didn't recreate the window. The test printed "Window recreated when adding a
    QRhiWidget: false", and "QRhiWidget: No QRhi" twice, so the QRhiWidget never rendered. The
    second half therefore passes without exercising recreation.
  * The final pacing check is wrapped in `if (… usesPacedUpdateRequests())`, so on cocoa and ios it
    passes even if pacing silently stopped after recreation.
* **Proposed fix:** Force the recreation, or drop the QRhiWidget part and its claim. Make the
  QRhiWidget get a QRhi, or QSKIP. On cocoa and ios, `QVERIFY(usesPacedUpdateRequests())` instead
  of the `if`.
* **Resolved when:** the test fails if the preference or the pacing is lost across recreation.

### R1-9 (minor) visionOS: `pacesUpdateRequests()` is true, but update requests are never delivered there

* **Commit:** 23 `cbace1505b6`.
* **Where:** `src/plugins/platforms/ios/qioswindow.mm:448-453`; `qiosscreen.mm:157-232` (the
  display link is only created in the non-visionOS constructor).
* **What:**
  * On visionOS `QIOSScreen` has no display link, so `QIOSWindow::requestUpdate()` does nothing
    (`[nil setPaused:]`). That's pre-existing.
  * `pacesUpdateRequests()` still returns true when the window has a preference, so Widgets route
    `update()` through `requestUpdate()`.
* **Failure scenario:** A Widgets top-level on visionOS with `windowHandle()->setPreferredFrameRate(30)`
  stops repainting after the first `update()`.
* **Also:** `QIOSWindow::setPreferredFrameRate()` doesn't call the base implementation, which the
  new QPA doc asks for (`qplatformwindow.cpp` "and call the base implementation"). That's harmless
  today but inconsistent.
* **Proposed fix:** Return false from `pacesUpdateRequests()` when the screen has no display link
  (or on visionOS), and call the base in `setPreferredFrameRate()`.
* **Resolved when:** both changes are in.

### R1-10 (minor) CVDisplayLink still documented in qtdeclarative, and still used by qtmultimedia on macOS 14

* **Where:**
  * qtdeclarative `src/quick/doc/src/concepts/visualcanvas/scenegraph.qdoc:443` still says macOS
    uses "CVDisplayLink". The PR changes qtdeclarative but not this doc. AUDIT.md lists it as a doc
    update.
  * qtmultimedia `src/plugins/multimedia/darwin/mediaplayer/avfdisplaylink.mm:91-112` uses
    CADisplayLink only `@available(macOS 15.0)`, and CVDisplayLink otherwise. That code runs on
    Qt's supported macOS 14.4-14.x.
* **Why it matters:** Request #1 is "stop using the deprecated CVDisplayLink". For qtbase it's met.
  Qt-wide it isn't, and the README doesn't say so or list it as a follow-up.
* **Proposed fix:** Update scenegraph.qdoc in the qtdeclarative series (mention CADisplayLink and
  preferredFrameRate). Add a qtmultimedia change (or a README follow-up) that drops the fallback,
  which AUDIT.md already proposes.
* **Resolved when:** the doc is fixed and the qtmultimedia item is either done or listed.

### R1-11 (nit) Pacing state is recorded before a delivery that QCocoaWindow may defer

* **Where:** `src/plugins/platforms/cocoa/qcocoascreen.mm:458-465`. `QCocoaWindow::deliverUpdateRequest()`
  (`qcocoawindow.mm:1937-1946`) returns without delivering when the Metal layer's display lock is
  taken.
* **Scenario:** A 30 fps window on a 240 Hz link shared with a faster window. A deferred delivery
  still calls `frameDelivered()`, so the window waits another 8 link frames: one lost paced frame,
  during live resize.
* **Fix:** Only record `frameDelivered()` if the delivery happened. For example, have
  `QCocoaWindow::deliverUpdateRequest()` report whether it delivered, or compare
  `lastUpdateRequestDelivery` before and after.

### R1-12 (nit) `updateRequestInterval` isn't reset if the platform window dies during delivery

* **Where:** `qcocoascreen.mm:467-473`, `qiosscreen.mm:407-413`.
* **What:** If the handler destroys the platform window (`QWindow::destroy()`) and keeps the
  QWindow, the `continue` skips the reset. The paced interval then sticks to the QWindow after
  `create()`, so Qt Quick's expose-driven frames would use it.
* **Fix:** Keep a `QPointer<QWindow>` and reset on the `QWindowPrivate` whenever the QWindow still
  exists.

### R1-13 (nit) `QT_WIDGETS_PACED_UPDATES` is an untested, undocumented env var in production code

* **Where:** `src/widgets/kernel/qwidgetrepaintmanager.cpp:341-356`.
* **What:** The env var is new and switches behavior. Only an internal doc comment mentions it,
  and no test uses it. The planned `QT_WIDGETS_PACED_UPDATES=1` test target (REVIEW-API.md m13) is
  a follow-up. Qt review usually asks to either test such a switch or drop it.
* **Fix:** Add the test target, or drop the switch.

---

## Not findings (questions for the API review, noted for the record)

* Not `FINAL`: the rationale (QML `Window` subtypes that declare the same property) is valid and
  tested (`preferredFrameRateOwnProperty`). Expect Qt API review to ask anyway, as qmlsc can't
  optimize non-FINAL properties.
* Widgets have no `QWidget`-level accessor. Users must go through `windowHandle()`, which only
  exists after `create()`. `QTLWExtra::preferredFrameRate` already stores the value across
  recreation, so a `QWidget` accessor would be cheap if API review asks for one.
* The gcd union favors exactness over power. For example, 24 + 30 on 120 Hz, or 30 + 48 on
  240 Hz, give the system default (maximum rate). That's reasonable, but worth one sentence in the
  docs.
* Untested here, and not in TESTING.md's "not run" list: behavior when the display sleeps
  (CADisplayLink vs CVDisplayLink for apps rendering while the display is off). PLAN.md says
  sleep/wake was skipped.

## Verdict

**REQUEST CHANGES**. Two majors are open.

Counts: blocker 0, major 2, minor 8, nit 3.

* R1-1 major: Unexplained update-request stall on the new code, undisclosed and not root-caused
* R1-2 major: Wall-clock rate autotests are likely flaky on Coin and have never run there
* R1-3 minor: A request made during another window's delivery is left out of the link rate: up to one paced interval of latency
* R1-4 minor: Display ID change can strand pending update requests (new path)
* R1-5 minor: Every Widgets update on macOS now parses an ICC profile and looks up a dynamic property
* R1-6 minor: Public docs overpromise on Qt Quick animation speed, power, and default rate
* R1-7 minor: Squash plan can't be applied as written; WIP reference in a commit message
* R1-8 minor: `pacedUpdatesAfterRecreate` doesn't test what it claims
* R1-9 minor: visionOS: `pacesUpdateRequests()` is true, but update requests are never delivered there
* R1-10 minor: CVDisplayLink still documented in qtdeclarative, and still used by qtmultimedia on macOS 14
* R1-11 nit: Pacing state is recorded before a delivery that QCocoaWindow may defer
* R1-12 nit: `updateRequestInterval` isn't reset if the platform window dies during delivery
* R1-13 nit: `QT_WIDGETS_PACED_UPDATES` is an untested, undocumented env var in production code
