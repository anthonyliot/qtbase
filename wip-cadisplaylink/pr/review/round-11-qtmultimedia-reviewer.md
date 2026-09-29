# Round 11 review: qtmultimedia series (M1 to M6)

Reviewer: qt-cadisplaylink-pr-reviewer (independent, strict)
Repo: `qt5/qtmultimedia`, base upstream `635067497`. The series is still uncommitted (signing blocked).
Its trees are kept by `refs/cadisplaylink/series/S1..S6` and listed in
`pr/qtmultimedia-series/trees.txt`. Line numbers are at S6 unless noted otherwise.

This is a confirmation round after my round 10 APPROVE. The author addressed R10-1 to R10-5 anyway.

| # | Tree | Subject | Round 10 items |
|---|---|---|---|
| M1 | S1 `47653cfd479b` | darwin: Don't leak the display link of AVFDisplayLink | none (unchanged) |
| M2 | S2 `e4ea5041e0f5` | darwin: Keep polling for video frames while menus and dialogs are open | none (unchanged) |
| M3 | S3 `dcbc502d19c3` | darwin: Stop using the deprecated CVDisplayLink in AVFDisplayLink | none (unchanged) |
| M4 | S4 `84212c21c771` | Report the stream frame rate of played video frames | none (unchanged) |
| M5 | S5 `9d6582f3ca7b` (was `9bb38750eba3`) | QVideoWindow: Let the display refresh at the video's frame rate | R10-1, R10-4, R10-5 |
| M6 | S6 `80569af10b23` (was `bd632ac19db0`) | darwin: Poll for video frames in sync with the display the video is on | none (patch identical apart from `index` lines) |

## How I checked

* **Trees and refs.**
  * S1 to S4 in `trees.txt` equal round 10's `/tmp/mm/series5-trees.txt`.
  * `refs/cadisplaylink/series/S1..S6` (type tree) equal `trees.txt`, and `trees.txt` equals the
    author's `/tmp/mm/series6-trees.txt`.
  * I diffed old S5 against new S5 with `git diff-tree -p`: 6 files (`qmultimediautils.cpp`,
    `qvideowindow.cpp`, `qvideowindow_p.h`, `qvideowidget.cpp`, the two tests). Old S6 against new
    S6 is the same.
  * M6's patch is identical to round 10's once the `index` lines are ignored.
  * `git diff-tree --check` is clean on all six patches. One added line is over 100 columns (R11-4).
* **Working tree.**
  * It equals S6: I ran `git hash-object --stdin-paths` (no `-w`) over its 3244 blobs, and 0
    differ.
  * The only untracked files are the two in `tests/auto/unit/multimedia/qvideowindow/`.
  * HEAD is `2152cdbd8`, the old M3, on `wip/cadisplaylink`, and it has no file that S6 lacks.
* **Messages.**
  * `M1..M6.txt` are byte-identical to `/tmp/mm/s7-{1..6}.txt`.
  * Every line is at most 72 columns and line 2 is blank.
  * The six Change-Ids are distinct, each preceded by a blank line, and every file ends with a
    newline.
* **Scripts.**
  * I read `commit-series.sh`, `finish.sh`, `sign.sh` and their diffs against round 10's
    `/tmp/mm` versions.
  * zsh `${0:A:h}`: I tested it through a relative path, `zsh script` and a symlink
    (`/tmp/rv11/selfloc`).
  * BSD `sed -n 0p`, which `commit-series.sh:25` hits when nothing is committed yet, prints nothing
    and returns 0.
  * Refs to trees, in a scratch repo (`/tmp/rv11/refs-test`): `log --all`, `rev-list --all` and
    `fsck` are clean, and the tree survives `gc --prune=now`.
  * Signing: `commit.gpgsign=true`, `gpg.format=x509`, ac-sign. So `git commit` can't make an
    unsigned commit.
* **What `finish.sh` would commit in qtbase now:** 41 paths under `wip-cadisplaylink`, sources and
  documents only (`git status --porcelain --untracked-files=all`). `.gitignore:333` ignores
  `build/`.
