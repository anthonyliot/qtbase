# Round 2 review: CADisplayLink and QWindow::preferredFrameRate

Reviewer: independent, round 2. Scope:

* The author's answers in `round-1-author.md`.
* The round-1 fix commits on the wip branches:
  * qtbase `999f77a2ce5`, `d3faa00127b`, `cc0502d392b`, `139d48651ea`, head `139d48651ea`.
  * qtdeclarative `898d2daa3f`, plus the staged, uncommitted
    `tst_qquickanimations.cpp` change.
* The Gerrit series plan:
  * `pr/README.md` and `pr/series/*.md`.
  * The committed G1 `7dc93d4377b` on `wip/cadisplaylink-gerrit`.
  * The messages in `/tmp/r1/msg/`, the file lists in `/tmp/r1/series-g*.files`, the intermediate
    G2 cocoa sources in `/tmp/r1/g2/`, and `/tmp/r1/tst_qwindow.g{1,2,4}.cpp`.

`file:line` references are at the wip heads unless another file is named.

## Summary

The round-1 fixes are good, and better than I asked for in places:

* **Shared delivery.** Moving the per-screen delivery into `QAppleDisplayLinkDelivery` removes
  the cocoa/iOS duplication. It makes the pacing testable without a display, and it fixes R1-3,
  R1-11 and R1-12 structurally rather than with patches. `tst_qappleframerate` now pins down the
  delivery decisions deterministically: 151 cases, including both window orders for R1-3.
* **Exact pacing checks.** `QCOMPARE_PACING` checks the interval the link paced the window at, to
  1%. That tells adjacent exact rates apart, which the 20% rate tolerance couldn't.
* **Soak.** The 20-run soak under heavy load is credible evidence for R1-2.

Both majors from round 1 are resolved. For R1-1 I accept the deferral of the root cause: the
recorded trigger configurations are now sent as the default range, the stall is disclosed, and
there's a recovery path. One weakness remains in that recovery (R2-1): it bounds a stall of *one
link*, not a stall whose cause survives recreating the link.

The rest is about the Gerrit series:

* It still isn't committed. Only G1 is, so R1-7 stays open.
* Its intermediate states have a few defects (R2-2): G1 contains dead retry code and a commit
  message claim that only becomes true in G4, and G4 documents behavior that only G5 implements.

None of the open findings is a blocker or a major.

## What I verified

* **Builds:** `qt5-build-cadisplaylink` (QtGui, the cocoa plugin, tst_qwindow,
  tst_qappleframerate, tst_qwidgetrepaintmanager) is up to date at the qtbase head.
  `qt5-build-nofw` plus `qt5-build-nofw-qtdeclarative` (tst_qquickanimations, tst_qquickwindow)
  was rebuilt at both heads, including the staged qtdeclarative change.
* **`tst_qappleframerate`:** 151 passed.
* **`tst_qwindow`, all 22 display-link and frame-rate functions (41 rows):** 41 passed and 1
  skipped (`preferredFrameRatePerScreen`, one screen). 240 Hz Odyssey G95SC, the only display.
* **`tst_qwidgetrepaintmanager pacedUpdates pacedUpdatesSemantics pacedUpdatesAfterRecreate`:**
  6 passed, and no more "No QRhi" warnings.
* **`tst_qquickanimations stepsWithPreferredFrameRate animatorDurationWithPreferredFrameRate`:**
  4 passed. **`tst_qquickwindow preferredFrameRate*`:** 5 passed.
* **R1-3, with my probe from round 1** (`/tmp/rvw/latency`, rebuilt plugin): driven-window latency
  median 0.0054 ms with the driven window visited before the driving one (was 33.34 ms), and
  0.0054 ms after it.
* **Watchdog false positives** (`/tmp/rvw/switch.cpp`): a 240 fps window switches to
  `preferredFrameRate(1)` between frames, at 8 different phase offsets, with
  `qt.qpa.screen.updates.warning=true`. The watchdog never logged "stopped delivering". The window
  where it could fire spuriously (the watchdog is armed with the fast link's 1 s timeout before the
  switch) is about 4 ms per second wide, and a spurious recreation is harmless anyway. So it's not
  a finding.
* **The G2 intermediate cocoa sources** (`/tmp/r1/g2/`) don't use anything that only exists after
  G2. None of `preferredFrameRate`, `updateRequestInterval`, `QAppleFrameRate*`,
  `pacesUpdateRequests` or `frameRatePreference` appears; the only near match is
  `CADisplayLink.preferredFrameRateRange`, read by the watchdog. The file diffs against the head
  are only the pacing parts. The G2 delivery (snapshot, first pass, second pass for windows that
  got a request during the pass, pause if nothing is pending) is the head's
  `QAppleDisplayLinkDelivery::deliver()` without pacing. `/tmp/r1/series-g2-build.log` shows the
  cocoa plugin compiling at G2.
