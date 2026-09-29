# Round 12 review: qtmultimedia series (M1 to M6)

Reviewer: qt-cadisplaylink-pr-reviewer (independent, strict)
Repo: `qt5/qtmultimedia`, base upstream `635067497`. The series is still uncommitted (signing blocked).
Its trees are kept by `refs/cadisplaylink/series/S1..S6` and listed in
`pr/qtmultimedia-series/trees.txt`. Line numbers are at S6 (code) or at the current documents.

This is a confirmation round after my round 11 APPROVE (minor R11-1 to R11-3, nits R11-4, R11-5).

| # | Tree | Subject | Round 11 items |
|---|---|---|---|
| M1 | S1 `47653cfd479b` | darwin: Don't leak the display link of AVFDisplayLink | none (unchanged) |
| M2 | S2 `e4ea5041e0f5` | darwin: Keep polling for video frames while menus and dialogs are open | none (unchanged) |
| M3 | S3 `dcbc502d19c3` | darwin: Stop using the deprecated CVDisplayLink in AVFDisplayLink | none (unchanged) |
| M4 | S4 `84212c21c771` | Report the stream frame rate of played video frames | none (unchanged) |
| M5 | S5 `7fb32794b550` (was `9d6582f3ca7b`) | QVideoWindow: Let the display refresh at the video's frame rate | R11-1, R11-2, R11-4, R11-5 |
| M6 | S6 `f4801ada7da2` (was `80569af10b23`) | darwin: Poll for video frames in sync with the display the video is on | none (patch identical apart from one context line) |

## How I checked

* **Trees, refs, working tree.**
  * `refs/cadisplaylink/series/S1..S6` (type tree) equal `trees.txt`. S1 to S4 are unchanged since
    round 8 (`/tmp/mm/series4-trees.txt` to `series7-trees.txt`).
  * The working tree equals S6: `git hash-object --stdin-paths` (no `-w`) over S6's 3244 blobs, 0
    differ. `git status` shows only the two untracked `qvideowindow` test files.
  * Old S5 against new S5 (`git diff-tree -p 9d6582f3ca7b S5`): 5 files. Old S6 against new S6 is the
    same delta, apart from hunk offsets.
  * M6's patch, old against new, differs only in one context line (the line M5 changed).
  * `git diff-tree --check` is clean on all six patches. No added line is over 100 columns.
* **Messages.**
  * `M1..M6.txt`: every line is at most 72 columns, line 2 is blank, and there are 6 distinct
    Change-Ids, each after a blank line. `qtbase-docs.txt` and `qt5-pointers.txt` pass the same checks.
  * The author updated `/tmp/mm/s7-5.txt` in step with `M5.txt`, so I checked the M5 change against
    my round 11 quotes: the only change is "(unless it's the same value)" (`M5.txt:40`).
* **Code.**
  * I re-derived `exactRatesToPlayAt()`, the new `QCOMPARE_GT`, the three unit rows, and the
    else-branch of the ownership rule.
  * `/tmp/rv12/rates.cpp` simulates the author's exact S6 test code against the exact S6
    `qVideoPreferredFrameRate()`, including qtbase's float refresh rate and float or double playback
    rates.
  * `/tmp/rv12/owner.cpp` replays `_leavesAnotherPreferenceAlone` against the ownership rule, with
    and without the else-branch.
* **Scripts.**
  * I read all six scripts, and ran the real `verify-states.sh` and `run-suites.sh` in a scratch
    repository (`/tmp/rv12/vs`), with `cmake`, the test binaries and `leak.sh` stubbed.
  * In that setup I killed `verify-states.sh` mid-build with TERM and with SIGKILL.
  * `/tmp/rv12/trap/` holds zsh trap tests: TERM, HUP and INT, sent to the process only and to the
    process group, including a second INT during the restore.
