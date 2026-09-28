# Round 2: author's response

Summary: R2-1 fixed and verified with the simulation you asked for; R2-2 fixed by restructuring the
series (all three points, including the G5 split); R2-3 fixed; R1-7: the series is rebuilt, built
and tested per commit, and **committed and signed**, each commit's tree checked against its tested
tree (see R1-7). The R1-1
condition (CVDisplayLink A/B on the 120 Hz panel before Gerrit) is recorded as a pre-Gerrit TODO in
the README; the panel still isn't connected.

## R2-1 Stall recovery that doesn't help

`qcocoascreen.mm` (wip working tree, and series G2):

* `m_displayLinkStalled`: set by the watchdog from the second recovery in a row
  (`m_displayLinkRecoveries` was already ≥ 1). While it's set, `QCocoaScreen::requestUpdate()`
  still creates/resumes the link and arms the watchdog, but returns false, so `QCocoaWindow` uses
  the timer fallback. The timeout handler calls `fallBackToTimerBasedUpdateRequests()` for the
  windows already pending (via `!requestUpdate()`).
* `deliverUpdateRequests()` clears it with the back-off on the first real callback; the fallback
  timers stop through `stopFallbackUpdateTimer()` as before.
* While `CGDisplayIsAsleep()`, the watchdog re-arms with the maximum back-off (8 s × base).
* Warnings (in `qt.qpa.screen.updates`): "stopped delivering update requests. Recreating it" on the
  first recovery, "still doesn't deliver. Falling back to timer based update requests" once when
  it's marked stalled.
* Not done: logging in a category that's on by default. `qt.qpa.screen` and
  `qt.qpa.screen.updates` are both QtCriticalMsg by default in the cocoa plugin, and a default-on
  warning would print in every application that hits it; the stall is reported to users as a
  visible hitch at worst now. Happy to reconsider if you think field evidence outweighs that.

**Verified** with the simulation you asked for: a temporary patch (reverted, not committed) made
*every* display link's callbacks be ignored for 6 s starting at the 100th callback. Frames per
250 ms sample from the manual test's `--log`:

```
t=0.47 57   t=0.72 31   t=0.97 0 ... t=3.47 0      (stalled, first recovery at ~1.8 s doesn't help)
t=3.72 87   t=3.97 101 ... t=6.47 103              (second recovery at ~3.8 s: timer fallback)
t=6.72 86   t=6.97 60 ... t=8.22 60                (links deliver again: back to 240/s)
```

The freeze lasted ~3 s (0.72 → 3.72), as intended. The timer fallback runs at ~410/s because the
existing timer path divides its 5 ms idle time by `refreshRate / 60` (1 ms at 240 Hz); that's
pre-existing `QPlatformWindow::requestUpdate()` behavior. The display-link tests pass after the
change (12/12 targeted).

## R2-2 Series plan

1. **Intermediate rate checks.**
   * New `unthrottledRates()`: the rate the display link reports, or, if it reports none, anything
     from half the refresh rate to the refresh rate (the system can lower it without telling, e.g.
     Low Power Mode). Used by `requestUpdateRate`/`requestUpdateMultipleWindows` in all states.
   * `measureUpdateRates()`'s retry falls back to half the refresh rate as the expected rate when
     no interval is reported, so it isn't dead at G1.
   * **G2 now adds the private `QWindowPrivate::updateRequestInterval`** and the cocoa display
     link reports its frame interval during delivery, so from G2 on the tests compare against the
     link's real rate on macOS (iOS reports from G5b; until then iOS uses the half-to-full bounds).
     `AnimatingWindow` records the interval from G2 on.
   * G1's message now says what G1 does (the retry and the Low Power Mode bounds).
2. **G4 docs.** The property doc is split by what's true at each commit: G4 has the generic parts
   (hint, default rate, invalid values, timer platforms' minimum interval, others ignore it); G5c
   adds the macOS/iOS exact rates, windows that can't be exact together, the Qt Quick paragraph,
   and "Pacing to the display refresh is implemented on macOS and iOS"; G6 adds the Widgets
   paragraph. G4's message no longer claims display-paced platforms report the interval (G2 does
   on macOS, which the message doesn't need to mention).
3. **G5 split** as you suggested: G5a the QtGui model and delivery (+ `tst_qappleframerate`, no
   platform code), G5b iOS, G5c cocoa (+ the tst_qwindow frame-rate tests, which run on both).
   iOS before cocoa, so that no commit has display-paced frame-rate tests for a platform that
   doesn't pace yet.

## R2-3

* `tst_qwidgetrepaintmanager.cpp`: the "A widget that keeps scheduling updates" comment is back
  above `AnimatingWidget`.
* `scenegraph.qdoc`: `\l{Window::preferredFrameRate}{Window.preferredFrameRate}`.
* Messages rewritten (`/tmp/r2/msg/`): G2's nested loop paragraph is re-wrapped and says the freeze
  was the case with the GCD source too (main queue doesn't re-enter); every line ≤ 72 columns
  (checked with awk).
* G2's comment above `hasPendingDisplayLinkUpdateRequests()` now describes it.

## R1-7 status

The series is rebuilt from scratch on the base (driver `/tmp/r2/series.sh`): each state's files are
written, the state's `git write-tree` is recorded (`/tmp/r2/series-trees.txt`,
`/tmp/r2/decl-trees.txt`), then it's built and its tests run (logs `/tmp/r2/series-logs/`). When
signing works, the commits are created from the same files, and each commit's tree must equal the
recorded tree, which proves that what's committed is what was tested. Results: TESTING.md.

**Committed** (signing works again): every commit's tree equals its recorded tested tree, and both
series heads equal the wip branches (`git diff wip/cadisplaylink HEAD` is empty in both repos, apart
from `wip-cadisplaylink/` in qtbase).

* qtbase `wip/cadisplaylink-gerrit`: G1 `33df309acc2`, G2 `0bb7668b5f5`, G3 `e540b6b2c69`,
  G4 `4ecd0f4a096`, G5a `d6efb26498f`, G5b `bfdd5bad25a`, G5c `eaeb583f860`, G6 `fc439691c5e`,
  G7 `09ff153f888`.
* qtdeclarative `wip/cadisplaylink-gerrit`: D1 `7c4be21eb2`, D2 `d8bc4071be`.
* wip branches: qtbase `26ebb2c1559` (R2-1), `156c44caf6b` (R2-2, R2-3), then the WIP docs;
  qtdeclarative `71025ea33e` (Animator skip when covered), `62d1e64eeb` (R2-3 link).

The old G1 commit `7dc93d4377b` was dropped with the restructuring (never pushed).
