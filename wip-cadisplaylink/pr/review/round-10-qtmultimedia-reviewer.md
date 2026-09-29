# Round 10 review: qtmultimedia series (M1 to M6)

Reviewer: qt-cadisplaylink-pr-reviewer (independent, strict)
Repo: `qt5/qtmultimedia`, base upstream `635067497`. The series still isn't committed. It's recorded
as trees in `/tmp/mm/series5-trees.txt`.

The working tree equals S6. I checked it with `git hash-object` (without `-w`) of every file in S6:
all 0 differ. The only untracked files are the two in `tests/auto/unit/multimedia/qvideowindow/`,
which S6 has. Line numbers are at S6 unless noted otherwise.

| # | Tree | Subject | Round 9 items |
|---|---|---|---|
| M1 | S1 `47653cfd479b` | darwin: Don't leak the display link of AVFDisplayLink | none (unchanged since round 7) |
| M2 | S2 `e4ea5041e0f5` | darwin: Keep polling for video frames while menus and dialogs are open | none (unchanged since round 8) |
| M3 | S3 `dcbc502d19c3` | darwin: Stop using the deprecated CVDisplayLink in AVFDisplayLink | none |
| M4 | S4 `84212c21c771` | Report the stream frame rate of played video frames | none |
| M5 | S5 `9bb38750eba3` | QVideoWindow: Let the display refresh at the video's frame rate | R9-1, R9-2, R9-3, R9-6 |
| M6 | S6 `bd632ac19db0` | darwin: Poll for video frames in sync with the display the video is on | none (patch identical to round 8 except for context lines) |

How I checked:

* **Patches.**
  * `git diff-tree -p` and `-M --stat` of each state against the previous one.
  * `series4-trees.txt` against `series5-trees.txt`: only S5 and S6 differ.
  * Round 8's M6 patch against round 9's: identical, apart from the `index` lines and the hunk
    context in the test file.
  * `git diff-tree --check` on all six patches: clean.
  * No added line is over 100 columns in any patch (awk over the `+` lines).
* **Messages.** `/tmp/mm/s7-{1..6}.txt`:
  * every line is at most 72 columns;
  * there's a blank line before each Change-Id, and the six Change-Ids are distinct.
* **Tooling.**
  * `commit-series5.sh`: it differs from `commit-series4.sh` only in its header and the trees file.
  * `finish.sh`, `sign.sh`, `qtbase-docs.txt`, `qt5-pointers.txt`.
  * The verification scripts: `verify-states9.sh`, `r9/stress-ab.sh`, `/tmp/ab/swap.sh` and
    `r9/negative.py`.
* **The new test.**
  * Its CMake against the neighbours (`qvideotransformation`, `qmediaplayer`, `qscreencapture`).
  * The mock player: `setIsValid()` gates `play()` and `pause()`, `qmockmediaplayer.h:91-92`.
  * tst_qmediaplayer's use of the mock player (`mockPlayer->setIsValid(valid)`).
* **The backends, for R9-2.**
  * `QFFmpegMediaPlayer::runPlayback()` (`qffmpegmediaplayer.cpp:300-304`) and `AVFMediaPlayer::play()`
    (`avfmediaplayer.mm:886-888`) both set `PlayingState` synchronously, before any frame of that
    playback arrives.
  * The FFmpeg renderer only gets valid frames. `StreamDecoder::onFrameFound()` is the only
    emitter of `requestHandleFrame`.
  * Empty frames are only sent in these cases:
    * FFmpeg: on `finalizeOutputs()`, with `cleanOutput` true (`qffmpegplaybackengine.cpp:626`);
    * darwin: from `setLayer(nil)`.
  * Detaching the output sends none: `updateActiveVideoOutput(sink)` defaults `cleanOutput` to
    false (`:496`, `_p.h:157`).
* **qtbase at the branch head (`f18df50a300`).**
  * Only windows with a pending update request set the display link's rate:
    * `QCocoaScreen::updateDisplayLinkFrameRate()`;
    * `QAppleDisplayLinkDelivery::pendingRange()` (`qappleframerate.cpp:447-458`).
  * Pacing is per window (`deliver()`, `shouldDeliverFrame()`).
  * `forPreferredFrameRate()` (`:174-202`).
  * `QCocoaWindow::setPreferredFrameRate()`.
  * The only other caller of `setPreferredFrameRate()` in qtbase's `src/` is `QWidget::create()`,
    for top-level widget windows (`qwidget.cpp:1401`).
  * `QNativeInterface::QCocoaScreen::nativeScreen()` is upstream (`0e8073278cf`), and qtbase's
    series doesn't touch it.
