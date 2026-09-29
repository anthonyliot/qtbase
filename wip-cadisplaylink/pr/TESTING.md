# Test results

All on macOS 27.2, Apple M5 Max, debug developer builds (see README "Building and testing").
"Activation" failures are `QTest::qWaitForWindowActive()` failing because another application
(the terminal, or the user) has focus; they fail the same way on the unmodified baseline
(`qt5-build-cadisplaylink/baseline-tst_qwindow.txt`) and pass when nothing else has focus.

## qtmultimedia, 2026-09-28, 240 Hz display (Odyssey G95SC, the only display, fixed rate)

`qtmm-build` against `qt5-build-nofw` (README "Building and testing"). The probes are in
`probes/qtmultimedia/`, the verification scripts in `pr/qtmultimedia-series/verify/`
(`verify-states.sh`, `run-suites.sh`, `leak.sh`, `ab-swap.sh`); the logs cited below are in `/tmp`
and don't survive a reboot. "Upstream" is `635067497`,
built in the same directory from the upstream sources, its four libraries swapped in and out
(`/tmp/ab/swap.sh` then, `pr/qtmultimedia-series/verify/ab-swap.sh` now), so both run the same test
binaries.

### Suites on the final state

Round 11 final state S6 `f4801ada7da2`, with `pr/qtmultimedia-series/verify/run-suites.sh` (logs
`/tmp/qtmm-results-s11/`, every test binary checked to be newer than its source):

| Suite | darwin | ffmpeg |
|---|---|---|
| tst_qvideoframebackend | 22 passed, 1 skipped (two screens) | 22 passed, 1 skipped |
| tst_qmediaplayerbackend | 249 passed, 9 failed (the 5 `invalidHttpsAddress`, 3 slow starts: `multipleMediaPlayback`, 2 `destruction` rows; `finiteLoops(No pause, fast rate)`), 50 skipped | 293 passed, 2 failed (`server.listen()`, sandbox), 16 skipped |
| tst_qquickvideooutput | 20 passed | 20 passed |
| tst_qquickvideooutput_window | 3 passed | 3 passed |

Mock backend: tst_qvideowindow 7; tst_qvideowidget 8 passed, 1 skipped; tst_qmediaplayerwidgets 5;
tst_qvideoframe 779; tst_qvideoframeformat 61; tst_qmediaplayer 126; tst_qmultimediautils 307.
Leak probe (20 players, pools): 0 observers, 0 display links. `finiteLoops(No pause, fast rate)`
(4 loops counted instead of 3 at 5x) had passed in all earlier full runs; A/B of `finiteLoops`, 5
interleaved runs each (`/tmp/mm/r11/finiteloops-*.log`): upstream failed that same row once, the
series `(Pause, fast rate)` once: a flaky fast-rate check (the test itself notes trouble on macOS,
QTBUG-111744).

Round 10 final state S6 `80569af10b23`: round 10 only changed M5 (the ownership of the preference,
the tolerance for faster rates, their tests, docs), so the suites M5 touches were rerun there (logs
`/tmp/mm/r10/final-*`): tst_qvideoframebackend 22 passed, 1 skipped on both backends;
tst_qvideowindow 7; tst_qvideowidget 8 passed, 1 skipped; tst_qmultimediautils 304. The rest is
round 9's full run below, on code that is the same outside those files.

Round 9 final state S6 `bd632ac19db0`, logs `/tmp/qtmm-results-s9/` (every test binary checked to be
newer than its source):

| Suite | darwin | ffmpeg |
|---|---|---|
| tst_qvideoframebackend | 22 passed, 1 skipped (two screens) | 22 passed, 1 skipped |
| tst_qmediaplayerbackend | 248 passed, 10 failed (the 5 `invalidHttpsAddress`, 5 duration rows), 50 skipped | 292 passed, 3 failed (`server.listen()` x2, sandbox; 1 duration row), 16 skipped |
| tst_qquickvideooutput | 20 passed | 20 passed |
| tst_qquickvideooutput_window | 3 passed | 3 passed |