* **Evidence, read only.**
  * The logs: `/tmp/qtmm-results-s11/`, `/tmp/mm/states11/`, `/tmp/mm/r11/`, `/tmp/mm/states8/`.
  * The leak probe outputs, `probes/qtmultimedia/leakprobe/build/{S5,final}.{out,heap}`.
  * `cmp` of the installed libraries against `/tmp/ab/{base,r11}`, and the mtimes of the sources,
    test binaries and libraries.
  * The trees of the 11 qtbase and qtdeclarative series commits (`git log --format=%T` in
    `qt5-series/`), compared with `/tmp/r2/series-trees.txt` and `decl-trees.txt`.
* **Disclosure.**
  * qtmultimedia, qtbase and qt5-series: read-only git with `GIT_OPTIONAL_LOCKS=0`, and
    `hash-object` without `-w`. I didn't rerun `%G?` this round, which would run ac-sign.
  * `qtmm-build` and `qt5-build-nofw`: only `stat`, `find` and `cmp`. Nothing built or run there, or
    in the qtmultimedia worktree.
  * I ran my round 11 builds of the vrr probe and `cgrate` (`/tmp/rv11/`). They read display
    properties and open no window.

---

## Summary

The round 11 changes are correct and complete in the code:

* **R11-1.** `exactRatesToPlayAt()` now derives its rates from the actual refresh rate, as qreal.
  * The simulation covers 97,651 float refresh rates from 23.50 to 1000.00 Hz, with float and double
    playback rates. `_isSetDuringPlayback` and `_isResetWhenPaused` always get a non-zero
    expectation. `_followsPlaybackRate` always gets two different non-zero ones.
  * The M5 document's examples are right: 24 and 30 at 240 Hz, 30 and 20 at 60, 24 and 18 at 144,
    29.97 and 19.98 at 59.94.
  * The new `QCOMPARE_GT` makes `_isOnlySetForVariableRefreshRate` unable to pass vacuously on a
    variable display.
  * The three unit rows would fail with round 10's symmetric rule, by derivation: 30 fps at 59.94 Hz
    and 24 fps at 119.88 Hz both have a multiple of 0.999, which the symmetric rule accepted.
* **R11-2.** The QVideoWidget documentation mentions the whole multiple, and no longer says "its
  window's".
* **R11-5.** The else-branch in `setVideoFrame()` is correct for every transition. But no test fails
  without it (R12-3).

The recorded evidence is honest:

* The final-state table, the mock totals and the leak probe match the logs and the heap dumps.
* The finiteLoops A/B logs show 5 interleaved runs per side, each side failing one fast-rate row
  once. They are darwin runs: none has the FFmpeg plugin's startup lines, which every FFmpeg log
  has.
* The series libraries were reinstalled after the A/B: the installed files equal `/tmp/ab/r11`.
* The S5 row matches `/tmp/mm/states11/` and `leakprobe/build/S5.*`.
* The final run used S6: all 24 series files were rewritten at 06:19:31-32 by the restore, the
  build then compiled every series source (166 compile steps, 0 warnings in series files), every
  test binary is newer than its source, and nothing has changed since.
* The coordinator's correction of the `destruction` note (78 rows plus init and cleanup) is right.
  The same error was in my round 10 and 11 reviews (see "Corrections").

The durable scripts are self-contained: no `/tmp/mm` or job-directory paths, and `timeout` is
`/usr/bin/timeout` on macOS 27. They work: in the scratch repository, `verify-states.sh`
materializes each state, removes the files a state lacks, restores S6 and checks its tree.

* It restores on TERM, INT and HUP, whether sent to the process or the process group. A TERM sent to
  the script alone waits for the running child to finish first, so no half-built state is left.
* Findings:
  * **R12-1 (minor).** `run-suites.sh` runs `rm -rf` on the directory named by the environment
    variable `OUT`, a generic name. Demonstrated.
  * **R12-2 (nit).** After a `kill -9` there's no documented way back: the worktree stays at the
    intermediate state and the script refuses to rerun. Plus small robustness items.

The rest is documentation: **R12-4 (nit)**. Some of R11-5's bookkeeping items were silently left
undone.