* **The author's logs, read only.**
  * `states9/` (S5), `qtmm-results-s9/` and `r9/`.
  * I matched every `Loc:` line in the negative logs to the S6 tests. `negative.py`'s baseline
    `qvideowindow.good.cpp` is identical to S6's `qvideowindow.cpp`.
  * I compared the stress logs' timestamps with the other runs. The libraries installed in
    `qt5-build-nofw` are byte-identical to `/tmp/ab/r9` (`cmp`).
* **My own scratch program:** `/tmp/rv10/cadence.py`, plain Python with no Qt, not in any tree.
* **Disclosure.**
  * In qtmultimedia I ran `git status`, and by mistake one `git write-tree`. These can refresh
    `.git/index`'s stat and cache-tree data.
  * The staged content, refs, objects and working tree didn't change. The tree written was HEAD's
    existing `a03e34ad`.
  * After that I ran git only with `GIT_OPTIONAL_LOCKS=0`, and `hash-object` without `-w`.
  * I didn't build or run anything in the qtmultimedia worktree, `qtmm-build` or `qt5-build-nofw`.

---

## Summary

The round 9 blocker is fixed correctly, in M5:

* `setVideoFrame()` now computes 0 whenever the conditions don't hold, and writes the property
  when either the new value or the window's own previous one is non-zero
  (`qvideowindow.cpp:568-582`).
* I went through every transition the round asks about (table below). The next frame resets a
  preference that no longer applies:
  * after a move to a fixed-rate display;
  * after a mode switched to a fixed rate;
  * with vertical sync off;
  * while paused;
  * when the player is gone;
  * for frames from another source.
* The value only stays stale on a window that gets no frames. There it has no effect:
  * that window requests no updates, except `render()`'s `beginFrame` retry (`:399-402`);
  * qtbase only takes windows with pending requests into account for the display link.
* The new mock-backend test and the real-playback `_isResetWhenPaused` catch the regressions. The
  five negative checks show it: every failure line matches the S6 tests.

R9-2 (PlayingState only) is right. Both backends enter `PlayingState` before the frames of that
playback arrive. Buffering is a media status, not a playback state. Neither backend delivers a
rate-less frame while playing. So the preference can't be missed at the start, and it doesn't flap.

R9-5's A/B is enough:

* the `(video, playing)` rows failed 3 times in 9 row-runs upstream and 2 times with the series;
* the symptom is the same, a start 50 to 100 ms over the 5 s timeout;
* the final run had none.

What's left is minor:

* **R10-1.** "One frame in 1001" is one in 1000. And content up to 0.2% faster than an exact rate
  loses frames, which isn't documented.
* **R10-2.** The ProMotion session checklist isn't actionable as written, and it lacks R9-1's real
  move.
* **R10-3.** The reviewed series (messages, trees list, scripts) exists only in volatile places.

R10-4 and R10-5 are nits.

---

## Round 9 findings