* **G1:** the committed tst_qwindow.cpp is byte-identical to `/tmp/r1/tst_qwindow.g1.cpp`.
* **Commit messages** (`/tmp/r1/msg/*.txt`): no WIP, review or plan references.

## Status of the round-1 findings

| ID | Round-1 severity | Status | Evidence at the head |
|---|---|---|---|
| R1-1 | major | **Deferral accepted** (root cause and ProMotion A/B). Residual in R2-1 | `withoutExplicitMaximum()` `qappleframerate.cpp:332-341, 378`; watchdog `qcocoascreen.mm:393-398, 455-467, 505-551`; README "Known limitations" and TESTING.md "Not run" |
| R1-2 | major | **Fixed, accepted** | Deterministic delivery tests in `tst_qappleframerate.cpp`; `QCOMPARE_PACING*` in `tst_qwindow.cpp`; retry in `measureUpdateRates()`; soak `/tmp/r1/soak-results.txt` (19 of 20 runs clean; run 20's failure was a covered window, fixed by the staged qtdeclarative change) |
| R1-3 | minor | **Fixed, accepted** | Two passes in `QAppleDisplayLinkDelivery::deliver()` `qappleframerate.cpp:392-445`, range from `pendingRange()`; test `deliveryToWindowRequestedDuringDelivery` (both orders); my probe 0.0054 ms |
| R1-4 | minor | **Fixed, accepted** | `qcocoascreen.mm:226`: `if (hasPendingUpdateRequests() && !requestUpdate()) fallBackToTimerBasedUpdateRequests();`. The timer-delivered windows retry the link through `QCocoaWindow::requestUpdate()` until the NSScreen exists |
| R1-5 | minor | **Fixed, accepted** | `updatesWithDisplayLink()` uses `requestedFormat().swapInterval()`; `pacesUpdateRequests()` checks the preference first (`qcocoawindow.mm:1906-1932`). No ICC work on the non-paced Widgets path. A dynamic property lookup remains, which is fine |
| R1-6 | minor | **Fixed, accepted** | `qwindow.cpp:1306-1327`; qtdecl `qquickwindow.cpp` doc. Animators, several windows, the default rate and the gcd case are all stated accurately |
| R1-7 | minor | **Open** (partially resolved) | See below |
| R1-8 | minor | **Fixed, accepted** | `pacedUpdatesAfterRecreate` requires `usesPacedUpdateRequests()` and a pending *window* update request after `update()`, which only the paced path makes. The QRhiWidget part is gone |
| R1-9 | minor | **Fixed, accepted** | `QIOSScreen::hasDisplayLink()`; `QIOSWindow::pacesUpdateRequests()` requires it; `setPreferredFrameRate()` calls the base |
| R1-10 | minor | **Fixed (doc), deferral accepted (qtmultimedia)** | qtdecl `scenegraph.qdoc:443-447`; README follow-up with file and fix |
| R1-11 | nit | **Fixed, accepted** | `frameDelivered()` only when `Screen::deliverUpdateRequest()` returns true; `QCocoaWindow::tryDeliverUpdateRequest()`; test `deliveryDeferred` (frames 0, 9, 17) |
| R1-12 | nit | **Fixed, accepted** | Reset through `QPointer<QWindow>` (`qappleframerate.cpp:407-416`); test `deliveryWindowGoesAway`, which also covers deleting another window during delivery (README limitation dropped, rightly) |
| R1-13 | nit | **Fixed, accepted** | `QT_WIDGETS_PACED_UPDATES` removed |

### R1-1: why I accept the deferral

My round-1 resolution paths were a root cause, or a baseline A/B plus disclosure plus a safety
net. The A/B needs the ProMotion panel, which isn't connected. The trigger for both recorded
configurations, (120,120,120) and (1,120,0) on 120 Hz, is removed. That's tested in
`preferenceExplicitMaximum`.

I also checked that no other path can still send such a range after sanitization:

* Public ranges never have n = 1.
* `unitedWith()` of sanitized inputs can't reach a maximum of 0.99 × refresh or more with
  preferred 0.
* The gcd path returns the default range when the common divisor is 1.

The stall is disclosed, and a watchdog recreates a link that stops calling back. Deferring the
root cause is acceptable on the condition that the ProMotion A/B is run before the series goes to
Gerrit, as TESTING.md "Not run" already says. R2-1 is about making the safety net hold whatever
the cause turns out to be.

### R1-7: still open

The plan is sound as a structure:

* The G1 regression tests pass on the old CVDisplayLink plugin.
* G2 switches to CADisplayLink without pacing.
* G4 adds the public API, then G5 the pacing, G6 Widgets, G7 the manual test.
* D1 and D2 in qtdeclarative follow the qtbase series.

The per-commit build and test table is in TESTING.md. But:

* G2-G7 and D1-D2 exist only as tree states and file lists.
* The qtdeclarative fix from the soak (`animatorDurationWithPreferredFrameRate` skipping when
  covered) is staged, not committed. It belongs in D1, per `series/D1-animation-interval.md`.
* See R2-2 for defects in the planned states.

**Resolved when:** the series is committed on `wip/cadisplaylink-gerrit` in both repos, each
commit builds (as already done for the planned states), and the README maps to the real hashes. I
review that in round 3.

## New findings

| ID | Severity | Title | Where |
|---|---|---|---|
| R2-1 | minor | Stall recovery only helps if a new display link delivers; otherwise windows stay frozen | `qcocoascreen.mm:517-551` (G2) |
| R2-2 | minor | Series plan: G1 carries dead retry code and a message claim that only G4 makes true; G4 documents G5 behavior; G5 is very large | G1 `7dc93d4377b`, `/tmp/r1/msg/g1.txt`, `g4.txt`, `/tmp/r1/g2/`, `series-g5.files` |
| R2-3 | nit | Small comment, link and message nits | `tst_qwidgetrepaintmanager.cpp:1099`, qtdecl `scenegraph.qdoc:446`, `/tmp/r1/msg/g2.txt` |

---

### R2-1 (minor) Stall recovery only helps if a new display link delivers; otherwise windows stay frozen

* **Commit:** `999f77a2ce5` (series: G2).
* **Where:** `src/plugins/platforms/cocoa/qcocoascreen.mm:517-551` (`displayLinkWatchdogTimeout`),
  `:393-398` (arming in `requestUpdate()`), `:455` (back-off reset on a real callback).
* **What:** When the watchdog detects a stall, it invalidates the link and calls `requestUpdate()`.
  That creates a new link and returns true, so it only falls back to the timer if the new link
  can't be created at all.
  * If the cause isn't specific to one link object (the root cause is unknown), the new link
    doesn't call back either. The watchdog then recreates it again after 2, 4, 8, 8, … s.
  * The pending windows get nothing in the meantime: no timer fallback, because every
    `QCocoaWindow::requestUpdate()` succeeds on the new link and stops the fallback timer
    (`qcocoawindow.mm:1884-1886`).
  * So the freeze isn't bounded, which is what R1-1's safety net is for.
  * The author's simulation doesn't cover this case. The temporary patch made Qt ignore one link's
    callbacks, so a new link necessarily helped.
* **Failure scenario:** 120 Hz ProMotion, whatever caused the recorded stalls happens again, but at
  the WindowServer or panel level rather than to one CADisplayLink object. The window freezes as
  in round 1. The only change is a silent `qt.qpa.screen.updates` warning, then a link recreation
  every 8 s.
* **Evidence:** code reading of the lines above.
* **Proposed fix:**
  * From the second consecutive recovery (`m_displayLinkRecoveries >= 1` on timeout), mark the
    link as stalled: `QCocoaScreen::requestUpdate()` returns false while that flag is set, as it
    does for `m_nestedEventLoopInDelivery`.
  * Call `fallBackToTimerBasedUpdateRequests()`, and clear the flag at the start of
    `deliverUpdateRequests()`. The first real callback then stops the timers through
    `stopFallbackUpdateTimer()`, which is already in place.
  * That bounds the freeze to about 1 + 2 s whatever the cause.
  * Optional: while `CGDisplayIsAsleep()`, re-arm with the maximum back-off instead of the base
    timeout (1 Hz wakeups all night otherwise).
  * Optional: log the first recovery in a category that is on by default at warning level, so
    that field reports give evidence for the root cause.
* **Resolved when:** a stalled link that stays stalled leads to timer-delivered update requests
  within a bounded time. Checked with the author's temporary patch, extended to ignore the
  callbacks of *every* link for some seconds.

### R2-2 (minor) Series plan: G1 carries dead retry code; G4 documents G5 behavior; G5 is very large

* **Where:**
  * G1 `7dc93d4377b` `tests/auto/gui/kernel/qwindow/tst_qwindow.cpp:3258, 3316, 3352-3357`,
    identical to `/tmp/r1/tst_qwindow.g1.cpp`.
  * `/tmp/r1/tst_qwindow.g2.cpp`.
  * `/tmp/r1/msg/g1.txt`, `/tmp/r1/msg/g4.txt`.
  * `series/G4-qwindow-api.md` "Note".
  * `/tmp/r1/series-g5.files`.
* **What:**
  1. **G1 and G2: `AnimatingWindow::lastUpdateRequestInterval` is never assigned.** The assignment
     from `QWindowPrivate::updateRequestInterval` only comes in G4 (`diff tst_qwindow.g2.cpp
     tst_qwindow.g4.cpp`), and the cocoa plugin only reports an interval from G5. So at G1-G4:
     * The retry in `measureUpdateRates()` can never trigger.
     * `unthrottledRate()` always returns the nominal `QScreen::refreshRate()`.
     * G1's message nonetheless says the rates are "measured again when a loaded machine missed
       more than half of the frames".
     * Comparing against the nominal rate is what REVIEW-API.md m10 fixed: it fails when the
       system runs the link below the refresh rate, as in Low Power Mode. It comes back in the
       intermediate states, including the "no regression" G1/G2 runs.
     * With the 40% tolerance, a link capped at 60 on a 120 Hz panel fails `requestUpdateRate`
       at G1-G4 (60 < 72).
  2. **G4:** the message says "Platforms that pace update requests to the display report it too",
     and the `QWindow::preferredFrameRate` doc describes the macOS/iOS pacing. Both only become
     true at G5 (the author notes this in `series/G4-qwindow-api.md`). A reviewer of G4 alone sees
     docs that don't match the code.
  3. **G5 is very large.** It holds `qappleframerate.{cpp,_p.h}`, `QAppleDisplayLinkDelivery`, the
     cocoa and iOS integration, `tst_qappleframerate` (about 760 lines) and the tst_qwindow
     frame-rate tests: roughly 2,000 lines, merging the old 02, 04, 06, 10, 15, 16, 18, 23, 25 and
     30. That will be hard to review on Gerrit.
* **Proposed fix:**
  1. In G1, either drop the retry and the `lastUpdateRequestInterval` fallback and add them in
     G4/G5 with the message wording, or make G1 self-contained. For example, skip the absolute
     rate check when `NSProcessInfo.lowPowerModeEnabled` (macOS 12+), or compare the two windows
     of `requestUpdateMultipleWindows` with each other.
  2. Move the macOS/iOS paragraphs of the property doc, and the "platforms report it too"
     sentence, into G5. Or word them in G4 as what platforms may do.
  3. Consider splitting G5 into three commits:
     * G5a: the QtGui helper, `QAppleDisplayLinkDelivery` and `tst_qappleframerate`, all
       platform independent and testable.
     * G5b: cocoa, with the tst_qwindow frame-rate tests.
     * G5c: iOS.
* **Resolved when:** the committed series (round 3) has G1 and G4 messages and docs that are true
  at those commits, and G1's rate checks don't depend on the nominal refresh rate, or skip where
  it doesn't apply. The G5 split is a recommendation, not a condition.

### R2-3 (nit) Small comment, link and message nits

* `tests/auto/widgets/kernel/qwidgetrepaintmanager/tst_qwidgetrepaintmanager.cpp:1099`: the comment
  "A widget that keeps scheduling updates, like an animated view" now sits above the new
  `updateRequestInterval()` helper instead of `AnimatingWidget`.
* qtdeclarative `scenegraph.qdoc:446`: `\l{QWindow::preferredFrameRate}{Window.preferredFrameRate}`
  shows the QML name but links to the C++ property. Link `\l{Window::preferredFrameRate}` instead,
  as the QML doc exists (qquickwindow.cpp).
* `/tmp/r1/msg/g2.txt`:
  * The paragraph on nested event loops has a broken wrap ("…which froze / every window on the
    screen. A timer can / only fire…").
  * It doesn't say that the freeze was pre-existing with the GCD source. It was, since the main
    queue doesn't re-enter.
  * Lines over 72 columns: `g2.txt:3`, `g4.txt:9`, `d1.txt:14, 19-21, 23`.
* G2 `/tmp/r1/g2/qcocoascreen.mm:585`: the comment above `hasPendingDisplayLinkUpdateRequests()`
  still says it "Updates the display link's frame rate range", which G2 doesn't have.

---

## Verdict

**APPROVE** the code at the wip heads, with the minors and nits below. No blocker or major is open.
This approval doesn't cover the Gerrit series yet: R1-7 stays open until the series is committed
in both repos and I've reviewed the actual commits in round 3. I'd also like R2-1 fixed before
Gerrit, as it's what makes the R1-1 deferral safe.

Counts: blocker 0, major 0, minor 3, nit 1. Round 1: 12 accepted (R1-1 and part of R1-10 as
deferrals), 1 still open.

Open findings:

* R1-7 minor: Squash plan can't be applied as written. Now partially resolved: the plan exists and
  was built per commit, but G2-G7, D1-D2 and the staged qtdeclarative fix aren't committed
* R2-1 minor: Stall recovery only helps if a new display link delivers; otherwise windows stay frozen
* R2-2 minor: Series plan: G1 carries dead retry code and a message claim that only G4 makes true; G4 documents G5 behavior; G5 is very large
* R2-3 nit: Small comment, link and message nits