* **The ProMotion checklist, command by command (README:194-221).**
  * `vrr.mm` compiles with the README's line (output under `/tmp/rv11`) and runs.
  * The ffmpeg line, on a 2 s clip, gives h264 at `24/1`.
  * The viewprobe configures and builds with the README's two `cmake` lines, into `/tmp/rv11/vp`:
    0 warnings, and nothing is written into its source directory. I didn't run it: it opens a
    window and plays video.
  * `xctrace list templates` has "Animation Hitches", and `list instruments` has "Display".
  * The test binary and both function names exist, and the `qInfo` text matches.
* **Code.**
  * I re-derived `qVideoPreferredFrameRate()` and the ownership logic.
  * I read the parts of qtbase they rely on:
    * `QWindow::setPreferredFrameRate()` (`qwindow.cpp:1348-1362`);
    * `QCocoaScreen`'s refresh rate, `CGDisplayModeGetRefreshRate()` stored as a float
      (`qcocoascreen.mm:266-267`);
    * `forPreferredFrameRate()` (`qappleframerate.cpp:174-202`).
  * Scratch programs, no Qt:
    * `/tmp/rv11/tolerance.cpp`: round 10's rule against round 11's, on the integration test's
      expectations and on real content.
    * `/tmp/rv11/sweep.cpp`: the new rule against qtbase's mapping.
    * `/tmp/rv11/fixcheck.cpp`: the test fix proposed in R11-1.
    * `/tmp/rv11/cgrate.c`: what qtbase reads as the refresh rate.
* **Evidence, read only.**
  * `/tmp/mm/r10/`: `final-*`, `negative-r10.log` and the 05:13 logs.
  * `/tmp/mm/states10/` (S5).
  * The S5 leak probe result in the agent job directory.
  * The timestamps (mtimes) of the sources, test binaries and libraries.
* **Disclosure.**
  * In qtmultimedia I ran git only with `GIT_OPTIONAL_LOCKS=0`, and `hash-object` without `-w`.
  * In the `qt5-series` worktrees I ran `git log --format=%G?`. That runs ac-sign to verify
    signatures. It's read only, and no prompt appeared.
  * I built or ran nothing in the qtmultimedia worktree, `qtmm-build` or `qt5-build-nofw`. The
    viewprobe build only reads `qt5-build-nofw`'s CMake packages and libraries.
* **Environment note.**
  * AppKit now reports the G95SC as "max 120 fps, refresh interval min 0.008335 s, max 0.008335 s
    -> fixed" (vrr probe, about 05:40). CoreGraphics, which Qt uses, still says 240 Hz.
  * Round 8 read 240 fps from AppKit. So the two sources now disagree on this machine.
  * It doesn't affect the M5 tests, which check the preference, not the delivery rate. It matters
    for reading step 1 against step 3 of the ProMotion session: see R11-1's viewprobe item.

---

## Summary

The round 10 changes do what they say. R10-1's tolerance is now asymmetric:

* `qVideoPreferredFrameRate()` accepts content from 0.2% slower than an exact rate down to 1e-6
  faster (`qmultimediautils.cpp:92-93`).
* My sweep, 31.2 million (fps, Hz) pairs over 39 refresh rates, whole and fractional, stored as a
  float as qtbase does, found no violation. Every preference:
  * is paced by qtbase at an exact rate R/n, with n >= 2 dividing the whole refresh rate;
  * is never paced slower than the content beyond the float slack, so no frame is dropped;
  * is paced at most 0.2% faster than the content;
  * is a whole multiple of the frame rate;
  * is the slowest rate that qualifies.
* The float slack covers all three cases the round asked about:
  * 25 × float(1.2) = 30.0000012 is 4e-8 relative;
  * float(23.976) and float(29.97) round down, so they are slower anyway;
  * any float rounding is at most 6e-8 relative.

R10-4's ownership by value is right for every transition (table below). It is as precise as the
API allows: `QWindow::setPreferredFrameRate()` emits nothing for an unchanged value, so another
component setting the window's own value can't be detected by any scheme.

The durable series works:

* The copies are byte-identical to what round 10 reviewed.
* The scripts locate their own directory, the temporary index is in `$TMPDIR`, the trees are
  checked upfront, and the refs keep the trees.
* The checklist's commands work as written.

But the tolerance change has a side effect I didn't foresee when I proposed it in round 10:

