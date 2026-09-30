# Round 14 review: qtmultimedia series (M1 to M6)

Reviewer: qt-cadisplaylink-pr-reviewer (independent, strict)
Repo: `qt5/qtmultimedia`, base upstream `635067497`. The committed branch is still round 12's (M1-M4
stay; M5 and M6 are to be committed again); the worktree is at S6. Line numbers are at S6 (code)
or at the current, uncommitted documents.

This round checks the author's response to round 13 (`round-13-author.md`).

| # | Tree | This round |
|---|---|---|
| M1-M4 | S1-S4, unchanged | none |
| M5 | S5 `d7b28d110a2f` (was `824627c8497b`) | R13-3: the QVideoWidget documentation sentence and the comment |
| M6 | S6 `395ad6fdce8e` (was `a8e69274ace7`) | none (same `git patch-id --stable`, `00e953ac…`) |

## How I checked

* **Trees.**
  * `refs/cadisplaylink/series/S1..S6` are trees and equal `trees.txt`.
  * The worktree equals S6: `git hash-object --stdin-paths` (no `-w`), 0 of 3244 blobs differ.
    Checked at the start and at the end.
  * The S5 and S6 deltas are identical apart from index lines and hunk offsets: 2 files, +16 -14,
    comments only. M6's patch-id is unchanged. `diff-tree --check` is clean.
  * With comments stripped, `qvideowindow.cpp` and `qvideowidget.cpp` are code-identical to round
    12's S5 (`7fb32794b550`). Since round 12, the only other change is R12-3's test step.
