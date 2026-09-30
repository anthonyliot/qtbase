# Round 13 review: qtmultimedia series (M1 to M6)

Reviewer: qt-cadisplaylink-pr-reviewer (independent, strict)
Repo: `qt5/qtmultimedia`, base upstream `635067497`. The committed branch is still the round 12
series (`f0c358d29`..`0e21dc1b3`, pushed); the worktree is at S6'. Line numbers are at S6' (code) or
at the current, uncommitted documents.

Round 12 approved on one condition: M5 doesn't go to Gerrit before the ProMotion session, and M5 is
reconsidered if the panel doesn't drop with FFmpeg. The session ran and M5 changed.

| # | Tree | Subject | This round |
|---|---|---|---|
| M1-M4 | S1-S4, unchanged | | none |
| M5 | S5 `824627c8497b` (was `7fb32794b550`) | QVideoWindow: Show frames evenly on variable refresh rate displays | R12-3, R12-4, rationale after the measurement |
| M6 | S6 `a8e69274ace7` (was `f4801ada7da2`) | darwin: Poll for video frames in sync with the display the video is on | none (same `git patch-id --stable`, `00e953ac…`) |

## How I checked

* **Trees.**
  * `refs/cadisplaylink/series/S1..S6` are trees and equal `trees.txt`.
  * The worktree equals S6': `git hash-object --stdin-paths` (no `-w`) over its 3244 blobs, 0
    differ.
    Checked at the start and again at the end.
  * `git diff 7fb32794b550 824627c8497b` and `git diff f4801ada7da2 a8e69274ace7` are the same delta
    (3 files, +28 -18) apart from index lines and hunk offsets.
  * M6's patch-id is unchanged.
  * `diff-tree --check` is clean. No added line is over 100 columns.
  * `M1..M6.txt`: at most 72 columns, line 2 blank, 6 distinct Change-Ids.
* **Code and tests.**
  * I traced R12-3's step through the ownership rule, with and without the else branch.
  * I read the negative-check logs (`m5fix/neg-*.log`).
  * `cmake --build qtmm-build --target tst_qvideowindow tst_qmultimediautils` was a no-op: the
    binaries (15:55) are newer than the restored sources (15:53:20).
  * I ran `tst_qvideowindow`: 7 passed on cocoa, and on `offscreen` 5 passed, 2 skipped (the new
    step passes there too). `tst_qmultimediautils`: 307 passed.
  * Every log in `states13/`, `m5fix/` and `ffmpeg9/`: totals, warnings, mtimes, the S5 leak probe
    output and its heap dump.
* **The measurement.** I didn't record anything; I only reanalysed what was recorded.
  * `/tmp/rv13/an/` has symlinks to every exported table, probe output, Qt log and xctrace log in
    `promotion-evidence-2026-09-29/`.
  * I ran the committed `analyze.py` (with its `xctrace export` fallback disabled), `cadence.py`,
    `qtlog.py` and `xtable.py summary` on every run. The committed analysis scripts are
    byte-identical to the job-directory ones (`cmp`).
  * I wrote scratch scripts in `/tmp/rv13/`:
    * `rcad.py` and `rcadt.py`: the render cadence from the Qt logs (intervals between delivering
      display link callbacks), per run, per time window and over time;
    * `phase.py`: the wait from request to delivery over time;
    * `vtl.py` and `seg.py`: the panel's refresh intervals and the surfaces displayed, per segment;
    * `cadseg.py`: `cadence.py` per segment.
  * I lined the Qt logs up with each trace's `start-date` and `duration` (`*.toc.xml`), and read the
    six job-directory `measure*.sh` and `matrix*.sh` scripts against the committed ones.
* **Disclosure.**
  * qtmultimedia and qtbase: read-only git with `GIT_OPTIONAL_LOCKS=0`.
  * qtmm-build: the no-op build and the test runs above.
  * No Instruments, no viewprobe run, nothing in `qt5-build-release` or `~/Qt`.

---

## Summary

**The code changes are right.**