* **R11-1, new.** `tst_qvideoframebackend` plays at whole rates derived from the *rounded* refresh
  rate. On a display that reports a rate just below a whole number, those are now rejected:
  * examples: 59.94 or 47.95 Hz (the fixed modes of MacBook Pro and Pro Display XDR panels),
    119.88, 143.98 or 239.96 Hz;
  * `_isSetDuringPlayback`, `_followsPlaybackRate` and `_isResetWhenPaused` fail there, where they
    passed in round 10;
  * `_isOnlySetForVariableRefreshRate` becomes vacuous on such a variable display;
  * the function itself is right; the test's choice of rates is what's wrong.

The rest is documentation:

* **R11-2.** The public QVideoWidget documentation names the wrong window.
* **R11-3.** Stale and volatile references remain:
  * round 10's trees in the M5 and M6 documents;
  * "one frame in 1001" still in the README;
  * TESTING's probe paths in the job directory;
  * verification scripts only in `/tmp`.

R11-4 and R11-5 are nits.

---

## Round 10 findings

| ID | Round 10 severity | Response | Verified at S6 | Status |
|---|---|---|---|---|
| R10-1 | minor | Fixed (M5) | Code: `qmultimediautils.cpp:92-93`. Comment `:75-78`, message `M5.txt:15-17` and `:25-26`, M5 document `:20-21` and `:81-83`. Rows `tst_qmultimediautils.cpp:164-166`. `negative-r10.log`: the symmetric rule gives 24.024 for the 0.1% faster row, and removing the 1e-6 slack would fail the float(1.2) row. The sweep above has no violation. | **Closed for the code, comment, message and M5 document.** README:277 still says "one frame in 1001" (R11-3). The change breaks the integration tests on fractional refresh rates (R11-1). |
| R10-2 | minor | Fixed (README) | README:194-221. Step 0: main display. Step 1: durable `vrr` path and build line, runs. Step 2: names exist. Step 3: the file (ffmpeg line checked), the program (viewprobe builds as written; its timed mode, `main.cpp:35-44`, prints frames, preference and screen every second), the expectation. Step 4: Instruments' Display track instead of a probe's own link (template and instrument exist). Step 5: a latency method. Step 6: R9-1's real move. | **Closed.** Residuals: step 2 can pass vacuously and the viewprobe hides a fractional refresh rate (R11-1); step 5's 25 fps file is unnamed, and the viewprobe counts FFmpeg frames off the main thread (R11-5). |
| R10-3 | minor | Fixed | `pr/qtmultimedia-series/`: messages identical, `trees.txt`, self-locating scripts, temporary index in `$TMPDIR`, trees checked upfront (`commit-series.sh:13`), refs to the trees (checked; harmless, see above). `finish.sh:14-15` commits `wip-cadisplaylink` as a whole. Probes in `probes/qtmultimedia/`. | **Closed.** Residuals: TESTING still points at the old probe paths, and the verification scripts are only in `/tmp` (R11-3). |
| R10-4 | nit | Fixed (M5) | `qvideowindow.cpp:580-584`, `qvideowindow_p.h:90`. Test `tst_qvideowindow.cpp:199-227`; round 9's rule fails it at `:209` (`negative-r10.log`: 120 replaced 12.3). Transition table below. | **Closed.** Wording and hardening nit: R11-5. |
| R10-5 | nit | Fixed | Series4 references gone. M2 and M5 "Verified" sections name the right rounds. M5 message: "iOS paces too, but doesn't tell" (`M5.txt:33`). QVideoWidget: "can then refresh slower and use less power". TESTING:148-151 says which libraries each stress run used. `/tmp/mm/r9/-mock.log` is gone. | **Closed except QVideoWidget:** "or a whole multiple" still missing, and the new wording names the wrong window (R11-2). |
| R6-6, R7-5 | minor | Deferred to the ProMotion and two-screen session | README:194-221, including the approval's condition (`:212-214`) | Deferrals still accepted. M5 doesn't go to Gerrit before that session. |

### R10-4: every transition, at S6

"own" is `m_preferredFrameRate`, "current" is `QWindow::preferredFrameRate()`, and v is this
frame's value. The check is `current == 0 || current == own`, then write v and set own to v
(`qvideowindow.cpp:580-584`).

The comparison is exact. `QWindow` stores finite non-negative values unchanged
(`qwindow.cpp:1356-1358`). The window only passes 0, or k × rate, which is at most half the refresh
rate.