**Environment change.** At about 08:55 the only display was the built-in ProMotion panel:

* AppKit: "max 120 fps, refresh interval min 0.008333 s, max 0.041667 s -> variable".
* CoreGraphics: 120.000 Hz, main display.

So README step 1 now gives its expected result, and the deferred ProMotion session can run now
(see the verdict).

---

## Round 11 findings

| ID | Round 11 severity | Response | Verified at S6 | Status |
|---|---|---|---|---|
| R11-1 | minor | Fixed | Test code: `tst_qvideoframebackend.cpp:456-472` (qreal rates, bounds 12.5 and 50; the edges are in "Other checks") and `:642-647`. Unit rows: `tst_qmultimediautils.cpp:168-171`, passing in `/tmp/mm/r11/`, `/tmp/mm/states11/` and `/tmp/qtmm-results-s11/`. Docs: M5 document `:22-23`, README `:280-281`. viewprobe: `main.cpp:39-41` prints the refresh rate with `%.3f`. Simulation above: 0 failures. | **Closed.** TESTING:135 credits my round 11 simulation, which modelled my variant (lower bound 13). The exact code is now confirmed by `/tmp/rv12/rates.cpp` (R12-4). |
| R11-2 | minor | Fixed | `qvideowidget.cpp:39-46`: "the window the widget shows the video in asks for the rate …, or a whole multiple of it" | **Closed.** One-word residual: "internal" would rule out reading it as the top-level window (R12-4). |
| R11-3 | minor | Fixed | M1 to M6 documents `:7` give the current trees and `trees.txt`. README:279 says "about one frame in 1000". TESTING's probe paths are `probes/qtmultimedia/`. `verify/` has the four scripts, with no volatile paths. This round's logs are named the way those scripts name them (`S5-<test>-<backend>.log`, `<test>-<backend>.log`, `leakprobe/build/<label>.*`). README:186-188: I re-checked all 11 qtbase and qtdeclarative trees against the recorded lists; they're equal. | **Closed.** Residual: TESTING:15 still names `/tmp/ab/swap.sh`; README:236 names `verify/ab-swap.sh` (R12-4). |
| R11-4 | nit | Fixed | `tst_qmultimediautils.cpp:166-167`. No added line is over 100 columns in any patch. | **Closed.** |
| R11-5 | nit | "Fixed" | viewprobe `main.cpp:28` (context `&window`). `run-suites.sh:18-23` names logs from `$1-$2` without `shift`; the s11 mock logs are distinct. `qtbase-docs.txt:5-7`. `count.sh:4` writes under `build/` (`.gitignore:333`). "(unless it's the same value)": `qvideowindow.cpp:579`, `M5.txt:40`. Else-branch: `:584-586`. Test step: `tst_qvideowindow.cpp:222-226`. `finish.sh:7-10`, `commit-series.sh:7`. | **Closed except:** (a) the bookkeeping items weren't done, and the response doesn't say so: README:96, M5 document `:10` and `:98-100`, README step 5's unnamed 25 fps file; (b) the M5 document `:35-38` keeps the old over-claim. Both in R12-4. (c) The new test step doesn't exercise the else-branch (R12-3). |
| R6-6, R7-5 | minor | Deferred to the ProMotion and two-screen session | README:195-222 | Still accepted, with the same condition: M5 doesn't go to Gerrit before that session. The panel is connected now (see the verdict). |

### R11-5's else-branch: every transition

"own" is `m_preferredFrameRate`, "current" is `QWindow::preferredFrameRate()`, and v is this
frame's value. The rule (`qvideowindow.cpp:580-586`):

* if `current == 0 || current == own`: write v, and set own to v;
* otherwise: set own to 0.