| ID | Round 9 severity | Response | Verified at S6 | Status |
|---|---|---|---|---|
| R9-1 | blocker | Fixed (M5) | `qvideowindow.cpp:568-582`, `qvideowindow_p.h:90`. Transition table below. Tests: `tst_QVideoWindow::preferredFrameRate_isResetWhenItNoLongerApplies` (fixed display via the hook, no vsync, player gone), `_isSetForRatesTheDisplayShowsExactly` (2.5 refreshes, rate 0 and no frame all reset), `_isNotSetWhilePaused`, and the real `_isResetWhenPaused`. `negative-noreset.log`: 3 mock failures and the real one, all at the S6 line numbers (115, 152, 185; 606). Message (`s7-5.txt:16-19`), code comment (`:565-567`, `:577-578`) and M5 document (`:32-35`) describe the reset. | **Closed.** My resolution also asked for the real move in the R9-4 session, which the checklist doesn't list: R10-2. Ownership wording: R10-4 |
| R9-2 | minor | Fixed (M5) | `qvideowindow.cpp:570`. Both backends set `PlayingState` synchronously before the frames of that playback (see "How I checked"). `negative-paused.log`: `_isNotSetWhilePaused` and `_isResetWhenPaused` fail. The reset happens before the seek frame's own `requestUpdate()` (`:579-585`). `colors.mp4` is 15 s long, so `setPosition(5000)` really is a paused seek. | **Closed** |
| R9-3 | minor | Fixed | "30 fps on 60, 120 and 240 Hz" (README:100); darwin decode link (M5 doc `:83-85`, README:258-260); 29.97 and slip to the next tick (message, document, README); `QVideoWidget` class documentation (`qvideowidget.cpp:39-45`) | **Closed except R10-1:** the new count "one frame in 1001" is one in 1000, and the symmetric drop case is missing. Wording nits: R10-5 |
| R9-4 | minor | Done (README checklist) | README:191-201 | **Open as R10-2:** paths, screen setup, methods, R9-1's move |
| R9-5 | minor | Done | `r9/stress-*.log`: upstream failed 0, 1 and 2 rows in its three runs, the series 1, 1 and 0. Always `(video, playing)` with "5050/5100 ms would have been sufficient". Final run: no stress failure, 248 passed, 10 failed (5 `invalidHttpsAddress`, 5 duration rows). | **Closed.** The upstream rate matches, so the round 8 streak was the machine that night. Note on rounds 1-2 libraries: R10-5 |
| R9-6 | nit | Fixed | No added line over 100 columns. The negative checks are rerun with the current names, including the display-check bypass, which `_isOnlySetForVariableRefreshRate` catches (`negative-novrr.log`, failing at `tst_qvideoframebackend.cpp:645`). The menu probe counts on the main thread (`menuprobe-mainthread.txt`). The finish messages have no round number. The player and state checks now come before AppKit (`:569-571`). | **Closed** |
| R6-6, R7-5 | minor | Deferred to the ProMotion and two-screen session | README "Before sending to Gerrit" | Deferrals still accepted. As the README says, M5 shouldn't go to Gerrit before that session. |

### R9-1: every transition, at S6

| Transition | Next frame | Evidence |
|---|---|---|
| Window moved to a fixed-rate display, or its display switched to a fixed mode | `hasVariableRefreshRate(q->screen())` is false, so the value is 0; the preference was ours, so it's reset | `_isResetWhenItNoLongerApplies` (hook off); `negative-noreset.log`, `negative-novrr.log` |
| Vertical sync turned off | `requestedFormat().swapInterval() == 0` gives 0, so it's reset. Same condition as `QCocoaWindow::updatesWithDisplayLink()` | same test |
| Player paused | The state check gives 0. The reset comes before the seek frame's own `requestUpdate()` | `_isNotSetWhilePaused`, `_isResetWhenPaused` |
| Player destroyed | `~QMediaPlayer` resets the sink's source (`qmediaplayer.cpp:225`), so the value is 0 and it's reset | `_isResetWhenItNoLongerApplies` |
| Player detached, or playback ended, with no further frame | The value stays until the next frame | Harmless: without frames the window requests no update (except the rare `beginFrame` retry, `:399-402`). Expose and resize render directly (`:529-533`). qtbase only takes windows with pending requests into account (`pendingRange()`) |
| Frames from a camera, screen capture or no source | 0, reset if ours; left alone if not | `_isNotSetWithoutMediaPlayer`, `_leavesAnotherPreferenceAlone`; `negative-noplayer.log`, `negative-overwrite.log` |
| Another component's preference, set before ours | Overwritten by the first qualifying frame, then reset to 0 when it stops applying, so the value is lost | code `:579-582`; R10-4 (nit, no such caller exists) |
| Another component's preference, set after ours | Overwritten or reset at the next frame | same |
| Window moved between two variable displays, e.g. 120 to 144 Hz | Recomputed for the new rate: 24 fps stays 24, 30 fps goes to 0 | per-frame evaluation |

---

## New findings