| Before the frame | Frame | Result | Evidence |
|---|---|---|---|
| Nothing set (current 0, own 0) | qualifies | written; own = v | `_isSetForRatesTheDisplayShowsExactly` |
| Own in effect (current = own) | new rate (screen, playback rate) | written | `_followsPlaybackRate`; playback rate 2 in `tst_qvideowindow` |
| Own in effect | stops applying (fixed display, no vsync, paused, player gone, other source) | reset to 0, own = 0 (R9-1) | `_isResetWhenItNoLongerApplies`, `_isNotSetWhilePaused`, `_isResetWhenPaused` |
| Someone else set P before the window's own (current P, own 0) | any | left alone; own stays 0, so it's never reset later | `_leavesAnotherPreferenceAlone` first block; negative check |
| Someone else set exactly v before (current v, own 0) | qualifies with v | left alone, and still left alone once it stops applying | code: neither condition holds |
| Someone else set P after the window's own (current P, own v) | qualifies, or stops applying | left alone; own stays v (stale) | `_leavesAnotherPreferenceAlone` second block, paused included |
| As above, then that component resets to 0 | any | the window writes its value again | code (`current == 0`) |
| Someone resets to 0 while the window's value is in effect | qualifies | the window sets its own again. 0 means none, so it doesn't opt the window out; a value that is never the window's (its refresh rate, which qtbase treats as the full rate) does | code; the "set 0" step of the test covers the write from 0 |
| Someone else sets exactly the window's value while it's in effect | stops applying | taken as the window's own, reset | QWindow emits nothing for an unchanged value, so no scheme can tell. R11-5 (wording) |
| Someone else set P after, then later sets exactly the stale own value | stops applying | taken as the window's, reset | `else own = 0` would avoid it. R11-5 (optional) |
| Invalid value from someone else (NaN, negative) | any | QWindow stores 0 (with a warning), so it behaves like a reset to 0 | `qwindow.cpp:1351-1355` |
| Interplay with R9-1 | moved to a fixed display, paused, ... | resets only a value that is still the window's own; a later value from someone else is kept | as above |

---

## New findings

| ID | Severity | Title | Commit |
|---|---|---|---|
| R11-1 | minor | R10-1's asymmetric tolerance breaks `tst_qvideoframebackend`'s preference tests on displays reporting a refresh rate just below a whole number (59.94, 47.95, 119.88, 143.98, 239.96 Hz). Whole-rate content gets no preference there, which is undocumented | M5 |
| R11-2 | minor | The QVideoWidget class documentation says the widget sets "its window's preferred frame rate": the wrong window. It still lacks "or a whole multiple" | M5 |
| R11-3 | minor | Stale and volatile references: round 10's trees in the M5 and M6 documents, "1001" in the README, TESTING's probe paths, verification scripts only in `/tmp`, an outdated qtbase checklist item | docs |
| R11-4 | nit | A new test row is 106 columns | M5 |
| R11-5 | nit | Small tooling and wording issues (viewprobe counting thread, overwritten final logs, docs commit message, `count.sh` outputs, ownership wording, script defaults, bookkeeping) | tooling, docs |

---

### R11-1: minor: the integration tests fail on displays whose refresh rate is just below a whole number

**Where:**

* `tests/auto/integration/qvideoframebackend/tst_qvideoframebackend.cpp:459-471`,
  `exactRatesToPlayAt()`. It returns `int` rates: `wholeRefreshRate / refreshes` of the *rounded*
  refresh rate.
* The tests that play at them:
  * `_isSetDuringPlayback`: `:508`, `:513-519`, with `QCOMPARE_GT(expected, 0)`;
  * `_followsPlaybackRate`: `:550-566`, with `QCOMPARE_NE`;
  * `_isResetWhenPaused`: `:597-599`, with `QTRY_COMPARE_GT(..., 0)`;
  * `_isOnlySetForVariableRefreshRate`: `:632`, `:641-645`.
* The function divides the *actual* refresh rate (`qmultimediautils.cpp:90`). qtbase reports
  `CGDisplayModeGetRefreshRate()` unrounded, as a float (`qcocoascreen.mm:266-267`).

**Scenario:**

* The window's display reports 59.94 Hz: a MacBook Pro or Pro Display XDR set to "59.94 Hertz", or
  a TV.