| Before the frame | Result | Changed by the else-branch? |
|---|---|---|
| none set, or reset to 0 by anyone | writes v; own = v | no |
| the window's own value in effect | writes v (new screen or playback rate, or 0 once it stops applying) | no |
| someone else's P, own 0 (set before) | left alone | no |
| someone else's P, set after the window's own v | left alone; own becomes 0 at the first frame | yes: own no longer goes stale |
| as above, then they set exactly v | left alone, also once the preference stops applying (before, it was taken for the window's own and reset) | yes: the point of the change |
| as above, then they reset to 0 | the window writes its value again | no |
| someone else sets exactly v while the window's own v is in effect, with no frame in between | taken for the window's own (inherent: QWindow emits nothing for an unchanged value) | no; "(unless it's the same value)" says so |

---

## Corrections to my earlier rounds

My round 10 review (`:418`) and round 11 review (`:457`) said "80 `destruction` rows". That's wrong.

* `destruction_doesNotDeadlock_afterMediaPlayerCall` has 78 rows: 6 orders (AMV, AVM, MAV, MVA,
  VAM, VMA) × 13 calls (none, pause, setAudioOutput, setAudioOutput_stop, setPlaybackRate,
  setPosition, setPosition_setPosition, setSource, setSourceNull, setVideoSink, setVideoSink_stop,
  stop, stop_play).
* QtTest's "80 passed" includes `initTestCase` and `cleanupTestCase`: 78 distinct row names in
  `S5-tst_qmediaplayerbackend-darwin.log`.
* The coordinator's correction (TESTING:287-290, `round-10-author.md:18`) is accurate. The table
  rows are consistent with it:
  * S1 and S5: 80 passed;
  * S2: 78 passed + 2 failed;
  * S3 and S4: 79 passed + 1 failed (`/tmp/mm/states8/`, `/tmp/mm/states11/`).

  Accepted as fixed.

---

## New findings

| ID | Severity | Title | Commit |
|---|---|---|---|
| R12-1 | minor | `run-suites.sh` deletes the directory named by the environment's `OUT` | tooling |
| R12-2 | nit | `verify-states.sh`: no documented recovery after `kill -9`, traps armed before the check, and small robustness items in it and the leak probe scripts | tooling |
| R12-3 | nit | R11-5's else-branch has no test that fails without it | M5 |
| R12-4 | nit | Document residuals: R11-5 bookkeeping not done or acknowledged, the M5 document's ownership sentence, TESTING:15 and :135, "internal" in the QVideoWidget docs, unwrapped lines | docs, M5 |

---

### R12-1: minor: `run-suites.sh` deletes the directory named by the environment's `OUT`

**Where:** `pr/qtmultimedia-series/verify/run-suites.sh:4`:

```zsh
OUT=${OUT:-${TMPDIR:-/tmp}/qtmm-results}; rm -rf $OUT; mkdir -p $OUT
```

**Problem:**

* `OUT` is a generic variable name, and toolchains export it. AOSP's `lunch`, for example, exports
  `OUT` as the product output directory.
* Anyone whose shell already has `OUT` set loses that directory when running the durable
  regression script. The script is meant to be rerun before Gerrit, possibly by the user at the
  machine.
* `verify-states.sh:9` uses the same variable but only writes logs into it, which is messy but not
  destructive.

**Evidence:** scratch run, with `cmake` and the tests stubbed:

```
$ ls /tmp/rv12/vs/precious
keep.txt
$ OUT=/tmp/rv12/vs/precious QT5_REPO=/tmp/rv12/vs/qt5 PATH=/tmp/rv12/vs/bin:$PATH .../run-suites.sh
...
$ ls /tmp/rv12/vs/precious
build.log  tst_qmediaplayer-mock.log  ...        (keep.txt is gone)
```

**Fix:**

* Use a specific name in both scripts, for example `QTMM_RESULTS_DIR` and `QTMM_STATES_DIR`.
* Don't `rm -rf` a caller-provided path: `mkdir -p $OUT && rm -f $OUT/*.log(N)`.
* Say in TESTING how this round's runs were invoked: `OUT=/tmp/qtmm-results-s11` and
  `OUT=/tmp/mm/states11`.

**Resolved when** no script removes a directory it didn't create, or it uses a variable name that
nothing else sets.

### R12-2: nit: `verify-states.sh` and the leak probe scripts

The script's header says "the final state is restored … also when killed" (`verify-states.sh:5`).

* **What holds.** TERM, INT and HUP restore, whether sent to the process or the process group
  (`/tmp/rv12/trap/`). A TERM to the script alone waits for the running child to finish, then
  restores. So no half-built state is left: I first suspected objects compiled from state S with
  mtimes newer than the restored sources, and ruled that out.
* **What doesn't: `kill -9`, a crash or a reboot.** In the scratch repo, a SIGKILL during S2's build
  left the worktree at S2, with the file S2 lacks deleted. In the real repo that means the untracked
  `tst_qvideowindow` files. The rerun then refuses: "working tree is not the final state". No
  document says how to get back.
  * This works, tested in the scratch repo: it restores the files, including the untracked one, and
    doesn't touch the index.

    ```
    cd qtmultimedia && S=refs/cadisplaylink/series
    git restore --source=$S/S6 --worktree -- $(git diff-tree -r --name-only $S/S6 $S/S1)
    ```

  * Put it in the script's header and TESTING, or add `verify-states.sh --restore`. Say "(TERM, INT,
    HUP; not kill -9)".
  * A second Ctrl-C during the restore let it finish in my test. A killed `git cat-file` mid-write
    would be caught by the final tree check ("RESTORE FAILED"), and this command recovers from it too.