* **Messages.** `M1..M6.txt`, `qtbase-docs.txt` and `qt5-pointers.txt`: at most 72 columns, line 2
  blank, 6 distinct Change-Ids (M5's unchanged).
* **Build and tests.**
  * `cmake --build qtmm-build --target tst_qvideowindow tst_qvideowidget` was a no-op: the
    libraries (17:20) and test binaries (17:21-17:22) are newer than the restored sources
    (17:17:51).
  * I ran `tst_qvideowindow` 7/7, `tst_qvideowidget` 8 passed + 1 skipped, and
    `tst_qmultimediautils` 307.
  * I compiled the committed viewprobe in `/tmp/rv14/vp` (no warnings) and didn't run it.
* **Logs.** Every log in `logs-round13/states13b/` and `m5fix-b/`: totals, the two failures, build
  warnings, recompiles, and the S5 leak probe's output and dump.
* **The measurement.**
  * The committed `analyze.py`, `cadence.py` and `qtlog.py`, copied to `/tmp/rv14/tools`, were run
    on every run through `/tmp/rv14/an/` (symlinks to the evidence), with
    `PYTHONDONTWRITEBYTECODE`.
  * I compared every number in TESTING, README, the M5 document and `M5.txt` with their output, and
    with my round 13 scripts (`/tmp/rv13/`).
  * The evidence files are unchanged since round 13 (no new exports).
* **Scripts.** I read `measure.sh`, `matrix.sh`, the promotion README, `finish.sh`,
  `commit-series.sh` and the viewprobe.
* **Disclosure.** Read-only git with `GIT_OPTIONAL_LOCKS=0`. No Instruments, no viewprobe run,
  nothing in `qt5-build-release`, `qt5-build-release-ninja` or `~/Qt`.

---

## Summary

Every round 13 finding is fixed, and the fixes are right.

* **The code (R13-3).** The QVideoWidget documentation now describes the mechanism, not a guarantee.
  The comment says the panel "may" refresh at the video's rate anyway.
* **The evidence (R13-1, R13-2).** TESTING's measurement section now uses only runs whose window was
  shown, and marks and explains the others.
  * The committed tools reproduce every number:
    * render cadence: FFmpeg 78.9 to 94.0% without, 98.2 to 100% with;
    * on screen: 88.3% against 96.7%, the difference lying in the burst;
    * the latencies, and the heavy-load holds (7.6% against 0.3%).
  * The panel-rate claims are limited to FFmpeg. R6-6 is open again, with the AVFoundation run that
    contradicts it.
* **Tooling (R13-4).** The committed tools now cut the Qt log to the recording, flag NOT SHOWN,
  separate the probe's frames from unattributed surfaces, and report the gaps. The viewprobe prints
  whether its window is exposed and no longer deletes a stack window.
* **Recommitting (R13-5).** The procedure now works: `commit-series.sh` keeps M1-M4, and
  `finish.sh`'s lease is the fork's actual head (`0e21dc1b35c1`).

What's left is two nits: a few residual numbers and method phrases (R14-1), and bookkeeping (R14-2).

**The `destruction` failures in the re-verification: the attribution holds.**

* Both are the setup's `QTRY_COMPARE_GT(mediaPlayer->position(), 0)` at
  `tst_qmediaplayerbackend.cpp:5078`: "timeout (5000 ms) was too short, 5100 ms would have been
  sufficient".
* The failing row differs: `MVA_setSourceNull` at S5, `VAM_setPosition` in one of three S6 runs.
* The test uses a QVideoSink, not a QVideoWindow, so M5's code doesn't run. Without a window, M6's
  decode link stays on the main screen, as before.
* The compiled library code is the same as in rounds 11 to 13:
  * the same function passed all 80 at S5 in rounds 11 and 13, and at S6 in round 13;
  * in round 11's full final-state run it lost 2 rows to the same slow start.
* It's the playback-start family the upstream A/B records: 3 of 234 upstream starts, and 5 of 312
  series starts, over 5 s.
* Counting the series-state and final-state runs since round 8 (S1 to S4, then S5 and S6 in rounds
  11 and 13): 8 slow starts in 12 runs of 78 rows, about 0.9%. That's the same order of magnitude.

---

## Round 13 findings

| ID | Severity | Response | Verified | Status |
|---|---|---|---|---|
| R13-1 | major | Fixed | See below | **Closed** |
| R13-2 | major | Fixed | See below | **Closed**, residuals in R14-1 |
| R13-3 | minor | Fixed | See below | **Closed** |
| R13-4 | minor | Fixed | See below | **Closed**, residuals in R14-1 |
| R13-5 | minor | Fixed | See below | **Closed** |
| R13-6 | nit | Fixed | See below | **Closed**, with a correction to my own finding |

**R13-1.**

* TESTING:186-196 lists the three arms as left out, with the reason. The panel-rate table
  (:198-215) keeps only `l3-ffmpeg-24-dflt-1` and segments with only the probe on screen. The
  segment figures match mine, apart from binning.
* `analyze.py` and `qtlog.py` mark `l3-ffmpeg-24-m5-1`, `l3-darwin-24-m5-1`, `l3-darwin-24-dflt-1`
  and `c4-ffmpeg-24-m5-1` NOT SHOWN, which is right.
* R6-6 is reopened: README:202-208, :223-230 and :300-304, the M5 document :62-66 and its Limits.
  `M5.txt:13-15` claims the panel rate for FFmpeg only.

**R13-2.** Every number matches the committed tools' output (M5 against default):

| | FFmpeg | AVFoundation |
|---|---|---|
| Render cadence | `l3` run 2: 100.0 against 90.2; `c5`: 100.0 and 98.2 against 94.0 and 81.3 (whole logs); `l3` run 1 default: 78.9 | 99.6 against 96.5 |
| On screen | 96.7 (96.3) against 88.3 (87.9); `c5`: 95.9 and 91.7; Hitches: 93.5 (90.2) against 24.4 (24.2) | 96.1 against 90.5 |
| Waits | 5, 33 and 19 ms against 6 and 4 | 17 to 33 against 9 |

`c4`'s 64.4% and 7.6% are the last 28 s of its log, which I reproduced exactly. "Heavily loaded" is
gone, and TESTING:245-247 says what differed in the Hitches pair.

**R13-3.** `qvideowidget.cpp:45-48` and `qvideowindow.cpp:557-563`. README:103-106 and
`M5.txt:21-23` match.

**R13-4.**

* The run-groups table (TESTING:164-169) matches each run's `xctrace.log`, and the
  commit-to-display paragraph (:258-260) is right.
* `measure.sh` light/display/hitches are as described, and it exports the toc and the commit table.
* `analyze.py:82-93` counts only labelled probe frames. `cadence.py` reports both ways.
* The viewprobe declares `parent` first, at `main.cpp:21`.
* Residuals: README:224, and the commit-rate figure (R14-1).

**R13-5.**

* README:193-197 is right.
* `finish.sh:18-22`: the lease is `0e21dc1b35c1…`, and `git ls-remote fork` shows that head.
* `commit-series.sh` would stop matching at M5, reset to M4 (`aae82cabd`), and commit S5 and S6.
* `release-build.sh` is committed on purpose, and `qtbase-docs.txt` says it's not part of the PR.
* The messages are new.

**R13-6.**

* TESTING:282-284 explains the skips, and :276 cites `logs-round13/`. The R1-1 line (:613-615) is
  updated.
* **Correction:** my R13-6 note about TESTING:122 and :454 was wrong. `awk` counted bytes; the lines
  are 99 characters (`…` and `≈` take several bytes).

**Earlier deferrals.**

* R6-6 is open again as a documented follow-up. It's about AVFoundation's decode link, which ran at
  its screen's maximum rate upstream too (a main-screen CADisplayLink on macOS 27), so it's not a
  regression. Acceptable for Gerrit.
* R7-5 (two screens) stays accepted as a documented limitation.

**The NOT SHOWN cause.**

* "The window wasn't exposed" (TESTING:190) is right, by elimination.
  * The logs end with a normal "No pending … Pausing". After that, any request would have had to
    resume the link, and every path that does logs something: resume, not online, nested loop, or
    another screen's link.
  * Nothing followed, so no request came. The only path that sends none without logging is
    `setVideoFrame()`'s `if (d->isExposed)`.
* Whether the full-screen space wasn't on the display, or Qt missed an expose event after the
  transition (a pre-existing cocoa matter, not this series), these logs can't tell.
* The new "exposed" print reports Qt's view, so only a look at the screen would separate the two.
  The runs are invalid either way. No finding.

---

## New findings

| ID | Severity | Title | Commit |
|---|---|---|---|
| R14-1 | nit | Residual numbers and method phrases after R13-2 and R13-4 | M5 message, docs, tooling |
| R14-2 | nit | Bookkeeping: stale round range, M5 document's display, series-state trees, run-groups table, docs commit message | docs |

### R14-1: nit: residual numbers and method phrases

* **README:224** still says `measure.sh` records "the Display instrument alone". Its default,
  `light`, now records Display and Core Animation Commits (`measure.sh:12-13`, `:36-40`).
* **"commits about 122 times a second"** (TESTING:214, README:301).
  * The number is right: 121.5 to 122.1 in the `l3` AVFoundation runs, from their
    `coreanimation-commit-interval` tables.
  * But no committed tool computes it any more: the rewritten `analyze.py` dropped the commits/s
    column, and `measure.sh` still exports the table. Put the column back, or name the source.
* **FFmpeg's default wait "4 to 6 ms"** (`M5.txt:40`, README:296, M5 document :90, TESTING:254-255)
  leaves out `c5` run 2: 3.0 ms over its whole log (`qtlog.py`). The render table uses that same
  whole log (81.3%). It should read "3 to 6".
* **TESTING:261-262**: "a slip's cost on screen is only measured in `c4`".
  * `c4-ffmpeg-24-m5-1` is NOT SHOWN during its recording; its 7.6% comes from its Qt log after the
    recording.
  * So the cost was measured on the render side only, never on screen.
* **TESTING:225** "(48 and 60 Hz modes for part of it)": inside the recording it's 48 Hz only, for
  3.8 s.
* **TESTING:241** "79% to 94% over whole runs": the `l3` figures are the recordings'.

### R14-2: nit: bookkeeping

* **README:81** still says "(review rounds 4 to 12)".
* **The M5 document's "Tests"** is still written for the G95SC:
  * :117 "The display here has a fixed refresh rate";
  * :142 `_isOnlySetForVariableRefreshRate` "none here".

  On the panel the tests take the variable path: they log "variable refresh rate: true", and
  `_isResetWhenItNoLongerApplies` skips its fixed-display block.
* **TESTING "Suites on the final state" (:20) and "Series states" (:460-476)** still name round 11's
  S5 `7fb32794b550` and S6 `f4801ada7da2`. Add one sentence: the current S5/S6 have the same
  library code (comments only since; the test gained R12-3's step), which is why only the suites M5
  touches were rerun.
* **The run-groups table** (TESTING:164-169) doesn't list `c4-*` (Display alone, 8 s, child window),
  which item 2 cites.
* **`qtbase-docs.txt:10`** says "Review round 13 and its response". The commit will carry round 14
  too.

---

## Other checks, found fine

* **The comment** (`qvideowindow.cpp:557-563`) is accurate:
  * "may refresh at the video's rate anyway";
  * "without a preference the window renders a frame at the first display link callback after it
    arrives".

  The code is unchanged.
* **The documentation sentence** matches the design:
  * with every frame arriving before its tick, the window updates on the grid;
  * the lateness clause covers the grid's wait.

  The slip is in the commit message and README. That's enough, since the documentation already
  says a frame may be shown up to one interval late.
* **`M5.txt`** reads as a Qt commit message: problem, then change, then cost. Every number has a
  run behind it.
* **Tools.**
  * `trace_window()` parses the toc's offset-aware start date, and the Qt log's local times in the
    same timezone.
  * The duplicate zero-length vsync intervals add no time.
  * `matrix.sh`'s arguments are shifted correctly (backends from the 7th).
  * The README makes the 25 and 30 fps clips.
* **Re-verification logs.**
  * S5 build: 0 warnings in series files. `qvideowindow.cpp` and `qvideowidget.cpp` were
    recompiled.
  * Leak probe at 17:16: 20 players with a frame; the dump has "All zones" and no
    `DisplayLinkObserver` or `CADisplayLink`.
  * S6: `tst_qvideoframebackend` 22 + 1 on both backends.
* **Recommitting.** `finish.sh`'s whole flow works for this state: the series, the docs commit
  (with the round 13 and 14 review files), the forced push under the right lease, the qtbase push,
  and the qt5 pointers.

---

## Verdict: APPROVE

Severity counts: blocker 0, major 0, minor 0, nit 2.

M5 (S5 `d7b28d110a2f`) and M6 (S6 `395ad6fdce8e`) are ready for Gerrit, with the rest of the
series:

* the ProMotion session the round 10 and 12 approvals waited for has run;
* M5's rationale and cost are now stated as measured;
* R6-6 is a documented follow-up;
* R7-5 is a documented limitation.

The nits can be fixed in the documents at any time; only R14-1's "3 to 6" touches `M5.txt`, and it
doesn't change a tree.

Committing and pushing is `finish.sh`, with the user at the machine (signing).

Open, not blocking:

- R14-1: nit: README:224 "Display instrument alone" vs measure.sh's light default; the 122 commits/s isn't computed by any committed tool; FFmpeg's default wait is 3 to 6 ms (c5 run 2 omitted) in M5.txt, README, the M5 document and TESTING; "a slip's cost on screen" was measured on the render side only; TESTING:225 and :241 wording (docs, M5 message, tooling)
- R14-2: nit: README:81 round range; the M5 document's Tests intro still describes a fixed-rate display; TESTING's series-state and final-state sections name round 11's trees without saying the code is unchanged; c4 missing from the run-groups table; qtbase-docs.txt says round 13 only (docs)