* `exactRatesToPlayAt(59.94)` gives `[30, 20, 15]`. The test plays `colors.mp4` at 1.2, so frames
  arrive at 30 fps.
* The display's exact rate is 59.94 / 2 = 29.97. So 30 fps is 0.1% faster than it.
  * Round 10's symmetric check accepted that. Round 11's rejects it, correctly: qtbase would pace a
    preference of 30 at 29.97 (`forPreferredFrameRate()`), dropping one frame in 1000.
  * So `qVideoPreferredFrameRate()` returns 0.
* `_isSetDuringPlayback` fails at `QCOMPARE_GT(expected, 0)`, and `_isResetWhenPaused` times out.
* `_followsPlaybackRate` gets 0 for both 30 and 20 and fails `QCOMPARE_NE`.
* On a *variable* display that reports such a rate, `_isOnlySetForVariableRefreshRate` compares 0
  with 0 and can't fail. That is the check step 2 of the ProMotion session relies on ("expects a
  preference").
* The same happens at any rate a little below a whole number: 47.95, 74.97, 119.88, 119.98,
  143.86, 143.98, 164.8, 239.76, 239.96 Hz.
* Rates at or above a whole number (60.02, 240.02) are unaffected.
* `tst_qvideowindow` (`:38-45`, `:91`) and `tst_qvideowidget` (`:306-310`) are robust: they
  derive their rate from the actual refresh rate.

**Evidence:** `/tmp/rv11/tolerance.cpp`. The backend's float playback rate is modelled, and the
expectations are the tests' own:

```
R=59.94006   rates: 30 20 15 | r10: e0=30.000001 e1=20.000000 setDuring=pass follows=pass | r11: e0=0.000000 e1=0.000000 setDuring=FAIL follows=FAIL
R=119.88012  rates: 24 30 20 15 40 | r10: ... pass | r11: e0=0.000000 e1=0.000000 setDuring=FAIL follows=FAIL
R=239.96001  rates: 24 30 20 16 15 40 48 | r10: ... pass | r11: e0=0.000000 e1=0.000000 setDuring=FAIL follows=FAIL
R=47.95205   rates: 24 16 | r10: ... pass | r11: e0=0.000000 e1=0.000000 setDuring=FAIL follows=FAIL
R=240.00000  ... r11: e0=23.999999 e1=30.000001 setDuring=pass follows=pass
```

The same program's content table shows the product side:

* at 119.88 Hz, 24 fps gets no preference now (it was 24), while 23.976 gets 23.976;
* at 239.96 Hz, 24, 30, 48 and 60 fps get none (they were set).

That's consistent with R10-1: those rates would be paced slightly slower than the content, and
frames would be dropped. But the M5 document's table, the README and the message only cover whole
refresh rates.

**Why minor.**

* The product code is right: the sweep shows no rate paced below its content.
* The failures are deterministic but need a display the author's machine, and likely Qt's CI (60
  Hz), doesn't have.