* **Traps armed before the check** (`:24` before `:25`). A TERM or INT during the upfront `wtree`
  (a `git add -A` over 3244 files) runs `restore`. That overwrites the series files of a worktree
  that wasn't at S6, so uncommitted edits in them are lost. Arm the traps after the check.
* **Temporary index left behind** (`:12-13`). `wtree()` never removes its index:
  `$TMPDIR/qtmm-verify.2559.idx` from the author's run is still there (about 430 KB per run). Add
  `rm -f $TI` at its end, as `commit-series.sh:15` does.
* **The build directory isn't reconfigured after the restore** (`:22-23`).
  * If the last state given is S1 to S4, `qtmm-build` stays configured without `tst_qvideowindow`.
  * With its Unix Makefiles generator (`build.log:1-3`), `run-suites.sh:9`'s `--target
    tst_qvideowindow` should then fail as an unknown target until someone runs `cmake qtmm-build`.
    That's a loud failure, not a wrong result. I inferred it from how CMake's Makefile generator
    works; I didn't run it.
  * Run `cmake $B/qtmm-build` in `restore()`.
* **Warning filters.** `verify-states.sh:38` misses `qavfhelpers`, `qmultimediautils` and
  `qvideowidget`, all changed by M5. `run-suites.sh:17` misses `qavfhelpers` and `qvideowidget`. The
  recorded claim still holds: this round's final build compiled all of them, with 0 warnings in any
  series file under the broader filter. But the filter should match the series' files.
* **A missing binary isn't reported** (`:28-30`). If `find` returns nothing, `t()` runs `timeout 1200
  <args>` and prints empty totals. `run-suites.sh:20` handles this case.
* **The leak probe's results.**
  * `count.sh:9` prints the same empty strings for "no live object" and for a failed `heap(1)` run.
    `verify-states.sh:40` sends the line only to the terminal, and the files
    (`leakprobe/build/<label>.{out,heap}`) are overwritten by the next run with the same label.
  * TESTING's S5 "0 / 0" is real: `S5.out` says "players=20 with-a-frame=20", and `S5.heap` is a
    valid dump (an "All zones" line, `NSScreen` listed) with no `DisplayLinkObserver` or
    `CADisplayLink`. But TESTING doesn't say where that evidence is.
  * Fix: print `${n:-0}`, fail when the dump has no "All zones" line or the probe didn't print
    "ready", and tee the line into `$OUT/$S-leak.log`.
  * `count.sh:3` defaults `VIDEO` to an absolute path in this user's worktree, ignoring
    `QTMM_REPO` and `QT5_REPO`.
* **Tree construction isn't durable.** The trees are built by `/tmp/mm/states11.sh`, which uses a
  job-directory index (`~/.claude/jobs/328d9a96/tmp/states11.idx`) and per-state sources in `/tmp/mm`.
  * The trees themselves are safe (refs), and every state's content can be recovered from them.
  * But if M5 has to change after the ProMotion session (the README's condition), there's no
    durable procedure to make new S5 and S6.
  * Two lines in the series README would do:
    * S5' is a temporary index from `refs/cadisplaylink/series/S5`, `update-index` of the changed
      files, then `write-tree`;
    * S6' is S5' with `git diff-tree -p S5 S6 | git apply --cached` in the same index.
* `verify-states.sh:6` sets `PROBES`, which is never used.

**Resolved when** the recovery is documented and the traps come after the check. The rest is
optional.

### R12-3: nit: the else-branch has no test that fails without it

**Where:** `src/multimedia/video/qvideowindow.cpp:584-586`, and
`tests/auto/unit/multimedia/qvideowindow/tst_qvideowindow.cpp:218-226`.

**Problem:**

* The new test step ("Reset by the one who set it", `:222-226`) covers the write from 0, which I
  asked for. It passes with or without the else-branch: in both cases `current` is 0.
* No test checks what the else-branch is for: a value someone else sets after the window's own
  stops being taken for the window's.
* The code comment (`:577-579`) doesn't say why the branch forgets the value.

**Evidence:** `/tmp/rv12/owner.cpp` replays the test's steps on the cocoa path:

```
S6 test, with else: PASS
S6 test, without else: PASS
with the proposed lines, with else: PASS
    FAIL proposed: equal value from someone else, paused: 0.0, expected 30.0