Mock backend: tst_qvideowindow 7 passed; tst_qvideowidget 8 passed, 1 skipped;
tst_qmediaplayerwidgets 5; tst_qvideoframe 779; tst_qvideoframeformat 61; tst_qmediaplayer 126;
tst_qmultimediautils 302 passed. Leak probe (20 players, pools): 0 observers, 0 display links. The
duration rows are the family of the upstream A/B below (FFmpeg's too: the round 6 baseline had
them fail upstream).

Round 8 final state S6 `82bca915bf20`, logs `/tmp/qtmm-results-s8/` (every test binary checked to be
newer than its source):

| Suite | darwin | ffmpeg |
|---|---|---|
| tst_qvideoframebackend | 23 passed, 1 skipped (two screens) | 23 passed, 1 skipped |
| tst_qmediaplayerbackend | 245 passed, 13 failed, 50 skipped (see below); run 2: 251 passed, 7 failed | 293 passed, 2 failed (`server.listen()`, sandbox), 16 skipped |
| tst_qquickvideooutput | 20 passed | 20 passed |
| tst_qquickvideooutput_window | 3 passed | 3 passed |

Mock backend: tst_qvideowidget 8 passed, 1 skipped; tst_qmediaplayerwidgets 5; tst_qvideoframe
779; tst_qvideoframeformat 61; tst_qmediaplayer 126; tst_qmultimediautils 302 passed. Leak probe
(20 players, pools): 0 observers, 0 display links.

The 13 darwin failures are the families of the upstream A/B below: the 5 `invalidHttpsAddress`, 3
duration rows, and 5 slow starts (position unchanged after 5 s: 3 `destruction` rows and, for the
first time, `stressTest_setupAndTeardown(video, playing)` and `_keepAudioOutput(video, playing)`).
Those two passed in every earlier full run, upstream's included, and pass 12/12 run alone on this
build. The darwin plugin code these tests run didn't change in round 8 (a comment only). A second
full run (`tst_qmediaplayerbackend-darwin-run2.log`): 251 passed, 7 failed: the 5
`invalidHttpsAddress` and 2 slow starts (`stressTest_setupAndTeardown_keepVideoOutput(video,
playing)`, `destruction…(AVM_none)`).

Round 7 final state (`0b2e8b2222e6`, logs `/tmp/qtmm-results-s6/`): the same, except darwin
tst_qmediaplayerbackend 249 passed, 9 failed (the 5 `invalidHttpsAddress`,
`pause_playback_resumesFromPausedPosition`, 3 duration rows) and 21 passed in
tst_qvideoframebackend.

Round 6 final state (`3b2fda1ab1a4`, logs `/tmp/qtmm-results-s5/`), for reference:

| Suite | darwin | ffmpeg |
|---|---|---|
| tst_qvideoframebackend | 18 passed, 1 skipped (two screens) | 18 passed, 1 skipped |
| tst_qmediaplayerbackend | 252 passed, 6 failed (the 5 `invalidHttpsAddress`, 1 `destruction_doesNotDeadlock` start over 5 s), 50 skipped | 293 passed, 2 failed (`server.listen()`, sandbox), 16 skipped |
| tst_qquickvideooutput | 20 passed | 20 passed |
| tst_qquickvideooutput_window | 3 passed | 3 passed |

Mock backend (the mock plugin overrides `QT_MEDIA_BACKEND`, so one run, R7-6): tst_qvideowidget 8
passed, 1 skipped; tst_qmediaplayerwidgets 5 passed; tst_qvideoframe 779, tst_qvideoframeformat 61,
tst_qmediaplayer 126 passed.

Before M1's destructor line (`92ecf663`, logs `/tmp/qtmm-results-final/`) the results were the
same, except darwin tst_qmediaplayerbackend: 248 passed, 10 failed (the 5 `invalidHttpsAddress`,
3 duration rows, `multipleMediaPlayback`, 1 `destruction` row), 1230 s against 1096 s. One run
each, so no conclusion is drawn from the difference.

### Round 7 changes

Logs `/tmp/mm/r7/`.

* `tst_qmultimediautils`: 299 passed, including the 31 rows of
  `qVideoPreferredFrameRate_returnsRateWithEvenCadence` (M5).
* `tst_qvideoframebackend`, after the tests used the player's actual playback rate: 19 passed,
  1 skipped (two screens), 3 runs on each backend. The first ffmpeg run, before that, failed twice:
  25 × float(1.2) = 30.0000012 against 30, and once a 0 in `_isSetDuringPlayback` that didn't
  reproduce in 4 later full runs (one with debug output showing 30 throughout).