* But the round 10 change introduced them, silently. The project already treated this family as a
  real defect in qtbase (REVIEW.md #5, "Test expectations wrong on 59.94/50/144 Hz"). And a
  developer with such a display, a video professional in particular, would hit three failures at
  once.
* It was my R10-1 fix (a). I didn't check the integration tests against fractional rates in round
  10.

**Fix:**

* Derive the rates from the actual refresh rate, as `tst_qvideowindow`'s `exactFrameRate()` does:

  ```cpp
  QList<qreal> exactRatesToPlayAt(qreal refreshRate)
  {
      const int wholeRefreshRate = qRound(refreshRate);
      QList<qreal> rates;
      for (int refreshes = 2; refreshes <= wholeRefreshRate; ++refreshes) {
          const qreal rate = refreshRate / refreshes;
          if (wholeRefreshRate % refreshes == 0 && rate >= 13 && rate <= 50)
              rates.append(rate);
      }
      std::stable_sort(rates.begin(), rates.end(),
                       [](qreal a, qreal b) { return qAbs(a - 25) < qAbs(b - 25); });
      return rates;
  }
  ```

  `/tmp/rv11/fixcheck.cpp` runs this with the tests' expectations:
  * every reported rate from 23.5 to 1000 Hz, 0.01 apart;
  * float and double playback rates;
  * result: `_isSetDuringPlayback` and `_followsPlaybackRate` would pass at every rate up to 1000
    Hz. The only failures are above 1000 Hz, where `qVideoPreferredFrameRate()` returns 0 by
    design.
* In `_isOnlySetForVariableRefreshRate`, add
  `if (platformPacesToTheDisplay() && variableRefreshRate) QCOMPARE_GT(window.preferredFrameRate(), 0);`,
  so that step 2 of the session can't pass vacuously.
* Unit rows for fractional displays: "30 fps at 59.94 Hz → none", and "24 fps at 119.88 Hz → none"
  next to "23.976 fps at 119.88 Hz → 23.976". They record the behavior that R10-1 changed.
* One sentence in the M5 document ("Limits") and the README: "On a display whose refresh rate is a
  little below a whole number (59.94, 119.88 Hz) only content at its own rates qualifies (29.97,
  23.976), not 30 or 24, which would be paced below their rate."
* The viewprobe prints the refresh rate with `%.0f` (`main.cpp:38-40`), which would hide 119.88 as
  "120" in steps 3 and 6. Print it with `%.3f`.

**Resolved when** the integration tests derive their rates from the actual refresh rate, the
variable-display check requires a preference, and the rows, docs and probe are updated.

### R11-2: minor: the QVideoWidget documentation names the wrong window

**Where:** `src/multimediawidgets/qvideowidget.cpp:39-46` (public class documentation, goes to
Gerrit and doc.qt.io).

**Problem:**

* "the widget asks for the rate the video's frames arrive at as *its window's* preferred frame
  rate".
  * For a widget, "its window" is `QWidget::window()`, whose `windowHandle()->preferredFrameRate()`
    stays 0.
  * The preference is set on the internal `QVideoWindow` that the widget embeds with
    `createWindowContainer()` (`:72-74`).
  * A reader who reads or sets the top-level window's property to inspect or override it gets
    nothing.
* "the rate the video's frames arrive at" is still missing "or a whole multiple of it": 12.5 fps
  at 100 Hz asks for 25 (R10-5's first point, not addressed).

**Fix,** for example: "... the widget asks the display to refresh at the rate the video's frames
arrive at, or a whole multiple of it, when the display can show every frame for the same time at
that rate, for instance 24 Hz for 24 fps video on a 120 Hz display. It sets this as the preferred
frame rate of the internal window it shows the video in (see QWindow::preferredFrameRate). The
display can then refresh slower and use less power, but ..."

**Resolved when** the paragraph doesn't suggest the widget's own window, and mentions the multiple.

### R11-3: minor: stale and volatile references in the documents

**Where and what:**

* **M5 and M6 documents, `:7`.** They give round 10's trees: "S5 `9bb38750eba3`" and "S6
  `bd632ac19db0` (the final tree)". The tested trees are now `9d6582f3ca7b` and `80569af10b23`.
  * M1, M2 and M5 `:7` still cite `/tmp/mm/series5-trees.txt` instead of
    `qtmultimedia-series/trees.txt`.
  * These are the per-commit documents a Gerrit reviewer checks the commits against.
* **README:277** ("Known limitations"): "23.976 and 29.97 fps show one frame in 1001 twice as long
  (R8-1, R9-3)". R10-1 asked for "1000" in all four places, and the author's response says the
  README was done.
* **TESTING, probe paths.** `:157`, `:170`, `:212` and `:226` cite
  `$CLAUDE_JOB_DIR/tmp/{vrr/vrr.mm,menuprobe,leakprobe,cycle/probe.mm}`, and `:232` cites
  `/tmp/viewprobe`. The sources are now in `probes/qtmultimedia/`, but TESTING doesn't say so.
* **Verification scripts.**
  * The ones TESTING cites exist only in `/tmp`:
    * `/tmp/mm/verify-states8.sh` and `verify-states10.sh` (`:250`);
    * `r9/negative.py` and `r9/stress-ab.sh`;
    * `r10/final-m5-suites.sh`;
    * `/tmp/ab/swap.sh`, which README:235 tells the reader to use.
  * `verify-states10.sh:9` and `:37` still depend on the agent's job directory: the temporary
    index, and the leak probe's copy, where S5's "0 / 0" also lives (`S5.heap`, `S5.out`).
  * A re-verification of the states before Gerrit, after a rebase for instance, has no durable
    script. The logs can stay in `/tmp`, but TESTING should say they are volatile.
* **README:186-187,** "Sign and create the series commits (blocked on AppleConnect), check each
  commit's tree against `/tmp/r2/...`". Both the qtbase and the qtdeclarative series already exist
  in `qt5-series/`:
  * signed: `%G?` is G for all 11 commits;
  * with exactly the trees of `/tmp/r2/series-trees.txt` and `decl-trees.txt` (I compared all 11).
  * The item should say it's done. Once it does, the `/tmp/r2` lists no longer matter.

**Fix:**

* Update the references above.
* Copy the verification scripts (not the logs) to `qtmultimedia-series/verify/`, with the job
  directory paths replaced by `$TMPDIR` and `probes/qtmultimedia/leakprobe`, and point TESTING at
  them.

**Resolved when** no document points at a tree other than the tested ones, or at the job directory,
and the scripts TESTING relies on have a durable copy.

### R11-4: nit: a new test row is 106 columns

`tests/auto/unit/multimedia/qmultimediautils/tst_qmultimediautils.cpp:166`:

```
    QTest::newRow("25 fps played at float(1.2) at 60 Hz") << 25 * qreal(1.2f) << 60.0 << 25 * qreal(1.2f);
```

It's over Qt's 100-column limit. Round 9 (R9-6) had made M5 clean. Break it after the row name.

### R11-5: nit

* **viewprobe counting thread** (`probes/qtmultimedia/viewprobe/main.cpp:27-29`).
  * The frame counter's lambda has no context object. With FFmpeg, which the checklist's step 3
    now uses, it counts on the renderer thread.
  * `frames` is a plain `int` read on the main thread, so it's a data race.
  * That's the R9-6 pattern the menu probe fixed. Pass `&window` as the context.
* **Overwritten final logs** (`/tmp/mm/r10/final-m5-suites.sh:8`).
  * `r()` names its log after `$1` *after* `shift 2`. So the three mock runs all wrote
    `final--mock.log`: `tst_qmultimediautils` overwrote `tst_qvideowindow` and `tst_qvideowidget`.
  * TESTING:16-19 cites `final-*` for "tst_qvideowindow 7; tst_qvideowidget 8 passed, 1 skipped".
  * Those runs did happen: both binaries were rebuilt at 05:23. But their logs are gone.
  * The 05:13 logs (`tst_qvideowindow-mock.log` 7 passed, `tst_qvideowidget-mock.log` 8 and 1
    skipped) ran before the negative checks. The library sources then were S6's: the negative
    checks' saved `qvideowindow.good.cpp` and `qmultimediautils.good.cpp` equal S6's blobs. I
    couldn't check the test sources of that run.
  * Fix the script (keep the name before `shift`, as `verify-states10.sh:25` does), or cite the
    05:13 logs. It's the same kind of slip as round 9's `-mock.log`.
* **Docs commit message** (`qtbase-docs.txt:3-5`). It lists the M documents, README, TESTING and
  the review rounds. It doesn't mention `pr/qtmultimedia-series/` (messages, trees, scripts) or
  `probes/qtmultimedia/`, which the commit now includes.
* **`count.sh` outputs** (`probes/qtmultimedia/leakprobe/count.sh:4`, `:7`).
  * It writes `<label>.out` and `<label>.heap` next to itself, and qtbase ignores only `build/`.
  * Run before `finish.sh`, its heap dumps (about 100 KB each) would be committed by
    `git add -- wip-cadisplaylink`.
  * Write them under `build/` or `$TMPDIR`.
* **Ownership wording.**
  * `M5.txt:39-40` ("neither replaced nor reset") and `qvideowindow.cpp:577-579` ("one that
    someone else set is left alone") over-claim for a value equal to the window's own. That case
    is inherent (see the table): "(unless it's the same value)" would be exact.
  * Optional: `else d->m_preferredFrameRate = 0;` would also make a later coincidental equal value
    safe.
  * Optional: a test line for "the other component resets to 0, then the window sets its own
    again".
* **Script details.**
  * `finish.sh:8` checks every input except `sign.sh`, which `:6` sources first. It fails safe,
    with "command not found".
  * `commit-series.sh:7` defaults `QTMM_REPO` independently of `finish.sh`'s `QT5_REPO`. Use
    `${QTMM_REPO:-${QT5_REPO:-...}/qtmultimedia}`.
* **Bookkeeping.**
  * README:96 (M5 "Contains") and the M5 document's "From" (`:10`) don't list R10-1 and R10-4.
  * The M5 document's test list (`:96-98`) doesn't name the two new rows.
  * README step 5 needs "a 25 fps file" but doesn't name one: `colors.mp4`, or the ffmpeg line with
    `rate=25`.

---

## Commit by commit: other checks, all found fine

* **M1 to M4.** Trees identical to round 10's. Messages unchanged.
* **M5.**
  * `qVideoPreferredFrameRate()`: the argument checks, the loop bounds and the int range of the
    multiples are unchanged.
  * The two new rows each catch one regression:
    * the 0.1% faster row fails with the symmetric check (`negative-r10.log`);
    * the float(1.2) row would fail without the 1e-6 slack. I checked this by derivation: 30 /
      30.0000012 = 0.99999996.
  * "About one frame in 1000 … at most one in 500" and "every 42 and 33 seconds" are right: 1000
    frames at 23.976 and 29.97 fps last 41.7 and 33.4 s.
  * The ownership change keeps round 9's behavior wherever nothing else sets a preference. Suites
    that create QVideoWindows without a playing media player, or on this fixed display without the
    hook, can't change:
    * `tst_qmediaplayerwidgets`, `tst_qcamerawidgets`, `tst_qmediacapturesession`,
      `tst_qwindowcapturebackend`;
    * the reason: the value is 0, and `setPreferredFrameRate(0)` returns early on an unchanged
      value.
  * The messages are accurate apart from the R11-5 wording, and the iOS sentence is right (`:97`
    of the code comment).
* **M6.** Patch unchanged.
* **States and suites.**
  * S5, `/tmp/mm/states10/`, all consistent with TESTING:263:
    * 20 and 20 passed on the two backends;
    * `tst_qvideowindow` 7, `tst_qvideowidget` 8 passed and 1 skipped, `tst_qmultimediautils` 304;
    * 80 `destruction` rows;
    * leak probe 20 players with a frame, 0 observers and 0 links.
  * S6 final:
    * `tst_qvideoframebackend` 22 passed, 1 skipped on both backends (`final-*`, 05:23, binaries
      and libraries built after the 05:20 sources);
    * `tst_qmultimediautils` 304;
    * the other two suites: see R11-5.
* **Tooling.** `commit-series.sh` handles HEAD at the old M3: it counts 0 done, resets to the base,
  and commits S1 to S6. Resuming counts commits by subject and tree. A killed signing restores the
  index. `finish.sh`'s steps can each be rerun.

---

## Verdict: APPROVE

Severity counts: blocker 0, major 0, minor 3, nit 2.

Round 10:

* R10-2, R10-3 and R10-4 are closed.
* R10-1 is closed for the code, with the README residue in R11-3 and the test side effect in R11-1.
* R10-5 is closed except the QVideoWidget part, now R11-2.

The R6-6 and R7-5 deferrals stand, with the README's condition: M5 doesn't go to Gerrit before the
ProMotion session, and is reconsidered if the panel doesn't drop with FFmpeg. R11-1 is cheap and
should be fixed before that session, so that step 2 can't pass vacuously on the panel.

Open, not blocking:

- R11-1: minor: R10-1's asymmetric tolerance breaks tst_qvideoframebackend's preference tests on displays reporting a refresh rate just below a whole number (59.94, 47.95, 119.88, 143.98, 239.96 Hz), makes the variable-display check vacuous there, and whole-rate content gets no preference there, undocumented (M5)
- R11-2: minor: QVideoWidget docs name the wrong window ("its window's preferred frame rate"), and still lack "or a whole multiple" (M5)
- R11-3: minor: M5/M6 documents give round 10's trees, README:277 still says "1001", TESTING's probe paths point at the job directory, verification scripts only in /tmp, outdated qtbase checklist item (docs)
- R11-4: nit: tst_qmultimediautils.cpp:166 is 106 columns (M5)
- R11-5: nit: viewprobe counts FFmpeg frames off the main thread; final mock logs overwritten; docs commit message; count.sh outputs; ownership wording; script defaults; bookkeeping (tooling, docs)
