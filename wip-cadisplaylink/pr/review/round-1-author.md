# Round 1: author's response

Author: the agent that wrote the PR. Branch heads after this round:

* qtbase `wip/cadisplaylink`: round 1 fixes `999f77a2ce5`, `d3faa00127b`, `cc0502d392b`,
  `139d48651ea` (on top of `9f7d196a2bb`).
* qtdeclarative `wip/cadisplaylink`: `898d2daa3f`.
* **The Gerrit series** (R1-7): qtbase `wip/cadisplaylink-gerrit`, qtdeclarative
  `wip/cadisplaylink-gerrit`, worktrees in `~/Desktop/bitbucket/qt5-series/`. See R1-7.

Summary: 12 findings fixed, 1 fixed with a mitigation and disclosed rather than root-caused (R1-1,
the ProMotion panel isn't connected to this machine now), 0 rebutted. One more problem found while
fixing (at the end).

| ID | Response | Where |
|---|---|---|
| R1-1 | Mitigated (trigger removed, recovery added, verified by simulation), disclosed; not root-caused | `999f77a2ce5`; README, TESTING.md |
| R1-2 | Fixed: deterministic delivery tests, exact pacing checks, retry; 20-run soak under load | `999f77a2ce5`, `cc0502d392b`, `d3faa00127b`; TESTING.md |
| R1-3 | Fixed, with a test in both orders; your probe now measures 0.008 ms | `999f77a2ce5` |
| R1-4 | Fixed: timer fallback when the new link can't be created | `999f77a2ce5` |
| R1-5 | Fixed: no `format()`/ICC on the update path | `999f77a2ce5` |
| R1-6 | Fixed in both docs | `139d48651ea`, qtdecl `898d2daa3f` |
| R1-7 | Fixed: the series exists, built and tested commit by commit | see R1-7 |
| R1-8 | Fixed | `d3faa00127b` |
| R1-9 | Fixed | `999f77a2ce5` |
| R1-10 | scenegraph.qdoc fixed; qtmultimedia listed as a follow-up | qtdecl `898d2daa3f`; README |
| R1-11 | Fixed, with a test | `999f77a2ce5` |
| R1-12 | Fixed, with a test | `999f77a2ce5` |
| R1-13 | Fixed: the switch is gone | `d3faa00127b` |

## R1-1 Stall

What's known, from the notes: every recorded stall was on the 120 Hz ProMotion built-in panel with
an explicit private range asking for the maximum rate: `QT_APPLE_PREFERRED_FRAME_RATE_RANGE=120`
((120,120,120)) in `video-rates` (DESIGN.md:46), and `120` / `1,120` ((1,120,0)) in VIDEO.md. The
PLAN.md occurrence doesn't record its configuration. The public API never sends such ranges.
The ProMotion panel isn't connected to this machine at the moment (only the 240 Hz G95SC), so I
couldn't root-cause it or run the CVDisplayLink A/B there. Three changes instead:

1. **Trigger removed.** `QAppleFrameRatePreference::update()` passes a private range whose maximum
   is at least the display's rate, without a lower preferred rate, on as the default range
   (`withoutExplicitMaximum()`, `qappleframerate.cpp`). That's what such ranges mean, and what the
   public API already did for n = 1. Both recorded configurations become the default range.
   Tested in `tst_qappleframerate::preferenceExplicitMaximum` (120@120, 1,120@120, 240@120,
   119.94@120 → default; 1,120,60 and 60@120, 120@240 kept; unknown display kept).
2. **Recovery.** The nested event loop watchdog is now one timer for three cases
   (`displayLinkWatchdogTimeout()`, `qcocoascreen.mm`):
   * During delivery (can only fire in a nested loop): timer fallback, as before.
   * Between deliveries: armed while the link runs with pending display-link requests. If there's no
     callback for ten frames at the slowest rate the link may run at (at least 1 s, doubling up to
     8 s for repeated recoveries, reset by a real callback), it logs a warning in
     `qt.qpa.screen.updates` (silent by default) and recreates the link, falling back to the timer
     if that fails. Skipped while `CGDisplayIsAsleep()`, so a sleeping display doesn't make it
     spin.
   * Verified by simulation: a temporary patch (not committed) made `displayLinkDidFire` ignore
     every callback of a link after 100 callbacks. The manual test ran at 240 fps, stopped at
     t≈0.9 s, the watchdog logged "stopped delivering update requests. Recreating it" at t≈1.9 s,
     and it was back at 240 fps from the next 250 ms sample. No false positives in 4 s runs with
     `--rate 1`, `--rate 30` and the default, with the warning category enabled.
3. **Disclosed** in the PR README (known limitations) and TESTING.md.

I think this meets your second resolution path, except for the baseline A/B, which needs the
ProMotion panel. It's listed as open in TESTING.md.

## R1-2 Wall-clock tests

* **Deterministic coverage**: the per-screen delivery is now `QAppleDisplayLinkDelivery` in QtGui,
  used by both plugins, and `tst_qappleframerate` drives it with synthetic display link frames and
  fake, never created windows (no display, no timing):
  * `deliveryPacesEachWindow`: 30 fps next to a full-rate window at 240 Hz, 240 frames: 240 and 30
    deliveries, 8 frames apart, intervals 8/240 and 1/240, reset to 0 after delivery, and
    (30,30,30) once the fast window is gone.
  * `deliveryExactRatesTogether`: 24 + 60 at 120 Hz: default range, 24 and 60 deliveries, intervals
    1/24 and 1/60; 30 + 60: (60,60,60), then 30 and 60 per second on a 60 Hz link.
  * `deliveryToWindowRequestedDuringDelivery` (both orders, asserted from `allWindows()`): R1-3.
  * `deliveryPausesWhenIdle`, `deliveryDeferred` (R1-11), `deliveryWindowGoesAway` (R1-12, and a
    window deleted during another's delivery).
  * `tst_qappleframerate` has 151 cases.
* **Discrimination**: `QCOMPARE_PACING*` checks the interval the link paced the window at during
  its last delivery, which doesn't depend on missed frames, to 1%. It's added to the private
  preference, mixed windows, runtime change, video+UI and per-screen tests. The API tests already
  checked it. `pacedUpdates` (Widgets) now checks it too, from inside `paintEvent`/`render()`. So
  24 can't pass for 30 anymore.
* **Robustness**: `measureUpdateRates()` measures again (up to three times) when a window got less
  than half of the frames it was paced at. The measured rate is only checked loosely (−40%/+10%).
* **Evidence**: 20 consecutive runs of every wall-clock test (41 tst_qwindow rows, 4 Widgets rows,
  2 Qt Quick functions) while another workload (a Metal shader build, a dozen `applegpu-nt`
  processes) kept the 1-minute load average between about 30 and 217: see TESTING.md. Runs 1-19
  passed; in run 20 the windows got covered (Widgets skipped, and the Animator test failed instead
  of skipping, now fixed, see "Found while fixing").
* **On Coin**: nothing in these tests needs more than a display that the window can be shown on, as
  the other tst_qwindow tests already do. The display-paced tests skip everywhere but cocoa/ios.
  The strict rate tables are gone: the remaining rate checks are smoke checks, and the exact
  properties are in the deterministic tests. I have no Coin access to prove it.

## R1-3

`QAppleDisplayLinkDelivery::deliver()` makes two passes over the windows it snapshotted
(`QPointer`s): due windows that were pending when visited, then windows that became pending during
the pass and weren't visited as pending. A window gets at most one delivery per link frame. The
range comes from all pending windows at the end (`pendingRange()`), so the re-scan of 16 is always
done: one more loop over the windows per frame. Your `/tmp/rvw/latency` against the new build:
`B visited before A … B latency ms: n 18 median 0.0078 max 0.0104` (was 33.34) and
`B visited after A … median 0.0073`.

## R1-4

`QCocoaScreen::update()`: `if (hasPendingUpdateRequests() && !requestUpdate())
fallBackToTimerBasedUpdateRequests();`. The pending windows then deliver via the timer, request
again, `QCocoaWindow::requestUpdate()` retries the link and falls back to the timer until the
NSScreen exists. Not tested by hand, as I can't change a display ID here. The reasoning is above,
and the watchdog would also recover a stranded link.

## R1-5

`updatesWithDisplayLink()` uses `window()->requestedFormat().swapInterval()`. `format()` is
`requestedFormat()` plus the color space, so the result is the same. `pacesUpdateRequests()` checks
the preference first. This also removes the ICC parse from the existing per-frame calls.

## R1-6

`qwindow.cpp`: Animators can run slower for about a tenth of a second when they start, on displays
that switch to a lower refresh rate for the preferred rate. Several visible Qt Quick windows tick
animations with a timer at the display's rate while rendering is still paced. The default is the
display's rate on macOS/iOS and every few milliseconds on timer platforms. Windows with rates that
can't be shown together at a lower rate keep the display at its full rate (your gcd note). The QML
doc says the same. The "one window's preference doesn't slow down another" sentence is true again
after R1-3.

## R1-7

The series is rebuilt from the final tree as logical changes rather than cherry-picked, with
intermediate versions where a file changes in two commits (`tst_qwindow.cpp`, and the cocoa sources
for the CADisplayLink switch, without pacing). Built and tested commit by commit in a separate build
(`qt5-series-build`); log in TESTING.md. The README maps the old commits to the series. No WIP
wording in any message (commit 09's "(see the WIP API proposal)" is gone with it).

The plan: qtbase G1 tests for delivery (they pass on the **old** CVDisplayLink plugin, so they
prove no regression), G2 the CADisplayLink switch with its own delivery tests, G3 doc, G4
`QWindow::preferredFrameRate` (+ timer path), G5 Apple pacing (+ `tst_qappleframerate`), G6
Widgets, G7 manual test; qtdeclarative D1 animation interval, D2 QML doc and tests. Documents:
`pr/series/`, map in the README, per-commit results in TESTING.md.

**Status, honestly:** commit signing (AppleConnect) is blocked while the user is away, and I
don't bypass it. So far only **G1 is committed** (`7dc93d4377b` on qtbase
`wip/cadisplaylink-gerrit`). G2 to G7 were built and tested in order as tree states in the series
worktree (its index now holds the cumulative G7 state, identical to the wip branch). They will be
committed with the messages in `/tmp/r1/msg/g*.txt`, from the recorded file lists and intermediate
files (`/tmp/r1/series-g*.files`, `/tmp/r1/g2/`, `/tmp/r1/tst_qwindow.g{2,4}.cpp`), as soon as
signing works. The qtdeclarative series (D1 staged in its worktree) is building against the
non-framework qtbase. Also staged but not committed for the same reason: qtdeclarative's
"tst_qquickanimations: Skip the Animator duration test when covered" (`git -C qtdeclarative diff
--cached`), from the soak (TESTING.md).

So for round 2: please review the round 1 fixes on the wip branches now, and the series plan
(messages, file split, intermediate G2 cocoa sources in `/tmp/r1/g2/`). I'll ask you to check the
committed series in round 3.

## R1-8

`pacedUpdatesAfterRecreate`: the QRhiWidget part is gone (it doesn't recreate the QWindow on macOS,
and never got a QRhi). On cocoa/ios it now requires `usesPacedUpdateRequests()`, waits for no
pending request, calls `update()`, and requires a pending *window* update request, which only the
paced path makes.

## R1-9

`QIOSScreen::hasDisplayLink()`; `QIOSWindow::pacesUpdateRequests()` is false without one
(visionOS). `QIOSWindow::setPreferredFrameRate()` calls the base.

## R1-10

`scenegraph.qdoc` names CADisplayLink and points to `Window.preferredFrameRate`. qtmultimedia's
`avfdisplaylink.mm` CVDisplayLink fallback for macOS 14.x is outside the repos in this PR (there's
no fork of qtmultimedia); it's listed as a follow-up in the README with the file and the fix
(drop the `@available(macOS 15.0)` fallback, as NSScreen/NSView display links exist from 14.0).

## R1-11, R1-12

Both in `QAppleDisplayLinkDelivery::deliver()`: `frameDelivered()` only if
`Screen::deliverUpdateRequest()` returns true (`QCocoaWindow::tryDeliverUpdateRequest()` reports the
Metal-layer deferral), and the interval is reset through a `QPointer<QWindow>`. Tests:
`deliveryDeferred` (deliveries at frames 0, 9, 17 instead of 0, 16), `deliveryWindowGoesAway`.

## R1-13

Dropped `QT_WIDGETS_PACED_UPDATES`.

## Found while fixing

* `animatorDurationWithPreferredFrameRate` failed instead of skipping when its window got covered:
  a covered window isn't rendered, so the Animator never finished, and the test waited 5 s before
  checking exposure. It now checks exposure when the wait times out (qtdeclarative, staged, pending
  signing).

* The CoreVideo link was unused (fixed before this round, commit 28).
* Your "not findings": the gcd note is in the docs now. A `QWidget` accessor and FINAL are left for
  API review. Display sleep: the watchdog doesn't act while `CGDisplayIsAsleep()`; rendering while
  the display is off wasn't tested (TESTING.md, not run).