* Run loop modes (M2): `playback_deliversFrames_whileRunLoopIsInMode` passes on both backends. With
  the display link put back in the default mode only (the code before M2), the darwin backend got
  1 frame in event tracking mode and 0 in modal panel mode, in 1 s of 25 fps video. The reviewer's
  AppKit probe (`/tmp/rv7/modes.mm`, rerun): 0 callbacks in those modes with the default mode, about
  237 per second in every mode with the common modes.
* Offscreen platform (R6-2 residual, and a timer platform for R7-2), the new and changed functions
  by name, as a pre-existing test (`toImage_returnsImage_whenCalledFromSeparateThread…`) aborts the
  full run by dereferencing the unloaded test URL:
  * darwin backend: 3 passed, 6 skipped. It never loads media on the offscreen platform (stuck in
    LoadingMedia, as upstream), so only the synthetic-frame test runs; it expects and gets no
    preference. No crash.
  * ffmpeg backend: 8 passed, 1 skipped (two screens), all expecting no preference.
  * `tst_qvideowidget::preferredFrameRate_followsStreamFrameRate`: passes.

### ProMotion panel, 2026-09-29 (the built-in display, the only one then)

README checklist steps 1 to 3, logs `/tmp/mm/promotion/`:

1. AppKit: "Built-in Retina Display: max 120 fps, refresh interval min 0.008333 s, max 0.041667 s ->
   variable"; CoreGraphics 120.000 Hz. `hasVariableRefreshRate()` is true for the first time.