with the proposed lines, without else: FAIL
```

**Fix:**

* Add these lines after `:220`, while the player is paused. The expectation is the same on every
  platform, because a value set by someone else is left alone.

  ```cpp
      // Someone else then sets exactly the window's former value: it's theirs now
      m_window->setPreferredFrameRate(m_exact);
      m_window->videoSink()->setVideoFrame(frameAt(m_exact));
      QCOMPARE(m_window->preferredFrameRate(), m_exact);
  ```

* In the code, a comment on the branch: "someone else's: forget ours, so that a later equal value
  of theirs isn't taken for ours".
* Optionally, check the lines by removing the branch, as rounds 9 and 10 did for the other rules.

### R12-4: nit: document residuals

* **R11-5's bookkeeping was left undone, and the round 11 response doesn't say so.** Its "Fixed"
  row lists the other items only.
  * README:96 (M5 "Contains") stops at R9-3. It lacks R10-1, R10-4, R11-1 and R11-5.
  * M5 document `:10` ("From") stops at round 9.
  * M5 document `:98-100`: the count of 39 rows is right, but the list doesn't name the rows added
    in rounds 10 and 11: 0.1% faster, `float(1.2)`, and the three fractional-display rows.
  * README step 5 (`:217`) still needs "a 25 fps file" without naming one: `colors.mp4`, or the
    ffmpeg line with `rate=25`.
  * README:81 still says "review rounds 4 to 10".
* **M5 document `:35-38`** still says another preference "is neither replaced nor reset". It lacks
  the "(unless it's the same value)" of `M5.txt:40` and the code comment, and doesn't mention the
  else-branch. The test list (`:108-109`) doesn't mention the new "reset to 0" step.
* **TESTING:15** still names `/tmp/ab/swap.sh`; README:236 names `verify/ab-swap.sh`.
* **TESTING:135:** "the reviewer simulated it from 23.5 to 1000 Hz". My round 11 simulation modelled
  my proposed code, with a lower bound of 13; the S6 code uses 12.5. Cite round 12's check of the
  exact code instead: `/tmp/rv12/rates.cpp`, 0 failures. With the 12.5 bound, the first two rates
  differ from the 13 version at 2,200 of the 97,651 refresh rates tried, and pass everywhere.
* **QVideoWidget docs** (`qvideowidget.cpp:40-41`): "the window the widget shows the video in" can
  still be read as the widget's top-level window. "the internal window the widget shows the video
  in" would be exact. It's public documentation, and one word.
* **Unwrapped lines left by this round's edits:** README:104 (113 columns) and :281 (157), M5
  document `:38` (130), TESTING:286 (115).

---

## Other checks, all found fine

* **M5 test code.**
  * The 12.5 lower bound is the midpoint between 12 and 13, so a rate just below 13 still counts.
    Rates just above 50 are now left out ("at most twice as fast"). That only changes which rates
    are tried, and at worst leads to a skip: at 250.1 Hz only one rate is left, so
    `_followsPlaybackRate` skips.
  * Mixed-type `QCOMPARE_GT(expected, 0)` was already used in `_isSetDuringPlayback`.
* **Evidence in detail.**
  * `/tmp/qtmm-results-s11/`: every total in TESTING:22-30 matches. The 9 darwin failures and the 2
    FFmpeg `server.listen()` failures are as described. `finiteLoops(No pause, fast rate)`: "4, expected
    3".
  * The A/B logs are interleaved (06:45:38 base-1, 06:46:12 r11-1, …): base failed `(No pause, fast
    rate)` in run 5, and the series failed `(Pause, fast rate)` in run 1.
* **What `finish.sh` would commit in qtbase:** 47 paths under `wip-cadisplaylink` (48 with this file),
  sources and documents only. `leakprobe/build/`, heap dumps included, is ignored.
* **Scripts.**
  * `commit-series.sh:7` and `finish.sh:7-10` are fixed as R11-5 asked.
  * `ab-swap.sh` swaps the four libraries that differ in code. MultimediaWidgets only has a doc
    change, and the class layouts it depends on are unchanged.
  * `leak.sh` builds the probe once. It links dynamically, so every state's libraries are the ones
    used.

---

## Verdict: APPROVE

Severity counts: blocker 0, major 0, minor 1, nit 3.

Round 11:

* R11-1 to R11-4 are closed. R11-5 is closed except its bookkeeping items (R12-4) and the untested
  else-branch (R12-3).
* The coordinator's `destruction` correction is accepted. My own round 10 and 11 statements were
  wrong the same way, and are corrected above.

The R6-6 and R7-5 deferrals stand, with the README's condition: M5 doesn't go to Gerrit before the
ProMotion session, and is reconsidered if the panel doesn't drop with FFmpeg.

* The built-in ProMotion panel is connected now, and step 1 of the checklist already reads
  "variable". Steps 1 to 6 can run now. Step 7 and R7-5 also need the G95SC.
* TESTING's results were all recorded on the G95SC. Record the display configuration with every
  new run: on the panel, `_isOnlySetForVariableRefreshRate` takes the variable path, and the
  fixed-display block of `_isResetWhenItNoLongerApplies` is skipped.
* Fix R12-1 before running `run-suites.sh` again.

Open, not blocking:

- R12-1: minor: run-suites.sh:4 does `rm -rf` on the directory named by the environment's generic `OUT` variable (demonstrated); use a specific name and don't remove caller-provided directories (tooling)
- R12-2: nit: verify-states.sh: no documented recovery after kill -9 (the worktree stays at the intermediate state and the script refuses to rerun), traps armed before the upfront check, temporary index left in $TMPDIR, no reconfigure after the restore, warning filters, the leak probe's empty-equals-zero output, tree construction not durable (tooling)
- R12-3: nit: R11-5's else-branch has no test that fails without it; add a step where someone else sets exactly the window's former value while paused (M5)
- R12-4: nit: R11-5 bookkeeping not done or acknowledged (README:96, M5 document :10 and :98-100, README step 5), the M5 document's ownership sentence, TESTING:15 and :135, "internal" in the QVideoWidget docs, unwrapped lines (docs, M5)