* **R12-3.** The new step (`tst_qvideowindow.cpp:222-225`) is exactly the transition the else branch
  exists for. Without the branch, the stale value equals the other component's 60 → the paused
  frame writes 0 → FAIL at :225, which is what `neg-tst_qvideowindow.log` shows ("Actual 0,
  Expected 60"). The comment at `qvideowindow.cpp:587-588` says why.
* **R12-4.** "the internal window" (`qvideowidget.cpp:40`) is in.
* The verification logs match TESTING's "Round 13 changes":
  * S5 20/20 on both backends, S6 22 + 1 skipped;
  * 307, 7, 8 + 1, and 80 `destruction` rows;
  * the leak probe: 20 players with a frame, a valid dump with no `DisplayLinkObserver` or
    `CADisplayLink`;
  * no warnings in series files.

**The measurement supports keeping M5 for FFmpeg's cadence, but less strongly than the documents
say, and part of what they cite didn't measure the video at all.**

* **Solid.** The probe's own display link log shows that with M5 the window is updated on the 24 Hz
  grid:
  * 98.5 to 100% of intervals at 41.7 ms in the three visible, undisturbed M5 runs (about 3,700
    frames);
  * against 80 to 94% for the four default arms (about 17,300 frames, including a 10-minute run),
    whose uneven updates come in stretches.
  * On screen, the one undisturbed composited pair gives 96.7% against 88.3%.
  * That's the user's criterion, and it's met under ordinary conditions.
* **Not solid:**
  * **R13-1 (major).** In three of the four arms of the panel-rate table, the video window made no
    update request during the recording. The panel sat at its minimum rate, 24 Hz, with nothing
    to show. The one valid AVFoundation default run contradicts "follows the content without M5"
    and R6-6's resolution.
  * **R13-2 (major).** The numbers and causes in the commit message and documents:
    * "24% on a heavily loaded system" is the Animation Hitches run that TESTING calls disturbed,
      at the same system load as the 88% run;
    * "93% to 97%" leaves out a 91.7% run;
    * AVFoundation's M5 latency is 17 to 33 ms, not 17 to 21;
    * one AVFoundation "M5" arm spent about the first 3 s of its 10.7-s recording in a fixed 48 Hz
      display mode with no preference;
    * the only heavily loaded pair that has render data points the other way.
  * **R13-3 (minor).** "Every frame is then shown for the same time" in the public QVideoWidget
    documentation.
  * **R13-4 (minor).** The method statements are inaccurate, the committed tooling doesn't reproduce
    the full-screen method, and it has analysis bugs, one of which hid R13-1.
  * **R13-5 (minor).** Re-committing M5/M6: `finish.sh` would stop at the qtmultimedia push, whose
    lease is the pre-review value.
  * **R13-6 (nit).** Loose ends in TESTING.

---

## Earlier findings

| ID | Severity | Response | Verified at S6' | Status |
|---|---|---|---|---|
| R12-1 | minor | Fixed in round 12 | `run-suites.sh:4-7`: a new `mktemp -d`, or `QTMM_RESULTS`; refuses a non-empty directory; removes nothing | **Closed** |
| R12-2 | nit | Fixed in round 12 | `verify-states.sh:13-15` (index removed), `:26` (reconfigure), `:27-29` (kill -9 recovery), `:30-31` (traps after the check), `:44` (filter) | **Closed** |
| R12-3 | nit | Fixed | Test `tst_qvideowindow.cpp:222-225`; comment `qvideowindow.cpp:587-588`; negative check fails at :225; passes on cocoa and offscreen (my runs) | **Closed** |
| R12-4 | nit | Fixed (the "internal" residual this round) | `qvideowidget.cpp:40` | **Closed** |
| R9-4 | minor | `hasVariableRefreshRate()` true on the panel | TESTING "ProMotion panel" 1-2; S5/S6 logs "display with a variable refresh rate: true" | **Closed** |
| R10-2 | minor | Steps 1-5 run; 6-7 need a second display | README:201-231 | **Closed**, except the evidence problems of steps 4-5 (R13-1, R13-2) |
| R6-6 | minor | "Measured: doesn't keep the panel at 120 Hz" | README:224-225, :294-296; M5 document :65-66 | **Reopened** (R13-1): the runs cited didn't show the video; the one that did contradicts it for 4.5 s |
| R7-5 | minor | Two screens: doesn't apply to this setup | README:205, TESTING "Not run" | **Deferral accepted**, documented as a limitation (one display; the automated test skips) |

The display mode changes that hurt one AVFoundation arm (R13-4) also did something useful. When the
panel was switched to fixed 60 and 48 Hz modes, M5 reset the preference to 0 within the same
second, and set 24 again back in ProMotion. So R9-1's reset was seen on real hardware:
`l3-darwin-24-m5-2.probe.txt`, and `.qtlog.txt` 14:27:35.290 and 14:27:45.810. In
`l2-ffmpeg-24-m5-1` the stale 24 was paced at 30 for 2 ms (14:07:51.346 → .348). Worth a line in
TESTING.

---

## The evidence: what's solid, what isn't

**Render cadence** is the share of intervals between the probe's delivering display link callbacks
that are 41.7 ms (`qt.qpa.screen.updates`), over each whole run.

**Display cadence** comes from `cadence.py` on the trace.

FFmpeg, 24 fps, 120 Hz panel:

| run | layout | render, M5 | render, default | display, M5 | display, default |
|---|---|---|---|---|---|
| l3 run 1 | full screen | (no update requests during the recording) | 80.2% (978) | - | - (direct to display) |
| l3 run 2 | full screen, composited | 99.2% (783) | 91.2% (907) | 96.7% | 88.3% |
| c5 run 1 | child window | 99.0% (910) | 94.0% (14,135, 10 min) | 95.9% | (recording hung) |
| c5 run 2 | child window | 99.0% (1,990) | 81.3% (1,297) | 91.7% (not in TESTING) | (recording killed) |
| Hitches | | - (no Qt log) | - | 93.5% | 24.4% |
| c4 (Webex, load 300-385) | child window | 64.6% (last 28 s), 83 ms holds 7.4% | 77.6%, 83 ms holds 0.3% | - | - |

**Solid:**

* The mechanism does what M5 claims. With the preference, updates land on the 24 Hz grid (99%).
  Without it, FFmpeg's updates hop a refresh in stretches: `rcadt.py` shows 1 to 10 s bins at 58 to
  80% in every default run, and 94% over the 10 quiet minutes of `c5-ffmpeg-24-dflt-1`.
* The display adds a few % of uneven intervals in both arms. For example `c5-ffmpeg-24-m5-2`: render
  98.5%, display 91.7%, with only the probe on screen.
* The on-screen pair (run 2) favours M5. But the difference sits in the 2.5 s when another surface
  kept the display at 120 Hz (`cadseg.py`):

  | segment | default | M5 |
  |---|---|---|
  | during the burst | 63.3% | 90.0% |
  | outside it | 96.6 to 96.8% | 98.3 to 100% |

**Not solid:**

* The Hitches pair: TESTING itself says the template disturbed the measurement.
* The child-window display A/B: no default arm recorded.
* Heavy load: c4 is the only heavily loaded pair with render data. The arms weren't simultaneous,
  the M5 arm's probe was starved for minutes, and Webex was running. Even in the M5 arm's steady
  last 28 s, it has 64.6% on the grid and 7.4% of 83-ms holds, against 77.6% and 0.3%. That's what
  the grid does with a frame that misses its tick. It argues against "the more the delivery
  varies, the more M5 helps".
* No undisturbed M5 run sampled frames arriving just before a tick. The waits in the four M5
  FFmpeg runs are stable at 5, 33, 31→19 and 36 ms, so the cost of the "slip" limitation on screen
  is unmeasured.

**Latency** (request to delivery, including the render):

| backend | M5 | default |
|---|---|---|
| FFmpeg | 5 to 36 ms, as documented | 2 to 5 ms |
| AVFoundation, over its periods at 120 Hz with the preference (`l3-darwin-24-m5-2`: 17 ms over 81 requests, 33 ms over 509) | 17 to 33 ms, not 17 to 21 | about 9 ms |

**Commit to display** is about 24 ms or about 7 ms, in either arm. `c5-ffmpeg-24-m5-2`, with M5's
preference and the Display instrument alone, is 7.1 ms. So M5 adds nothing there.

---

## New findings

| ID | Severity | Title | Commit |
|---|---|---|---|
| R13-1 | major | Three of the four panel-rate arms didn't show the video during the recording; AVFoundation's one valid default run contradicts the conclusion and R6-6's resolution | docs, M5 message |
| R13-2 | major | The cadence and latency numbers in M5's message and the documents don't match the evidence, and attribute the difference to load | M5 message, docs |
| R13-3 | minor | "Every frame is then shown for the same time" in the public QVideoWidget documentation (and README "In short"); the comment's "refreshes at the video's rate anyway" | M5 |
| R13-4 | minor | Method statements contradicted by the recordings; committed tooling doesn't reproduce the full-screen method and has analysis bugs; display mode changes undisclosed; viewprobe child-mode destruction order | docs, tooling |
| R13-5 | minor | Re-committing M5/M6: README says "Done", `finish.sh`'s lease is stale and will be rejected, and `git add -- wip-cadisplaylink` sweeps in `release-build.sh` | tooling, README |
| R13-6 | nit | TESTING "Round 13 changes": unexplained new skips, volatile log paths, stale "panel not connected" | docs |

---

### R13-1: major: three of the four panel-rate arms didn't show the video

**Where:**

* TESTING:175-186 (the table and its conclusion).
* The M5 document :62-66 ("92.9% ... 98.6% ... 97.3% and 100%").
* README:224-225 ("Done: the panel drops with FFmpeg and AVFoundation ... doesn't keep it at 120 Hz
  (R6-6)"), and :294-296.
* `M5.txt:3-6`.

**Problem.** QVideoWindow requests an update for every frame while it's exposed
(`qvideowindow.cpp`, the end of `setVideoFrame()`). On cocoa every request that finds the link
paused logs "Resuming display link". In three of the four arms the table cites, the probe's
`qt.qpa.screen.updates` log stops 1.4 to 2.8 s after launch, before xctrace attached:

| run | Qt display link events | trace window | callbacks in it |
|---|---|---|---|
| `l3-ffmpeg-24-m5-1` (97.3%) | 14:13:05.030 - 14:13:06.394 (32) | 14:13:14.179 + 10.6 s | 0 |
| `l3-darwin-24-m5-1` (100.0%) | 14:21:43.2 - 14:21:44.55 (31) | 14:21:51.161 + 10.5 s | 0 |
| `l3-darwin-24-dflt-1` (98.6%) | 14:22:24.8 - 14:22:27.6 (70) | 14:22:33.412 + 10.7 s | 0 |
| `l3-ffmpeg-24-dflt-1` (92.9%) | 14:15:16 - 14:16:00, 24 per second | 14:15:25.5 + 10.7 s | 24/s throughout |

* Meanwhile the probe kept counting 24 frames per second (`videoFrameChanged`) with the same
  preference.
* The last event is always a normal "No pending update requests. Pausing", and nothing follows. So
  no request reached the platform: the window wasn't exposed.
* The most likely cause is the full-screen space not being shown. A lost update request in qtbase
  would look the same in these logs, and they can't rule it out.
* The same pattern ended the recordings of `lite-ffmpeg-24-m5-1`, `l2-darwin-24-*` and
  `c3-ffmpeg-24-dflt-1`.

What the three arms measured is a panel with nothing to show:

* `l3-darwin-24-m5-1` has 0 displayed surfaces, and 245 vsyncs all exactly 41.666 ms.
* The panel's slowest rate is 24 Hz (AppKit: maximum interval 0.041667 s). So for 24 fps content
  "time at 24 Hz" can't tell an idle panel from one following the video.
* Their "request to delivery" cells (36/44, 17/17, 8.5/9) come from the 29 to 68 requests before the
  recording.

The fourth arm is valid, but TESTING:165 says runs with other surfaces are left out, and it had 7
WebKit surfaces.

The valid evidence:

* **FFmpeg supports the claim.**
  * `l3-ffmpeg-24-dflt-1`: 92.9% at 24 Hz, full screen.
  * Run 2's segments with only the probe on screen (`seg.py`): default 93% at 41.7 ms over
    [0, 5) s; M5 100% over [0, 2.5) s.
* **AVFoundation contradicts it.** The one visible default run, `l3-darwin-24-dflt-2`, over [0, 4.5)
  s:
  * 107 probe surfaces and 1 unattributed, so nothing else on screen;
  * the panel spent 41% of the time at 8.3 ms intervals, 55% at 16.7 ms and 0% at 41.7 ms. The
    refresh pattern repeats every two video frames, which points at the probe itself.
  * After the other surface's burst, [7, 11) s: 79% at 41.7 ms.

  So "AVFDisplayLink's decode link doesn't keep it at 120 Hz" isn't established.
  * What the invalid runs do show: `l3-darwin-24-*-1` committed about 122 times a second with the
    panel at 24 Hz 98.6 to 100% of the time. So the decode link's own commits don't raise the
    panel's rate while the window isn't shown.
  * That's narrower than R6-6's question.

**Fix:**

* Drop or redo the three cells.
* State the FFmpeg conclusion on the valid runs. For AVFoundation, either re-measure or say what the
  one visible run shows. Put R6-6 back to open (a follow-up) in README:294-296 and the M5 document,
  and remove "and AVFoundation" and "(R6-6)" from README:224-225's "Done".
* Make it checkable:
  * `analyze.py` and `qtlog.py` should use only the trace window (`--toc` start-date and
    duration), and flag a run with no delivery in it;
  * the viewprobe should print `window.isExposed()` in its per-second line.
* For the panel-rate question, a 30 fps clip (M5: 30 on 120 Hz) separates "follows the content"
  (30 Hz) from "idle" (24 Hz).

**Resolved when** every panel-rate number comes from a recording in which the Qt log shows the
window updating, and README, the M5 document and `M5.txt` claim for AVFoundation only what those
runs show.

### R13-2: major: the cadence and latency numbers don't match the evidence

**Where:** `M5.txt:10-14` and `:34-38`; M5 document :67-72 and :87-90; README:285-292;
TESTING:193-207.

**Problem:**

* **"24% on a heavily loaded system"** (`M5.txt:12`), and "with a heavy one" (M5 document :70), is
  the Animation Hitches pair.
  * TESTING:169-171 says that template disturbed the measurement.
  * The system load average was 58-67 before and 33-38 after, the same as the "88%" run (60 before,
    60 after). What was heavy was the kernel trace.
  * Its default arm is a strict 33/50 alternation (83 and 81 intervals). The moderate runs show the
    same pattern in shorter stretches, which fits the frames' phase against the refresh, not load.
  * The one other heavily loaded pair (c4, render cadence) points the other way: 7.4% against 0.3%
    of 83-ms holds with M5.
  * So "The more the frames' delivery varies, the more often" (`M5.txt:10`), with M5 as the remedy,
    isn't supported for large variations.
* **"88% ... against 93% to 97%":**
  * The 88% is one 10-s run whose difference with M5 lies in the 2.5 s of another surface's burst
    (the table above).
  * The M5 range leaves out `c5-ffmpeg-24-m5-2`, the second child-window M5 run: 91.7%, with 91.7-
    and 133-ms holds. TESTING:197 lists only run 1.
* **The AVFoundation run-2 M5 arm (96.1%, TESTING:196; "92% to 96%", M5 document :72):** the
  display was in a fixed 48 Hz mode with M5's preference at 0.000 for about the first 3 s of the
  10.7-s recording.
  * The probe prints "(48.000 Hz)", preferredFrameRate 0.000.
  * The Qt log: "(default)" at 14:27:35.290, "(min=24…)" at 14:27:45.810.
  * The trace starts at 14:27:42.048, and its vsyncs are 20.8 ms until then.
  * At 48 Hz, 24 fps is even anyway.
* **AVFoundation latency "17 to 21 ms against 8.5 to 9 ms"** (`M5.txt:37-38`, README:292,
  TESTING:205, M5 document :89-90):
  * 17 comes from the 29 requests before `l3-darwin-24-m5-1`'s recording.
  * 21 is the median of `l3-darwin-24-m5-2`'s whole log, about 40% of which (401 of 991 requests)
    is at 60 and 48 Hz without the preference.
  * Over its 22 s at 120 Hz with the preference, the median is 33 ms (p10 17, p90 34, 509 requests).
  * The measured range is 17 to 33 ms.

**Evidence:**

* `cadence.py`, `cadseg.py`, `rcad.py` and `rcadt.py` outputs (above), and `phase.py`.
* The probe outputs' load lines.
* `l3-darwin-24-m5-2.{probe,qtlog}.txt` and its vsyncs.

**Fix.** Rewrite `M5.txt:3-14`, the M5 document's "Why" and TESTING item 2 with what holds. For
example:

  > ... so a frame arriving a little early or late is shown a refresh earlier or later, and 24 fps
  > video shows some frames for 33 or 50 ms instead of 41.7. With the FFmpeg backend on a 120 Hz
  > ProMotion panel, 80% to 94% of the window's updates were 41.7 ms apart, less in stretches and
  > while another window updated the display at 120 Hz, against 99% with this change; on screen, in
  > the one undisturbed pair, 88% against 97%. The AVFoundation backend's frames follow the display
  > and were about as even without it.

* The latency: "17 to 33 ms against 9 ms with AVFoundation".
* The trade-off paragraph should say what a slip looks like: "a frame that arrives after its tick
  waits for the next one, and the previous frame stays on screen for another frame interval".
  Under heavy load that was 7% of the updates in one run, as against 0.3% without.
* Drop "on a heavily loaded system", or say "while Instruments recorded a kernel trace".
* Add c5 run 2 (91.7%) to TESTING:197.
* Mark or drop the AVFoundation run-2 M5 row.
* Put the render-cadence numbers in TESTING: they're the strongest evidence for the decision.

**Resolved when** every number in `M5.txt`, the M5 document, README and TESTING matches a run as
recorded, and no causal claim (load) goes beyond the data.

### R13-3: minor: "Every frame is then shown for the same time"

**Where:**

* `qvideowidget.cpp:45-47` (public documentation);
* README:103-105 ("so that every frame is shown for the same time: such a panel refreshes at the
  video's rate anyway");
* `M5.txt:21-22`;
* `qvideowindow.cpp:557` and `:560-562`.

**Problem.** The QVideoWidget documentation promises something neither the design nor the
measurement gives:

* the compositor adds uneven intervals (with M5 and only the probe on screen, 91.7%);
* a frame that misses its tick holds the previous one for two frame intervals.

The sentence even contradicts its own next clause, which says a frame may be shown up to one frame
interval late. And the comment's "Such a display refreshes at the video's rate anyway while nothing
else changes" is contradicted for AVFoundation (R13-1). As intent, "Show every frame for the same
time" in a comment is acceptable. As documentation, it's a guarantee.

**Fix**, for example in the documentation:

> "The window is then updated at that rate, so that frames aren't shown a display refresh longer or
> shorter depending on when they arrive, but a frame may be shown up to one frame interval later
> than at the display's full rate."

In the comment: "Such a display may refresh at the video's rate anyway, but …". The same in README
"In short" and `M5.txt:21-22` ("… and frames aren't shown a refresh early or late").

The documentation change changes S5 and S6, so it needs the S5/S6 verification again. That's quick:
`verify-states.sh S5`, then the final-state suites M5 touches.

### R13-4: minor: method statements, tooling, undisclosed conditions

**Statements the recordings contradict:**

* **"The panel rate below is from the Display instrument alone (`light`)"** (TESTING:171). The l3
  runs recorded "Display, Core Animation Commits Instruments" (their `xctrace.log`, `measure2.sh`).
  * The committed `measure.sh` records `--instrument Display` only.
  * So `matrix.sh` doesn't reproduce the full-screen method, and it can't give "commits about 122
    times a second" (TESTING:186, README:295): `analyze.py` prints 0 commits/s for Display-only
    traces.
  * The c5 runs used 8 s recordings; `matrix.sh` uses 10.
  * No committed step makes or plays the 25 fps clip.
  * `analyze.py:2` still names `measure2.sh`.
  * `measure.sh` doesn't export `--toc`, which R13-1's fix needs.
* **"24 ms from commit to display where the Display instrument alone saw 7 ms"** (TESTING:170-171,
  `promotion/README.md:31`, `measure.sh:13`), blamed on the Hitches template. The recordings
  contradict this in both directions:
  * `c5-ffmpeg-24-m5-1`, Display alone: median 24.02 ms;
  * `darwin-24-m5-1`, Hitches: 7.57 ms.
  * The 24 ms mostly goes with the runs that had the other surface's burst, in either arm. Not
    always: `lite-ffmpeg-25-1` had one, with a 7.4 ms median.
* **"7.4 ms for a 25 fps clip ... with the Display instrument alone"** (TESTING:206-207).
  `lite-ffmpeg-25-1` recorded Display and Core Animation Commits. `c5-ffmpeg-24-m5-2` (Display
  alone, with M5's preference) gives 7.09 ms, which shows M5 adds no commit-to-display latency.
* **Display modes.** `QScreen::refreshRate()` (CGDisplayMode) read 60 or 48 Hz during several runs.
  None of this is mentioned. The one in `l3-darwin-24-m5-2` affects a table row (R13-2).

  | run | reading |
  |---|---|
  | `l2-ffmpeg-24-dflt-1`, `l2-ffmpeg-25-1` | 60 Hz throughout |
  | `l2-ffmpeg-24-m5-1` | 60 Hz for 15 of 29 s |
  | `l2-darwin-24-m5-1` | 60 Hz for 6 of 40 s |
  | `l3-darwin-24-m5-2` | 60 Hz for 10 s and 48 Hz for 8 s |
  | `l3-ffmpeg-25-1` | 60 Hz for 15 s |

**Analysis bugs:**

* `analyze.py:52-63` counts unattributed surfaces as the probe's frames: `l3-ffmpeg-24-m5-2` shows
  "439 frames, 55% at 8.3 ms", 197 of which are window-server framebuffers. The probe's own frames
  are 96.7% at 41.7 ms.
* `analyze.py:79-95` and `qtlog.py` use the whole probe run, not the recording. That's what hid
  R13-1.
* `cadence.py:26-28` drops intervals across frame-number gaps: `ffmpeg-24-m5-1` is 93.5% with its 5
  gaps dropped, 90.2% if they count as uneven. Report the gaps next to the percentage.

**The viewprobe.** In child mode, `QWindow parent` (`main.cpp:30`) is declared after
`QVideoWindow window` (`:20`) and becomes its QObject parent (`QWindow::setParent` calls
`QObject::setParent`). When `main()` returns, `parent` is destroyed first and deletes the stack
`window`: undefined behaviour at exit. `measure.sh` kills the probe with TERM, so no measurement was
affected. Declare `parent` first.

**Fix:**

* Correct the three statements.
* Say which job script produced which rows, or make `measure.sh`'s light mode record Core Animation
  Commits too (and export the toc).
* Record the display mode per run, or exclude runs where it changed.
* Fix the three analysis bugs and the declaration order.

### R13-5: minor: re-committing M5 and M6

**Where:** README:193-196, `finish.sh:17-20`, `qtbase-docs.txt`.

**Problem:**

* README:193 says the series is committed, signed and pushed ("Done"). The branch's M5 and M6 are
  the round 12 trees; `trees.txt` now lists S5'/S6'.
* `commit-series.sh` handles that correctly: it keeps M1-M4, resets to M4 and commits M5' and M6'.
* But `finish.sh:19-20` then pushes with `--force-with-lease=wip/cadisplaylink:89c28908b…`, the
  pre-review head. The fork is at `0e21dc1b35c1` (`git ls-remote fork`), so the push is rejected and
  `finish.sh` stops after committing, before the qtbase push and the qt5 pointers. It's a loud
  failure, not a wrong one.
* `git add -- wip-cadisplaylink` (`:14-15`) would also commit the untracked `release-build.sh`
  (outside this PR's scope, still being edited at 16:12). `__pycache__` is ignored
  (`.gitignore:41`).
* The docs commit would reuse round 12's message, "WIP: Record the qtmultimedia series and its
  review rounds".

**Fix:**

* Update README's step: M5 and M6 are re-committed.
* Set the lease to `0e21dc1b35c1cd89236874e2ebff46c63324ffa8` (or pass it in).
* Decide about `release-build.sh`: ignore it, or add it on purpose.
* Give the docs commit a message of its own ("… the ProMotion measurement and review round 13").

### R13-6: nit: TESTING loose ends

* **The FFmpeg 9 suite's new skips.** TESTING:226-227 gives "19 skipped", 3 more than before,
  without saying why. They're `swapAudioDevice_doesNotStopPlayback` ×3, "requires two audio output
  devices": this setup has one output. Not FFmpeg 9.
* **Log locations.** The round 13 logs are cited in `~/.claude/jobs/328d9a96/tmp/` (TESTING:221),
  which goes with the job. `ffmpeg9/` isn't cited at all. Copy the logs into the evidence directory.
* **TESTING:544** still says the R1-1 stall A/B wasn't run because the panel isn't connected. It is
  now; the reason is stale (qtbase item).
* **Unwrapped lines:** TESTING:122, :454, M5 document :116-117, and several script lines over 100
  columns.

---

## Other checks, found fine

* **The ownership rule** is unchanged. R12-3's step covers the "someone else sets exactly v after
  the window's own stopped" row of my round 12 transition table. The other rows keep their
  existing tests.
* **A/B method.** The default arm sets 120 first. The Qt logs show the link never left the default
  range in those arms ("frame interval 0.00833333", no "Setting display link frame rate"). So it's
  equivalent to no preference, and M5 leaves it alone.
* **FFmpeg 9 rebuild.**
  * `tst_qvideoframebackend` 22 + 1 skipped on both backends.
  * `tst_qmediaplayerbackend` FFmpeg: 290 passed, 2 failed, both `server.listen()`.
  * The linker warnings (dylibs built for macOS 26 against a 14.4 target) are local.
* **Line counts and messages.** `M5.txt` is 62 lines, with no line over 72 and the Change-Id
  unchanged. The M5 document's file list still matches the S5 diff.
* **What's committed in qtbase:** `__pycache__` is ignored. The promotion scripts and the viewprobe
  change are sources; the evidence directory is outside git, as TESTING says.

---

## Verdict: REQUEST CHANGES

Severity counts: blocker 0, major 2, minor 3, nit 1.

The code of M5 (S5 `824627c8497b`) and M6 (S6 `a8e69274ace7`) is right. R12-3 and R12-4 are closed.

The measurement supports the user's decision for FFmpeg under ordinary conditions: the window's
updates go from 80-94% to 99% on the grid, and on screen from 88% to 97% in the one clean pair.

The documents that go to Gerrit with M5 (`M5.txt`) and the public QVideoWidget documentation need to
say what the recordings show:

* the panel-rate arms that didn't show the video;
* AVFoundation's contradicting run, and R6-6 reopened;
* the numbers and the load attribution;
* the latency for AVFoundation;
* the slip.

These are text changes, except R13-3's documentation sentence, which changes S5/S6 and needs the
quick re-verification. No new measurement is needed to fix R13-2. R13-1 needs either a new
AVFoundation measurement or a statement that it's open. R7-5's deferral stays accepted as a
documented limitation.

Open:

- R13-1: major: three of the four panel-rate arms (TESTING:180-181) had no update request during the recording (the Qt log stops 1.4-2.8 s after launch), so they measured an idle 24 Hz panel; AVFoundation's one visible default run had the panel at 8.3/16.7 ms intervals for 4.5 s with nothing else on screen; R6-6 reopened (docs, M5 message)
- R13-2: major: "24% on a heavily loaded system" is the disturbed Hitches run at normal system load; "93% to 97%" omits 91.7%; one AVFoundation M5 arm spent its first ~3 s at 48 Hz without a preference; AVFoundation latency is 17-33 ms, not 17-21; the heavy-load pair with render data points the other way (M5 message, docs)
- R13-3: minor: "Every frame is then shown for the same time" in the QVideoWidget docs (and README, M5.txt); the comment's "refreshes at the video's rate anyway" (M5)
- R13-4: minor: "Display instrument alone" wrong for l3 and the 25 fps run; the 24-vs-7 ms commit-to-display blamed on Hitches is contradicted; committed measure.sh doesn't reproduce the l3 method; display mode changes undisclosed; analyze.py counts unattributed surfaces and uses whole logs; cadence.py drops gaps; viewprobe child-mode destruction order (docs, tooling)
- R13-5: minor: README says the series is committed; finish.sh's force-with-lease expects 89c28908b but the fork is at 0e21dc1b3; `git add -- wip-cadisplaylink` sweeps in release-build.sh; the docs commit reuses round 12's message (tooling, README)
- R13-6: nit: 3 new skips unexplained (one audio output), job-directory log paths, stale "panel not connected", long lines (docs)