| ID | Severity | Title | Commit |
|---|---|---|---|
| R10-1 | minor | The cadence statement is off by one ("one frame in 1001", it's 1000), and content up to 0.2% faster than an exact rate is paced below its rate: one frame in 500 or more is never shown, undocumented | M5, README |
| R10-2 | minor | The ProMotion session checklist isn't actionable as written: agent-only path, the test windows open on the primary screen, no program, file or valid measuring method for items 3 and 4. It also lacks R9-1's real move | README |
| R10-3 | minor | The reviewed series exists only in volatile places: messages and trees list in `/tmp` (recreated at boot, cleaned daily), a temporary index in the agent's job directory, unreferenced tree objects | tooling |
| R10-4 | nit | "A preference that the window didn't set is left alone" only holds until the window sets its own | M5 |
| R10-5 | nit | Stale references and small wording issues | README, TESTING, M2 and M5 documents, M5 message, `qvideowidget.cpp` |

---

### R10-1: minor: the cadence statement is off by one, and slightly fast content loses frames

**Where (M5, and README):**

* `src/multimedia/qmultimediautils.cpp:75-77`: "one frame in 1001 is then shown twice as long
  (every 42 s at 23.976 fps); the tolerance allows at most one in 500";
* `s7-5.txt:24-25`;
* M5 document `:81` (and `:65-66`);
* README:257-258.

**Problem 1, the count.** 23.976 fps paced at exactly 24 Hz takes 24 × 1001/24000 = 1.001
refreshes per frame. That's one extra refresh every 1000 frames, so one frame in **1000** is shown
twice as long. The 1001 refreshes are what those 1000 frames take, 41.7 s, so "every 42 s" is
right. My round 9 text said 1000.

**Problem 2, the other side of the tolerance.**

* `qVideoPreferredFrameRate()` accepts `|multiple - n| <= 0.002 n` on both sides
  (`qmultimediautils.cpp:91`).
* For content slightly *faster* than the exact rate, say a 24.04 fps average, it returns 24.04.
  The multiple is 24/24.04 = 0.99834, within 0.2%.
* qtbase then paces 24.04 at 24: `forPreferredFrameRate()` computes
  `int(120 / (24.04 * 0.99)) = 5` refreshes, `qappleframerate.cpp:190-201`.
* 24.04 frames a second shown 24 times a second means one frame in about 600 is **never shown**.
  That's a drop, not a doubled frame.
* It happens where the window is alone on its display, on CoreAnimation's grid. When another
  window keeps the link at full rate, the per-window pacing doesn't drop it.
* Without M5, the full rate shows every frame.

**Evidence.** `/tmp/rv10/cadence.py` simulates a 24 or 30 Hz grid and counts how often each frame
is shown over 100,000 frames:

```
23.976 @ 24: frames 99998, never shown 0, once 99898, twice 100; one doubled per 1000.0 frames, one dropped per inf frames
29.97 @ 30: frames 99998, never shown 0, once 99898, twice 100; one doubled per 1000.0 frames, one dropped per inf frames
0.2% slow @ 24: frames 99998, never shown 0, once 99798, twice 200; one doubled per 500.0 frames, one dropped per inf frames
0.17% fast (24.04) @ 24: frames 99998, never shown 167, once 99831, twice 0; one doubled per inf frames, one dropped per 598.8 frames
```

**Why minor, not higher.**

* The effect is bounded: at most one frame in 500.
* It needs unusual averages. Constant-rate files are normally exact or 1000/1001. VFR phone
  clips can report averages like 30.02.
* It's the same size as the 23.976 doubling that round 8 accepted.
* But it's a frame drop for applications that didn't opt in, and it can be avoided at no cost.

**Fix, (a) preferred.**

* Accept only content at or below the exact multiple, keeping a relative slack of about 1e-6 for
  float rates like 25 × float(1.2) = 30.0000012:

  ```cpp
  multiple >= wholeMultiple * (1 - 1e-6) && multiple - wholeMultiple <= 0.002 * wholeMultiple
  ```

  23.976 and 29.97 still qualify.
* Add a row "0.1% faster than 24 fps at 120 Hz → 0".
* Document: "one frame in 1000 is shown twice as long (23.976, 29.97), and one in 500 at most".

**Fix, (b).** Keep the symmetric tolerance and document both effects: "one frame in 1000 is shown
twice as long for 23.976 and 29.97 fps, and content up to 0.2% faster than an exact rate doesn't
show one frame in 500 or more".

Either way, correct 1001 to 1000 in the four places.

**Resolved when** (a) or (b) is in M5, and the comment, message, M5 document and README say the
same.

### R10-2: minor: the ProMotion session checklist isn't actionable as written

**Where:** README:191-201. This is the gate for M5 (R9-4, and the README's own "Before sending
to Gerrit").

**Problems:**

1. **Item 1 path.** `$CLAUDE_JOB_DIR/tmp/vrr/vrr` only resolves in the agent's environment. In the
   user's shell the variable is unset, and the path becomes `/tmp/vrr/vrr`, which doesn't exist.
   The job directory isn't durable either. TESTING cites the same kind of path at :140, :153,
   :195 and :209.
   * Put `vrr.mm` into `wip-cadisplaylink/probes/`, as `divisors.m` is, with its build line:
     `clang -fobjc-arc -framework AppKit vrr.mm -o vrr`.
2. **Item 2: the screen the test uses.**
   * `tst_qvideoframebackend` creates `QVideoWindow window;` on the primary screen, the one with
     the menu bar.
   * With the G95SC as the main display, `_isOnlySetForVariableRefreshRate` runs on the fixed
     display, expects 0, gets 0 and passes. That proves nothing about the panel; only its `qInfo`
     ("false") gives it away.
   * Say: make the built-in panel the main display (System Settings, Displays, "Use as Main
     Display"), then check that the `qInfo` says `true`.
3. **Item 3: nothing to run, and no valid way to measure.**
   * Name the program, e.g. `examples/multimedia/videowidget` (a minimal QVideoWidget player), or
     a probe.
   * Name the 24 fps file, e.g.
     `ffmpeg -f lavfi -i testsrc2=size=1280x720:rate=24 -t 60 -pix_fmt yuv420p 24fps.mp4`.
   * Say how to see the *panel's* rate. A separate `CADisplayLink` probe votes for its own rate.
     Qt's `qt.qpa.screen.updates` log ("Setting display link frame rate ... to (24,24,24)") shows
     what Qt asks for, not what the panel does. If Quartz Debug is the tool, name the view, and
     check that it shows the refresh rate on macOS 27.
4. **Item 4: the latency, no method.** For example, the time from `QVideoWindow::setVideoFrame()`
   to its `UpdateRequest` render (debug timestamps in a local build), with the preference and
   without it (hook off).
5. **R9-1's move is missing.**
   * My R9-1 resolution asked for it: move a playing QVideoWidget from the panel to the G95SC and
     back.
   * `preferredFrameRate()` should go 24 → 0 → 24. A probe printing it every second is enough.
   * It's the one transition the hook can't simulate on this machine.

**Resolved when** the checklist has these five points, so that the user can run the session without
the agent.

### R10-3: minor: the reviewed series exists only in volatile places

**Evidence:**

* **The six messages.**
  * They're only in `/tmp/mm/s7-*.txt`. A grep of `wip-cadisplaylink/` for
    "The price is latency: alone on its display" (M5) or "Invalidate the display link in
    ~AVFDisplayLink" (M1) finds nothing.
  * The M documents have the Change-Ids and short tree hashes, not the messages.
* **`/tmp` doesn't survive a reboot, or a few days.**
  * `/private/tmp` was created at boot: birth time Sep 18 13:49:30, 26 s after `kern.boottime`
    (13:49:04). `/private/var/tmp` dates from Sep 17.
  * `com.apple.tmp_cleaner` runs every day at 00:00 (`/System/Library/LaunchDaemons`).
  * So a reboot (an OS update, for instance) loses the messages, the trees list, `commit-series5.sh`,
    `finish.sh`, `sign.sh`, both finish messages and the verification scripts, while signing is
    still blocked.
* **The trees.** They are unreferenced objects. `git gc` can prune them once `gc.pruneExpire` has
  passed.
* **The temporary index.**
  * `commit-series5.sh:11` (and `verify-states9.sh:9`) put it in
    `/Users/anthony.liot/.claude/jobs/328d9a96/tmp`, the agent job's directory.
  * If that directory is gone when the user runs `finish.sh`, `git read-tree` can't create the
    index. The script then stops with "working tree ... is not the final state". That fails safe,
    but the message is misleading.

**Fix:**

* copy `s7-*.txt`, `series5-trees.txt` and the scripts into `wip-cadisplaylink/pr/series/` (or a
  `tooling/` directory next to it). That's untracked and on disk, and the docs commit publishes it;
* protect the six trees with local refs, e.g. `git update-ref refs/wip/mm-series5/S<k> <tree>`.
  Refs can name trees: no commit, no signing;
* use `mktemp` for the temporary index;
* move the probe sources TESTING cites (`vrr`, `menuprobe`, `leakprobe`, `cycle`) to
  `wip-cadisplaylink/probes/`.

**Resolved when** the messages, the trees list and the scripts have a durable copy, and the commit
script doesn't depend on the job directory.

### R10-4: nit: the ownership claim holds only until the window sets its own preference

**Where:**

* `qvideowindow.cpp:577-582` ("leave a preference that someone else set alone");
* `s7-5.txt:37` ("A preference that the window didn't set is left alone");
* M5 document `:34-35`;
* the name `_leavesAnotherPreferenceAlone`.

**Problem.** `m_setPreferredFrameRate` is a bool.

* If something else sets P and a frame then qualifies, the window writes its own rate over P
  (`preferredFrameRate > 0`). When the rate stops applying, the window resets it to 0, and P is
  lost.
* A P set after the window's own value is overwritten, or reset, at the next frame.
* The test only covers "P set, no qualifying frame".
* Nothing sets a preference on a QVideoWindow today:
  * the only other caller in qtbase is `QWidget::create()`, for top-level widget windows;
  * QVideoWidget's window is a container child;
  * QML doesn't use QVideoWindow.

  So there's no user-visible effect.

**Fix.** Either change the wording, or keep the value.

* Wording: "It only resets a preference that it set itself; while it plays, its own replaces any
  other."
* Value: keep `qreal m_ownPreferredFrameRate`, and write only when `preferredFrameRate()` is 0 or
  still equals it.

### R10-5: nit

* **README:85-86 and :186-187** still name `series4-trees.txt` and `commit-series4.sh`.
  * `finish.sh` uses series5, which is correct.
  * `commit-series4.sh` would refuse the working tree, so that's safe but confusing.
* **Stale "Verified" sections.**
  * M5 document `:117` points at "Round 8"; it should be "Round 9".
  * M2 document `:44` says "Round 7", but its R8-3 results are in "Round 8".
* **`s7-5.txt:30-34`: "Elsewhere it's a minimum interval from the previous update request".**
  * On iOS the preference paces to the display as well.
  * iOS is excluded because it doesn't tell whether a display has a variable refresh rate. The
    code comment says so (`qvideowindow.cpp:97`).
  * Suggestion: "Where update requests are timer based, it's a minimum interval ...; iOS doesn't
    tell whether a display has a variable refresh rate."
* **`qvideowidget.cpp:39-45`.**
  * "refresh at the video's frame rate" is really "at the video's frame rate or a whole multiple
    of it": 12.5 fps asks for 25.
  * "The display then uses less power" would read better as "can use less power". It doesn't
    while other windows on that display animate, and possibly not with the AVFoundation backend
    (R6-6).
* **TESTING "Round 9", stress A/B.**
  * `/tmp/ab/r9`'s files have the mtimes of the S6 rebuild (03:44-03:45), which is after rounds 1
    and 2 (03:28-03:41).
  * So those two rounds ran with the libraries copied into `/tmp/ab/r9` at 03:28, a minute after
    the last negative check (03:27:21). No build log exists in between, so their QtMultimedia
    library may have had a negative-check variant of `qvideowindow.cpp`.
  * That doesn't matter for these rows: `tst_qmediaplayerbackend` runs no QVideoWindow code, and
    the plugins don't depend on that file. Still, say which libraries each round used.
* **`/tmp/mm/r9/-mock.log`** ("env: ./: Permission denied") is left over from a script slip.
  Delete it.

---

## Commit by commit: other checks, all found fine

* **M1 to M4.** Trees identical to round 8's, where I verified them. The messages are still
  accurate at their commits.
* **M5.**
  * The new `tests/auto/unit/multimedia/qvideowindow/` follows the module's conventions:
    * the standalone-test preamble;
    * `qt_internal_multimedia_add_test`, `LIBRARIES Qt::Gui Qt::MultimediaPrivate
      Qt::MockMultimediaPlugin`, like `qmediaplayer` and `qscreencapture`;
    * the license headers: `BSD-3-Clause` in CMake, `LicenseRef-Qt-Commercial OR GPL-3.0-only`
      in the test;
    * it's registered in `tests/auto/unit/multimedia/CMakeLists.txt:52`.
  * The files and the registration are all in S5, and S4 has none of them.
  * The mock player needs `setIsValid(true)` before `play()` and `pause()` change state, as
    tst_qmediaplayer uses it.
  * Both `init()` and `cleanup()` guard the hook with `QT_BUILD_INTERNAL`.
    * `init()` `QSKIP`s the whole test in non-developer builds. That's needed: the hook is only
      exported there (`Q_AUTOTEST_EXPORT`), and without it the tests would pass vacuously on a
      fixed display.
    * `cleanup()` resets the hook, and the `unique_ptr`s tolerate a skipped `init()`.
  * I checked the test's expectations on the displays it could run on:
    * 240 Hz gives 120;
    * 60 gives 30;
    * 75 gives 25;
    * 165 gives 55;
    * 59.94 gives 29.97;
    * a prime 61 gives 1.

    The "2.5 refreshes" rate gets no preference on each of them. On non-cocoa platforms every
    expectation is 0, and the cocoa-only functions skip.
  * The integration tests are non-vacuous here:
    * `_isSetDuringPlayback` requires a value > 0 on cocoa;
    * `_followsPlaybackRate` requires a change;
    * `_isResetWhenPaused` requires > 0, then 0 after a real paused seek;
    * `_isOnlySetForVariableRefreshRate` is the hook-less check, shown to fail with the display
      check bypassed.

    `FrameCounter` connects after QVideoWindow's own connection, so the preference is updated
    before the count, and the `QCOMPARE` after `QTRY_COMPARE_GT(counter.frames, before)` is
    deterministic.
* **M6.** Unchanged since round 8.
* **States and final suites.**
  * S5 (`states9/`): 20 and 20 passed on the two backends; tst_qvideowindow 7; tst_qvideowidget 8
    passed and 1 skipped; tst_qmultimediautils 302; 80 destruction rows.
  * S6 (`qtmm-results-s9/`): 22 passed and 1 skipped (two screens) on both backends; the M5
    functions all pass; the `qInfo` says "false".
  * The final darwin tst_qmediaplayerbackend has 5 duration rows (0.6 to 1.75 s over), and FFmpeg
    has 1 (loops 1, rate 2, 2394 ms for 500). They're in the known family: the Sep 28 20:27
    FFmpeg log in `/tmp/qtmm-results/` has 5 of the same rows (for example 2119 ms for 500), and
    none of these tests uses a QVideoWindow.
* **Tooling.**
  * `finish.sh` checks every input before the first signature, and runs `commit-series5.sh`.
  * `commit-series5.sh` stages each tested tree and checks it before and after committing, and it
    can be resumed.
  * `qtbase-docs.txt` and `qt5-pointers.txt` name no round.

---

## Verdict: APPROVE

Severity counts: blocker 0, major 0, minor 3, nit 2.

Round 9: R9-1, R9-2, R9-5 and R9-6 are closed. R9-3 is closed except for R10-1. R9-4 continues as
R10-2. The R6-6 and R7-5 deferrals are still accepted, with the README's own condition: M5 doesn't
go to Gerrit before the ProMotion session. If that session shows that the panel doesn't drop to the
video's rate with the FFmpeg backend, M5's trade-off (latency for power, on by default) has no
payoff, and M5 should be reconsidered.

Open, not blocking:

- R10-1: minor: "one frame in 1001" is one in 1000; content up to 0.2% faster than an exact rate drops one frame in 500 or more, undocumented (prefer an asymmetric tolerance) (M5, README)
- R10-2: minor: ProMotion session checklist not actionable (agent-only path, primary screen, no program, file or valid method for items 3 and 4), and R9-1's real move missing (README)
- R10-3: minor: messages, trees list and scripts only in `/tmp` (recreated at boot, cleaned daily) and the agent's job directory; trees unreferenced (tooling)
- R10-4: nit: the ownership claim holds only until the window sets its own preference (M5)
- R10-5: nit: stale series4 references, "Verified" sections, iOS wording in the M5 message, QVideoWidget doc wording, stress A/B library note, stray log (docs)