2. `tst_qvideoframebackend` (the final state's build): 22 passed, 1 skipped (two screens) with both
   backends; `_isOnlySetForVariableRefreshRate` logs "display with a variable refresh rate: true"
   and gets its non-zero preference without the autotest hook.
3. The viewprobe, 1280x720 test clips made with ffmpeg's `testsrc2`, frames per second and the
   window's preference:

   | clip | backend | frames per second | preferredFrameRate |
   |---|---|---|---|
   | 24 fps | FFmpeg | 24 (25 in the first second) | 24.000 |
   | 24 fps | AVFoundation | 24 (25 once) | 24.000 |
   | 25 fps | FFmpeg | 25 (26 once) | 0.000 (no exact rate at 120 Hz) |

Not run yet: steps 4 and 5 (the panel's rate and the latency, with Instruments), 6 and 7 (the
G95SC wasn't connected).

### Round 11 changes

Logs `/tmp/mm/r11/`. `tst_qmultimediautils` 307 passed (3 rows for displays just below a whole
rate: 30 fps at 59.94 Hz and 24 fps at 119.88 Hz get none, 23.976 fps at 119.88 Hz gets 23.976);
`tst_qvideowindow` 7 (the other component resetting to 0, then the window setting its own again);
`tst_qvideowidget` 8 passed, 1 skipped; `tst_qvideoframebackend` 22 passed, 1 skipped on both
backends. The playback tests now pick their rates from the actual refresh rate, which this 240 Hz
display can't exercise for 59.94: the reviewer's round 12 check ran the exact test code against
the function for 97,651 float refresh rates from 23.5 to 1000 Hz, with float and double playback
rates: always a non-zero expectation, and two different ones for `_followsPlaybackRate`
(`/tmp/rv12/rates.cpp`). The display:
the reviewer's AppKit probe once read "max 120 fps" for the G95SC while CoreGraphics said 240 Hz;
rechecked afterwards, AppKit says max 240 fps, refresh interval 4.167 ms fixed, CoreGraphics
240.000 Hz. Qt uses CoreGraphics' rate, which all the tests here read.

### Round 10 changes

Logs `/tmp/mm/r10/`. `tst_qmultimediautils` 304 passed (a row for content 0.1% faster than 24 fps,
none, and one for 25 fps played at `float(1.2)`, 30.0000012, accepted); `tst_qvideowindow` 7 passed
(the extended `_leavesAnotherPreferenceAlone`). Negative checks (`negative-r10.log`): round 9's
ownership rule back fails `_leavesAnotherPreferenceAlone` (120 replaced 12.3); the symmetric
tolerance back fails the 0.1% faster row (24.024 instead of none).

### Round 9 changes

Logs `/tmp/mm/r9/`.

* `tst_qvideowindow` (new, mock backend): 7 passed (5 tests). `tst_qvideowidget` 8 passed, 1
  skipped; `tst_qmultimediautils` 302 passed; `tst_qvideoframebackend` 22 passed, 1 skipped on
  both backends, including the real-backend `_isResetWhenPaused` (pause, seek, the seek's frame
  resets the preference). All test binaries checked to be newer than their sources.
* Negative checks (`negative.py`, `negative-*.log`): each change broken on purpose, the Multimedia
  library rebuilt, the tests run:

  | Broken on purpose | Tests that fail |
  |---|---|
  | no reset once it no longer applies (R9-1) | `_isResetWhenItNoLongerApplies`, `_isNotSetWhilePaused`, `_isSetForRatesTheDisplayShowsExactly`, `_isResetWhenPaused` |
  | any playback state (R9-2) | `_isNotSetWhilePaused`, `_isResetWhenPaused` |
  | the display check bypassed (R8-1) | `_isResetWhenItNoLongerApplies`, `_isOnlySetForVariableRefreshRate` (real playback on this fixed display) |
  | any source (R8-2) | `_isNotSetWithoutMediaPlayer`, `_isResetWhenItNoLongerApplies`, `_leavesAnotherPreferenceAlone` |
  | overwriting another preference | `_leavesAnotherPreferenceAlone` |

* Real menu probe, frames now counted on the main thread (R9-6: the lambda had no context object,
  so FFmpeg's were counted on its renderer thread): darwin 30 in the menu, 26 in the modal
  session, 25 normally; FFmpeg 31, 26, 25 (`menuprobe-mainthread.txt`).
* Stress rows A/B (R9-5): `stressTest_setupAndTeardown`, `_keepAudioOutput` and `_keepVideoOutput`
  (5 rows each, 50 players per row), darwin backend, interleaved with upstream's libraries
  (`stress-ab.sh`, logs `stress-*.log`). The failing rows are always `(video, playing)`, a playback
  start slower than 5 s:

  | Run | Upstream | Series (round 9) |
  |---|---|---|
  | 1 | 0 failed | 1 (`keepAudioOutput`) |
  | 2 | 1 (`keepVideoOutput`) | 1 (`keepAudioOutput`) |
  | 3 | 2 (`setupAndTeardown`, `keepAudioOutput`) | 0 |

  Upstream fails them as often. Libraries (R10-5): "upstream" is `/tmp/ab/base`, built from
  `635067497` in this build directory; "series" is `/tmp/ab/r9`, the round 9 build, stashed before
  S5's verification for runs 1 and 2 and again after the final build for run 3 (the same code).
  (The third round was meant as two; a zsh variable holding "3 4" isn't split into words, so it
  ran once, labelled "#3 4".)

### Round 8 changes

Logs `/tmp/mm/r8/`. The display here has a fixed refresh rate: AppKit reports "Odyssey G95SC: max
240 fps, refresh interval min 0.004167 s, max 0.004167 s" (`probes/qtmultimedia/vrr/vrr.mm`, no Qt),
and `QAVFHelpers::hasVariableRefreshRate()` says false for it, as the test logs.

* `tst_qmultimediautils`: 302 passed (34 rows of the cadence table, 3 new for tiny rates, R8-4).
* `tst_qvideoframebackend`: 23 passed, 1 skipped (two screens) on both backends. The preference
  tests use `qt_setVideoWindowAssumesVariableRefreshRate()`, except
  `_isOnlySetForVariableRefreshRate`, which checks that this display gets no preference.
* Negative checks, with the code broken on purpose and rebuilt (`negative-checks.log`):
  * without the media player check, `_isNotSetWithoutMediaPlayer` fails (120 instead of 0), R8-2;
  * with `hasVariableRefreshRate()` always true, `_isOnlySetForVariableRefreshRate` still passes: it
    follows the helper by design; the helper's answer is the AppKit probe's above.
* Run loop modes (R8-7): the default-mode run is kept, `modes-test-default-mode.log` (0 and 0
  frames, fails) and `modes-test-common-modes.log` (passes).
* Real menu and modal session (`probes/qtmultimedia/menuprobe`, AppKit and Qt): 25 fps video, frames
  in 1 s of an open `NSMenu` (`popUpMenuPositioningItem:`, cancelled by a common-mode timer), of
  `-[NSApp runModalForWindow:]`, and of the normal event loop:

  | darwin plugin | menu open | modal session | normal |
  |---|---|---|---|
  | display link in the default mode (before M2) | 1 | 0 | 26 |
  | in the common modes (M2) | 30 | 25 | 25 |
  | FFmpeg backend (no display link), for reference | 31 | 25 | 26 |

* Offscreen platform: darwin backend 5 passed, 7 skipped (media never loads there), ffmpeg backend
  10 passed, 2 skipped: the run loop mode test now skips off the cocoa platform (R8-3).
* iOS (R8-7): `avfdisplaylink.mm`, the file with the UIKit branches, syntax-checked for the iOS
  simulator (SDK 27.2, `-target arm64-apple-ios17.0-simulator`, MRC) against the iOS qtbase headers
  (`qt5-build-cadisplaylink-ios`) and the macOS build's moc output, at upstream, S1, S2, S3 and the
  final state: no errors, no warnings. Not a build of the iOS plugin (there's no iOS qtmultimedia
  build here).

### Upstream A/B of the darwin tst_qmediaplayerbackend failures

The darwin failures of the full run were `invalidHttpsAddress` x5 (fail upstream too: FormatError
instead of ResourceError), `play_playbackLastsForTheExpectedTime` rows (0.6-1.2 s too long),
`multipleMediaPlayback` and `destruction_doesNotDeadlock_afterMediaPlayerCall` rows (position still
0 after 5 s). None of these tests uses a window, so the series' window code doesn't run in them,
and on macOS 27 upstream already used the same main-screen CADisplayLink. Interleaved runs of
those three functions (`/tmp/ab/abab.sh`, logs `/tmp/ab/`), then the whole suite upstream:

| Run | Upstream | Mine |
|---|---|---|
| targeted 1 | 6 failed (4 duration, 2 position) | 3 failed (3 position) |
| targeted 2 | 1 failed (position) | 3 failed (1 duration, 2 position) |
| targeted 3 | 0 failed | 2 failed (2 duration) |
| targeted 4 | | 3 failed (3 duration) |
| full suite | 188 passed, 9 failed (the 5 `invalidHttpsAddress`, 3 duration rows), then **hung** in `destruction_doesNotDeadlock_afterMediaPlayerCall(AMV_setSourceNull)` until the 300 s watchdog aborted it | 248 passed, 10 failed, completed (2 runs) |

Same failure families on both; the rows differ from run to run, and upstream's overruns were the
largest (2000 ms expected, 4122 ms). Playback starts slower than 5 s in 3 of 234 upstream and 5 of
312 of my targeted starts. Conclusion: pre-existing darwin timing flakiness on this machine, not
the series.

### AVFDisplayLink leak (M1)

`leakprobe` (`probes/qtmultimedia/leakprobe`, `count.sh`): 20 media players with a QVideoSink, one
after the other, each playing `colors.mp4` until its first frame, then destroyed; `heap(1)` counts
the live objects after. "Pools": each player in its own autorelease pool, as an event loop
iteration of an application would drain it.

| Build | DisplayLinkObserver | CADisplayLink |
|---|---|---|
| upstream | 20 | 20 |
| upstream, pools | 20 | 20 |
| series without M1's destructor line | 20 | 20 |
| same, pools | 20 | 20 |
| final (with M1) | 0 | 20 (autoreleased, invalidated, in the never drained root pool: the players are created outside the event loop) |
| final, pools | **0** | **0** |

A standalone MRC probe (`probes/qtmultimedia/cycle/probe.mm`) shows the cause: a target released by
its owner isn't deallocated while its display link exists (retain count 2 after creating the link),
and `-[CADisplayLink invalidate]` deallocates it.

### Decode clock and preferred rate (M5, M6)

`probes/qtmultimedia/viewprobe`: a QVideoWindow playing a 25 fps file with the AVFoundation backend,
frames counted over 1 s shown, 1 s hidden, 1 s shown again (the first rows in round 6, when every
stream rate was asked for; the last on the round 8 final state, `/tmp/mm/r8/viewprobe-final.txt`):

| Build | Shown | preferredFrameRate | Hidden | Shown again |
|---|---|---|---|---|
| final design (window's screen link) | 25 | 25.000 | 25 | 25 |
| round 6 design (NSView link, R6-4) | 25 | 25.000 | 0 | 25 |
| upstream | 24 (a 1 s window starting mid-stream, ±1) | 0 | 25 | 24 |
| round 8 final state | 26 | 0.000 (25 fps isn't exact, and this display's rate is fixed) | 25 | 25 |

With `QT_QPA_PLATFORM=offscreen` (R6-2): runs without crashing; 0 frames, like upstream (also on
the round 8 final state).

### Series states

Each state of `pr/qtmultimedia-series/trees.txt` (round 11; S1 to S4 are the trees of round 8,
verified then), materialized in the worktree, built (the libraries, both plugins and the tests
below, no warnings in the changed files) and tested with `/tmp/mm/verify-states8.sh` and, for S5,
`pr/qtmultimedia-series/verify/verify-states.sh`, which also removes the files a state doesn't have
yet and reconfigures (logs `/tmp/mm/states8/`, `/tmp/mm/states11/`; earlier versions of S5,
`9bb38750eba3` in round 9 and `9d6582f3ca7b` in round 10, passed the same way). The leak probe runs
20 players with autorelease pools. The `destruction` column is QtTest's totals for
`tst_qmediaplayerbackend::destruction_doesNotDeadlock_afterMediaPlayerCall` (darwin): its 78 rows (6
destruction orders x 13 calls) plus `initTestCase` and `cleanupTestCase`, so "80 passed" is every
row; the failures are playback starting slower than 5 s, the known flake (upstream A/B above).

| State | Leak probe (observers / links) | tst_qvideoframebackend darwin, ffmpeg | destruction rows | Other |
|---|---|---|---|---|
| S1 `47653cfd479b` | 0 / 0 | 13, 13 passed (upstream's tests) | 80 passed | |
| S2 `e4ea5041e0f5` | 0 / 0 | 15, 15 passed (+ run loop modes) | 78 passed, 2 slow starts | |
| S3 `dcbc502d19c3` | 0 / 0 | 15, 15 passed | 79 passed, 1 slow start | |
| S4 `84212c21c771` | 0 / 0 | 16, 16 passed (+ stream frame rate) | 79 passed, 1 slow start | |
| S5 `7fb32794b550` | 0 / 0 | 20, 20 passed (+ the 4 real-playback preference tests) | 80 passed | tst_qvideowindow (mock) 7 passed; tst_qvideowidget (mock) 8 passed, 1 skipped; tst_qmultimediautils 307 passed |
| S6 `f4801ada7da2` | the final state, above | | | |

S5 changed in round 9 (the reset, the playing state, the new `tst_qvideowindow`); in round 8 it
was verified at `b3c446be11b3` and `8bf7a3a77fe6` (21 and 21 passed, `tst_qmultimediautils` 302,
every `destruction` row). S1 to S4 didn't change. Round 7's
states (`/tmp/mm/series3-trees.txt`, logs `/tmp/mm/states7/`) passed the same way.

Two pitfalls of the verification, both caught by its checks: a state is only complete if every file
the series touches gets the state's content (the first round 7 run left a file at the previous
state's content, and the tree check refused it); and in this build directory `cmake --build` without
targets doesn't rebuild the tests, so they're built by name and checked to be newer than their
sources (a first round 7 final run had used a stale test binary, and was redone).

## Review round 1 fixes, 2026-09-28, 240 Hz display

### Soak under load (R1-2)

20 consecutive runs of every wall-clock test on the round 1 heads, while another workload (a Metal
shader build, a dozen `applegpu-nt` processes, not ours) kept the machine loaded. Per run: 43
tst_qwindow rows (display link and frame rate), 3 Widgets functions (`pacedUpdates` x2,
`pacedUpdatesSemantics`, `pacedUpdatesAfterRecreate`), 2 Qt Quick functions
(`stepsWithPreferredFrameRate`, `animatorDurationWithPreferredFrameRate`). Raw log:
`/tmp/r1/soak-results.txt`, per-run logs in `/tmp/r1/soak/`.

| Runs | Load averages (1, 5, 15 min) | Result |
|---|---|---|
| 1-19 | from 29.7/82.4/147.6 to 216.7/225.8/247.4 | all passed |
| 20 | 109.1/104.0/147.6 | tst_qwindow passed; Widgets skipped `pacedUpdates` (window got covered); `animatorDurationWithPreferredFrameRate` failed waiting for the animation |

Run 20's failure was the window being covered (the Widgets test skipped for that reason just
before): a covered window isn't rendered, so its Animator never finishes, and the test waited 5 s
before checking exposure. Fixed to skip in that case (qtdeclarative, staged; see below).

Before these fixes, on the same loaded machine: `requestUpdateRate` measured 130.9/s for 240 and
`requestUpdateMultipleWindows` 186.5/s, failing the old 80% bound.

### Other checks

* `tst_qappleframerate`: 151 passed (15 new delivery and preference cases).
* Full `tst_qquickwindow` 127 passed, 1 skipped; full `tst_qquickanimations` 73 passed.
* Reviewer's `/tmp/rvw/latency` (R1-3): driven window latency median 0.008 ms in both orders (was
  33.34 ms when visited before the driving window).
* Stall recovery (R1-1), simulated with a temporary patch ignoring a link's callbacks after 100: the
  manual test stopped at t≈0.9 s, "stopped delivering update requests. Recreating it" at t≈1.9 s,
  240 fps from the next sample. No false positives in 4 s runs with `--rate 1`, `--rate 30`,
  default.
* iOS simulator (iPhone 18 Pro, iOS 27): `tst_qappleframerate` 151 passed; `tst_qwindow` display
  link and frame-rate tests 39 passed, 5 skipped (60 Hz simulator: 24 and 60 not both exact; no
  timer path; no nested loops on iOS; one screen; swap interval 0).

### The Gerrit series after review round 2 (R2-2)

Rebuilt from scratch on the base with `/tmp/r2/series.sh`, each state's tree recorded
(`/tmp/r2/series-trees.txt`) and then committed with `/tmp/r2/replay.sh`, which refuses a commit
whose tree differs from the tested one. Machine load during the run: 1-minute load average from 117
to 594 (another build).

| Commit | Build | Tests at that commit |
|---|---|---|
| G1 | QtGui, cocoa plugin, tst_qwindow | 7 delivery functions pass (9 with init/cleanup) **on the old CVDisplayLink plugin** |
| G2 | cocoa plugin, tst_qwindow | 9 pass (+ driven window, nested loop); the link reports its interval |
| G3 | QtGui | doc only |
| G4 | QtGui, cocoa plugin, tst_qwindow | 11 pass (+ property, timer pacing) |
| G5a | QtGui, tst_qappleframerate | 151/151 |
| G5b | not built here (iOS sources only) | iOS at the final state, below |
| G5c | cocoa plugin, tst_qwindow, tst_qappleframerate | display link and frame-rate tests: 43 passed, 1 skipped (two screens) |
| G6 | QtGui, Widgets, tst_qwidgetrepaintmanager | 18 passed, 1 failed (`scrollWithOverlap`, `qWaitForWindowActive`, focus) |
| G7 | displaylink, standalone against the series build | `--rate 30`: 30.0/s on 240 Hz |

The final state equals the snapshot of the wip branch's files (checked file by file).

### The Gerrit series, first version (round 1, superseded)

Separate worktree and build (`qt5-series-build`: Debug developer build, non-framework, tests on
demand, sql/network/dbus/printsupport off).

| Commit | Build | Tests at that commit |
|---|---|---|
| G1 | QtGui, cocoa plugin, tst_qwindow | 5 delivery tests pass **with the old CVDisplayLink plugin** |
| G2 | cocoa plugin, tst_qwindow | 9 delivery tests pass (+ driven window, nested loop) |
| G3 | QtGui | doc only |
| G4 | QtGui, cocoa plugin, tst_qwindow | 11 pass (+ property, timer pacing) |
| G5 | QtGui, cocoa plugin, tst_qwindow, tst_qappleframerate | tst_qappleframerate 151/151; tst_qwindow 43 passed, 1 skipped (two screens) |
| G6 | Widgets, tst_qwidgetrepaintmanager | 18 passed, 1 failed (`scrollWithOverlap`, `qWaitForWindowActive`, focus) |
| G7 | displaylink (standalone, against the series build) | `--rate 30` → 30.0/s |
| D1 | qtdeclarative (`qt5-series-build-qtdeclarative`, configured with the non-framework qtbase, whose tree is G7's) | `stepsWithPreferredFrameRate`, `animatorDurationWithPreferredFrameRate` pass; full tst_qquickanimations 73/73 |
| D2 | tst_qquickwindow | `preferredFrameRateFromQml`, `preferredFrameRateRevision`, `preferredFrameRateOwnProperty` pass. The full suite had 56 activation failures (`qWaitForWindowActive`, `requestActivate`, `isActive`) while other windows had focus; it passed 127/127 on the wip branch when nothing else was in front |

The D2 tree is the qtdeclarative wip branch plus the staged "Skip the Animator duration test when
covered" change. Note: add-on modules built against an uninstalled qtbase write their libraries
into its prefix, so the series and the main qtdeclarative build share `qt5-build-nofw/lib`; their
sources only differ in doc comments and the qquickwindow tests.

The G7 tree is identical to `wip/cadisplaylink` without `wip-cadisplaylink/` (`git diff --cached
wip/cadisplaylink -- . ':(exclude)wip-cadisplaylink'` is empty). Signing of the series commits G2
onwards is pending (AppleConnect); the tested states are recorded as file lists
(`/tmp/r1/series-g*.files`) and intermediate files (`/tmp/r1/g2/`, `/tmp/r1/tst_qwindow.g*.cpp`).

## 2026-09-28, 240 Hz external display (Odyssey G95SC), before round 1

| Suite | Result |
|---|---|
| tst_qappleframerate | 136 passed |
| tst_qwindow | 106 passed, 3 failed (activation/cursor: activateDeactivateEvent, enterLeaveOnWindowShowHide x2), 8 skipped (platform-specific, and preferredFrameRatePerScreen: one screen) |
| tst_qwidgetrepaintmanager | 17 passed, 2 failed: scrollWithOverlap (activation), pacedUpdates(QRhiWidget) once ("not unpaced after resetting the preference"; 0 failures in 14 reruns, and the check now reports the rates and skips if the window was covered) |
| tst_qquickwindow | 119 passed, 8 failed (all activation; the user was using the machine), 1 skipped |
| tst_qquickanimations | 73 passed |
| animatorDurationWithPreferredFrameRate + stepsWithPreferredFrameRate, 10 runs | 0 failures |

Before commit 30 (supported rates), `tst_qwindow::preferredFrameRateApi(25)` failed on this
display: Qt asked for 240 / 9 = 26.67, the system delivered 30.

## 2026-09-26, 120 Hz ProMotion built-in display

| Suite | Result |
|---|---|
| tst_qappleframerate | 123 passed (before commit 30) |
| tst_qwindow | 106 passed, 3 failed (activation, same as baseline), 7 skipped |
| tst_qwidgetrepaintmanager | 19 passed |
| tst_qquickwindow | 127 passed, 1 skipped |
| tst_qquickanimations | 72 passed |
| animatorDurationWithPreferredFrameRate, 15 runs | 0 failures (after the settle fix; 3 in 18 before) |

## iOS simulator (iPhone 18 Pro, iOS 27, 60 Hz), 2026-09-26

| Suite | Result |
|---|---|
| tst_qappleframerate | 123 passed |
| tst_qwindow (display link and frame-rate tests) | 39 passed, 5 skipped (60 Hz: 24 and 60 not both exact; no timer path; nested loops; one screen; swap interval 0) |

## Not run

* `preferredFrameRatePerScreen` (needs two screens connected at once).
* The stall (R1-1) on the ProMotion panel, and a CVDisplayLink A/B of it (panel not connected).
* A display ID change (R1-4): reasoned, not triggered.
* Wayland/xcb/Windows: the timer-path pacing test has only run on cocoa (it's in the allow-list).
* Real-mouse live resize with the event tap removed.
* qtmultimedia: an iOS build of the darwin plugin (only a syntax check of `avfdisplaylink.mm`); a
  live resize with the AVFoundation backend (menus and modal sessions were probed); a display with a
  variable refresh rate (none connected: M5's preference is only exercised through the autotest
  hook); two screens for M6.
