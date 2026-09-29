# Round 9 review: qtmultimedia series (M1 to M6)

Reviewer: qt-cadisplaylink-pr-reviewer (independent, strict)
Repo: `qt5/qtmultimedia`, base upstream `635067497`. The series still isn't committed: it's recorded
as trees (`/tmp/mm/series4-trees.txt`), and the working tree equals S6 (`git diff 82bca915bf20` is
empty). Line numbers are at S6 unless noted otherwise.

| # | Tree | Subject | Round 8 items |
|---|---|---|---|
| M1 | S1 `47653cfd479b` | darwin: Don't leak the display link of AVFDisplayLink | none (unchanged since round 7) |
| M2 | S2 `e4ea5041e0f5` | darwin: Keep polling for video frames while menus and dialogs are open | R8-3, R8-7 |
| M3 | S3 `dcbc502d19c3` | darwin: Stop using the deprecated CVDisplayLink in AVFDisplayLink | none (test file carries M2's 3 lines) |
| M4 | S4 `84212c21c771` | Report the stream frame rate of played video frames | none (same) |
| M5 | S5 `8bf7a3a77fe6` | QVideoWindow: Let the display refresh at the video's frame rate | R8-1, R8-2, R8-4, R8-5, R8-7 |
| M6 | S6 `82bca915bf20` | darwin: Poll for video frames in sync with the display the video is on | R8-7 (comment) |

How I checked:

* **Patches, messages, documents.**
  * `git diff-tree -p` of each state against the previous one.
  * The round 7 to round 8 tree diffs: S2, S3 and S4 differ only by M2's 3 test lines. S5 and S6
    differ from the pre-stable-sort trees only by `std::stable_sort` and its comment.
  * `git diff-tree --check` on all six patches: clean.
  * The messages `/tmp/mm/s7-{1..6}.txt`: widths, blank line before each Change-Id, the IDs are
    unique.
  * `commit-series4.sh`, `finish.sh`, `sign.sh`, `qtbase-docs.txt`, `qt5-pointers.txt`,
    `verify-states8.sh`, `qtmm-run-s8.sh`.
  * The M1 to M6 documents, and the README and TESTING.md sections.
* **qtbase at the branch head (`f18df50a300`).**
  * `QWindow::setPreferredFrameRate()` (`qwindow.cpp:1348-1362`) and its documentation.
  * `QCocoaWindow::updatesWithDisplayLink()` (`qcocoawindow.mm:1926-1931`).
  * `QCocoaScreen::nativeScreen()` (`qcocoascreen.mm:1027-1042`).
  * `QScreen::resolveInterface()` and `QT_NATIVE_INTERFACE_RETURN_IF`: a `qstrcmp` and a
    `dynamic_cast`.
  * `QAppleFrameRateRange::forPreferredFrameRate()` and `shouldDeliverFrame()`.
* **The author's logs, read only.**
  * `/tmp/mm/states8/`, `/tmp/mm/r8/`, `/tmp/qtmm-results-s8/`, including run 2, which has
    finished.
  * The earlier full runs in `/tmp/qtmm-results-{s6,s5,final}/` and `/tmp/ab/base-full.log`.
  * The leak probe outputs, `menuprobe/main.mm`, `vrr/vrr.mm`, and `ioscheck/`.
* **My own scratch programs,** under `/tmp/rv9/`. None of them builds or writes anything in the
  qtmultimedia worktree, `qtmm-build` or `qt5-build-nofw`.
  * `stale/main.cpp` uses public API plus the exported autotest hook. It's built against the
    `qt5-build-nofw` headers and libraries, and shows no window.
  * An iOS simulator `-fsyntax-only` check of the final `avfdisplaylink.mm`.
  * Disclosure: both ran during the author's darwin run 2, at about 02:56 and 02:58. That's a
    one-file compile (a few seconds of one core), a probe run under 1 s with no playback, and one
    syntax check. See R9-5.

---

## Summary

The round 8 fixes are done in the right commits, and most of them are done well:

* **R8-2.** Only a `QMediaPlayer`'s frames get a rate, through a private `QVideoSink::source()`.
  `~QMediaPlayer` resets the sink's source (`qmediaplayer.cpp:225`, `qmediaplayer_p.h:80-81`), so
  the raw pointer can't dangle.
* **R8-3.** The run loop mode test skips off the cocoa platform (`tst_qvideoframebackend.cpp:365-366`).
* **R8-4.** Rates below a frame an hour get no preference, so `qRound` sees at most
  1000 / 2 × 3600 = 1.8e6.
* **R8-5.** The playback tests are non-vacuous on every display. I worked through the
  expectations at 50, 60, 75, 120, 144 and 240 Hz.
* **R8-6** and **R8-7** are fixed. I reproduced the iOS syntax check at the final state.

The autotest hook is acceptable in Qt: qtbase has `Q_AUTOTEST_EXPORT void
qt_setQtEnableTestFont(bool)`. It's guarded by `QT_BUILD_INTERNAL` in both tests and reset by RAII
or `qScopeGuard`. Dropping iOS is the conservative choice, and I accept it.

But the R8-1 fix makes the preference depend on the window's display, and nothing resets it when
the display stops qualifying:

* **R9-1 (blocker, M5).** A video window that moves from a ProMotion panel to a fixed-rate
  external monitor keeps the preference it had, for the rest of its life. The same happens when
  the display is switched to a fixed rate, or vertical sync is turned off. My probe shows the value
  staying at 24 for 24 fps frames, for 25 fps frames, with no frame, and with the player detached.
  qtbase then paces a stale 24 at 30 Hz on a 60 Hz monitor. So 24 fps film holds one frame of every
  four for 67 ms, where the 60 Hz cadence never holds one longer than 50 ms. That's R7-1's judder,
  on exactly the displays R8-1's fix was meant to leave alone. The laptop plus external monitor
  setup is the common case.

The minors:

* **R9-2.** The preference also applies while the player is paused, so seek frames are paced on
  the content's grid.
* **R9-3.** Gaps and inaccuracies in the trade-off documentation.
* **R9-4.** `hasVariableRefreshRate()` has never been observed returning true. The ProMotion and
  two-screen session looks feasible on this machine and should cover it.
* **R9-5.** The `(video, playing)` stress rows failed in both round 8 final runs and in none of the
  four earlier full runs.

R9-6 is nits.

---

## Round 8 findings

| ID | Round 8 severity | Response | Verified at S6 | Status |
|---|---|---|---|---|
| R8-1 | blocker | Fixed in M5: variable refresh rate displays only, iOS dropped, trade-off documented | `qvideowindow.cpp:98-106`, `qavfhelpers.mm:172-177`. By reading, `_isOnlySetForVariableRefreshRate` does guard the fix: bypass the helper in `setsPreferredFrameRate()` and it fails on this display (it expects 0 and would get the exact rate). That's a different negative check from the one the author recorded, see R9-6. The AppKit probe, `vrr-probe.txt`, says this display is fixed rate (min = max = 4.167 ms). | **Closed for a window that stays on one kind of display.** The transition isn't handled: R9-1 (blocker). Documentation gaps: R9-3 |
| R8-2 | major | Fixed in M5: `QMediaPlayer` sources only | `qvideowindow.cpp:566-573`. The negative check (`negative-checks.log`): `_isNotSetWithoutMediaPlayer` gets 120 instead of 0 without the source check. The M5 document's line about sources is updated. | **Closed.** The same premise, "a player's frames arrive at the stream's rate", fails while paused: R9-2 |
| R8-3 | minor | Fixed in M2 | `tst_qvideoframebackend.cpp:365-366`. The S2 state includes `qguiapplication.h` (M2 patch). Offscreen: ffmpeg 10 passed and 2 skipped with that message, darwin 5 passed and 7 skipped (`/tmp/mm/r8/offscreen-*.log`). | **Closed** |
| R8-4 | minor | Fixed in M5 | `qmultimediautils.cpp:80`, and the rows for a frame an hour (1 Hz), a frame every two hours (none) and 1e-12 fps (none). 34 rows in `/tmp/qtmm-results-s8/tst_qmultimediautils-mock.log`. | **Closed** |
| R8-5 | minor | Fixed in M5 | `tst_qvideoframebackend.cpp:460-484` and `:600-611`. The rates I worked out: [24, 30, ...] at 240 Hz, [30, 20, ...] at 60, [24, 18, ...] at 144, [24, 30, ...] at 120, [25, 15] at 75, and [25] at 50, where `_followsPlaybackRate` skips. The first expectation is required to be > 0 on cocoa. `_followsPlaybackRate` requires a change. `std::stable_sort` makes the tie at 60 Hz deterministic. | **Closed** |
| R8-6 | minor | Fixed | `finish.sh:7-11` checks every input first, `qtbase-docs.txt` exists, and it runs `commit-series4.sh`. BSD `sed -n 0p` prints nothing and returns 0, so a fresh start resolves to the base. | **Closed** (message wording: R9-6) |
| R8-7 | nit | Fixed | "use the main screen" (`avfdisplaylink.mm:98-99`, M6). The platform name is read per call (`qvideowindow.cpp:101`). M2's message has the iOS paragraph. The default and common mode logs are kept. The menu probe (`menuprobe/main.mm`) uses a real `popUpMenuPositioningItem:` and a real `runModalForWindow:`, and its outputs match TESTING. iOS: my own `xcrun --sdk iphonesimulator clang++ -fsyntax-only -target arm64-apple-ios17.0-simulator -fno-objc-arc -Wall -Wextra` of the final `avfdisplaylink.mm` against `qt5-build-cadisplaylink-ios` passes with no output. Live resize is in "Not run". | **Closed** (evidence wording: R9-6) |
| R6-6 | minor | Deferred: ProMotion measurement | README "Before sending to Gerrit" | Deferral still accepted. It's now the only evidence that M5 does anything, see R9-4 |
| R7-5 | minor | Deferred: two-screen manual run | README "Before sending to Gerrit" | Accepted. Same session as R9-4 |

---

## New findings

| ID | Severity | Title | Commit |
|---|---|---|---|
| R9-1 | blocker | The preference isn't reset when the window's display stops qualifying (moved to a fixed-rate display, display switched to a fixed rate, vertical sync off): it stays for the window's life, and qtbase paces it on the new display (R7-1 judder or dropped frames, R8-1 latency) | M5 |
| R9-2 | minor | The preference applies while the player is paused, so seek frames (scrubbing) wait for the content-rate grid and are capped at the content rate | M5 |
| R9-3 | minor | The trade-off documentation is incomplete or inaccurate: "once every 500 frames", no doubled frame in README, 29.97, "30 fps anywhere", the darwin backend's decode link, no public doc note | M5, README |
| R9-4 | minor | `hasVariableRefreshRate()` has never been observed returning true; the ProMotion and two-screen session looks feasible here and should list the concrete checks | M5, README |
| R9-5 | minor | The `(video, playing)` stress rows failed in both round 8 final runs and passed in all four earlier full runs; record run 2 and A/B them against upstream | TESTING |
| R9-6 | nit | Two new lines over 100 columns, evidence wording, round numbers in the finish messages, check order | M5, TESTING, tooling |

---

### R9-1: blocker: the preference isn't reset when the display stops qualifying

**Where:** M5, `src/multimedia/video/qvideowindow.cpp:566-574`. This is the only place in
qtmultimedia that writes the property (`grep -rn "setPreferredFrameRate" src/`).

```cpp
    if (d->setsPreferredFrameRate()) {
        ...
        setPreferredFrameRate(qVideoPreferredFrameRate(frameRate, refreshRate));
    }
```

**Problem.** When `setsPreferredFrameRate()` turns false after having been true, the value set
while it was true is never touched again. `setsPreferredFrameRate()` is `false` when:

* `hasVariableRefreshRate(q->screen())` is false. That's the case after the window moves to a
  fixed-rate screen, a display is unplugged, the lid is closed in clamshell mode, or the display's
  refresh rate is set to a fixed value in System Settings (ProMotion to 60 Hz, or an external
  "Variable" mode to a fixed one);
* the swap interval is 0.

**Evidence.** `/tmp/rv9/stale/main.cpp` uses a `QVideoWidget` with a `QMediaPlayer`, FFmpeg backend,
no window shown. The hook stands in for the variable refresh rate display. Without it, AppKit
reports this display as fixed, as a real move to a fixed display would.

```
platform cocoa, screen Odyssey G95SC at 240.000 Hz
variable refresh rate display, 24 fps frame: preferredFrameRate 24
fixed refresh rate display, 24 fps frame:    preferredFrameRate 24
fixed refresh rate display, 25 fps frame:    preferredFrameRate 24
fixed refresh rate display, no frame:        preferredFrameRate 24
fixed refresh rate display, player detached: preferredFrameRate 24
swap interval 0, 24 fps frame:               preferredFrameRate 24
```

**What qtbase does with the stale value.** It maps it for the new display with
`forPreferredFrameRate()` (`qappleframerate.cpp:174-202`): the slowest exact rate not below it.

| Left over | New display (fixed) | Paced at | Content | Result |
|---|---|---|---|---|
| 24 | 60 Hz, the usual external monitor | 30 Hz | 24 fps | one frame in four shown for 67 ms. Without the preference, 60 Hz shows every frame for 33 or 50 ms. That's R7-1 |
| 24 | 60 Hz | 30 Hz | 25 fps (next file) | every fifth frame shown for 67 ms (R7-1) |
| 24 | 240 Hz | 24 Hz | 25 fps | 24 deliveries a second for 25 frames: one frame a second is never shown |
| 24 | 165 Hz | 33 Hz | 24 fps | uneven cadence |
| 24 | 75 or 100 Hz | 25 Hz | 24 fps | one frame a second shown twice as long |
| 30 (29.97 content) | 144 Hz | 36 Hz | 29.97 fps | uneven cadence |
| any | any fixed display | the preferred rate | at that rate | R8-1's grid: up to one frame of added delay (A/V offset), on the displays R8-1's fix exempts |

**Why blocker.**

* It's a regression for applications that don't use the feature, and they can't opt out. It
  affects every QVideoWidget application on a MacBook Pro with a fixed-rate external monitor, the
  most common Mac laptop setup, as soon as a video window crosses from the built-in panel.
* It lasts for the window's life, whatever is played next.
* It brings back R7-1 and R8-1, both blockers, on fixed-rate displays.
* The M5 message says the opposite (`s7-5.txt:16-18`): "for every frame, so it follows the window to
  other screens". So do the code comment (`qvideowindow.cpp:563-565`) and the M5 document ("on
  fixed ones, none at all", `:44`; "Elsewhere the property isn't touched", `:32`).

**Fix.** Compute 0 where the conditions don't hold, and always set the result. When the value is
unchanged, `QWindow::setPreferredFrameRate()` returns early (`qwindow.cpp:1356-1357`), so this costs
nothing. `QVideoWindow` is private and nothing else sets its preference.

```cpp
    qreal preferredFrameRate = 0;
    if (d->setsPreferredFrameRate()) {
        ... // as now
        preferredFrameRate = qVideoPreferredFrameRate(frameRate, refreshRate);
    }
    // Also where it no longer applies, e.g. after moving to a fixed-rate display
    setPreferredFrameRate(preferredFrameRate);
```

If you'd rather keep "isn't touched" literally, remember whether the window set a non-zero value
and reset only that.

**Resolved when:**

* The fix is in M5.
* M5 has a test that fails without it, under `QT_BUILD_INTERNAL`:
  * with the hook on, a frame at the exact rate sets it;
  * with the hook off, the next frame gives `platformPacesToTheDisplay() && hasVariableRefreshRate(screen) ? exact : 0`,
    so 0 here;
  * the same after turning vertical sync off once a preference is set. Today's vertical sync check
    (`tst_qvideoframebackend.cpp:535-540`) starts from 0, so it can't catch this.
* The message, the code comment and the M5 document say what happens on the transition.
* S5 and S6 are re-verified.
* In the R9-4 session: a playing QVideoWidget moved from the built-in panel to the Odyssey reads
  `preferredFrameRate() == 0` after the move.

### R9-2: minor: the preference applies while the player is paused

**Where:** M5, `qvideowindow.cpp:567-570`. The rate is `streamFrameRate() * |playbackRate()|`
whatever the player's state. `QMediaPlayer::playbackRate()` stays at the set rate while paused.

**Problem.**

* The comment's premise, "a media player's frames, which arrive at the stream's frame rate"
  (`:560`), only holds in `PlayingState`.
* While paused, every `setPosition()` delivers a frame. `tst_qmediaplayerbackend::seekPauseSeek`
  (`:2606-2612`) requires that on every backend.
* So scrubbing a paused 24 fps video with a seek slider, on a ProMotion display, goes like this:
  * each seek frame waits for the next tick of the window's 24 Hz grid: 0 to 42 ms, 21 ms on
    average (R8-1's measurement);
  * seek frames arriving faster than 24 a second are coalesced.
* Without the preference, which is upstream's behavior and what fixed displays get, a seek frame
  waits at most one refresh (8.3 ms at 120 Hz), and scrubbing can update at up to the refresh
  rate.
* Scrubbing traverses media time faster than real time, so more distinct frames exist than the
  content rate. The cap is visible in editors and players with a seek bar.

**Fix:**

* only while `player->playbackState() == QMediaPlayer::PlayingState`, otherwise 0. Combined with
  R9-1's fix, the first seek frame after pausing resets it, before its own `requestUpdate()`;
* add a test with a paused player (hook on): a frame gives 0;
* adjust the comment and the M5 document.

**Rebuttal I'd accept:** a measured trace showing that seek frames while paused aren't delayed or
capped.

### R9-3: minor: the trade-off documentation is incomplete or inaccurate

Round 8 asked for three things to be documented: the wait for the grid, the doubled frame every
42 or 33 s, and jitter near a tick. What's there:

* **`qmultimediautils.cpp:75-76`** says: "Within 0.2%, so that 23.976 and 29.97 count as 24 and 30:
  a frame is then shown longer once every 500 frames."
  * For 23.976 and 29.97, which are 0.1% off, it's once every 1000 frames, 42 s and 33 s. Every 500
    frames is only the 0.2% limit.
  * Where the preference applies, that frame is shown for two frame intervals, not just "longer".
  * The comment contradicts the M5 message, which says "every 42 seconds".
  * I flagged this sentence in round 8 (R8-1, "claims more than holds"), and it's unchanged.
* **README "Known limitations"** (`:245-246`) has the wait for the grid, but not the doubled frame
  at 23.976 and 29.97 fps. That's the headline content, and the message and document have it.
* **The M5 message and document** mention 23.976 only, not 29.97 (every 33 s). They don't mention
  arrival jitter near a tick. That part was a model, not a measurement, so either document it as
  modelled or say why it's left out.
* **README `:100`** says "30 fps anywhere". 30 fps is exact at 60, 120 and 240 Hz, but not at 75,
  100, 144 or 165 Hz, and 144 and 165 Hz are common Adaptive-Sync refresh rates. Say "30 fps at 60,
  120 and 240 Hz".
* **The darwin backend.**
  * M6's decode link runs at the screen's maximum rate (R6-6). On ProMotion that probably keeps the
    panel at 120 Hz while an AVFoundation-backend video plays.
  * So with that backend, M5's latency is paid without the refresh rate reduction it's for.
  * M5's "Limits" and README should say so. The M5 document's "There the trade is power for that
    latency" (`:64`) only holds for FFmpeg, the default backend.
* **Public documentation.**
  * Applications can't opt out, and the behavior changes the video's latency on variable refresh
    rate displays.
  * So a `\note` in the QVideoWidget documentation would be appropriate: on macOS displays with a
    variable refresh rate, it asks the display to refresh at the video's frame rate when the
    display shows that rate evenly, and frames may then be shown up to one frame interval later.

**Resolved when** these are corrected, or rebutted item by item.

### R9-4: minor: `hasVariableRefreshRate()` has never been observed returning true

**Problem.**

* M5 now only does something where `QAVFHelpers::hasVariableRefreshRate()` is true.
* It has only run on this fixed-rate display (the test's `qInfo`: false). Every test of the "true"
  branch goes through the hook.
* The author's disclosure is right: `_isOnlySetForVariableRefreshRate` follows the helper by design,
  and nothing checks that the helper says true on ProMotion or Adaptive-Sync. If AppKit reported
  min = max for the built-in panel in its default mode, M5 would be dead code.
* R6-6's measurement is also still the only evidence that the preference lowers the panel rate at
  all.

**Feasibility.**

* TESTING has a "2026-09-26, 120 Hz ProMotion built-in display" section, run on this M5 Max
  machine. So the built-in panel seems to be available when the user is at the machine and the lid
  is open.
* With it and the Odyssey both on, you have one variable and one fixed display. That's R9-1's setup,
  and M6's two screens (R7-5).

**Fix.** Make README "Before sending to Gerrit" list the concrete checks for that session:

1. `vrr` on the built-in panel, and `_isOnlySetForVariableRefreshRate`'s `qInfo` there, without the
   hook;
2. the panel rate while a 24 fps video plays, with both backends (R6-6; see R9-3 about the darwin
   backend);
3. R9-1's move;
4. `videoWindow_receivesFrames_afterMovingToAnotherScreen` and the M6 debug check (R7-5).

M5 shouldn't go to Gerrit before item 1 at least.

### R9-5: minor: the stress rows failed in both round 8 final runs

**Evidence.** `grep "stressTest_setupAndTeardown.*(video, playing)"` over the saved full darwin runs:

| Run | `setupAndTeardown` | `_keepAudioOutput` | `_keepVideoOutput` |
|---|---|---|---|
| upstream full (`/tmp/ab/base-full.log`) | pass | pass | pass |
| before M1's destructor line (`qtmm-results-final`) | pass | pass | pass |
| round 6 final (`qtmm-results-s5`) | pass | pass | pass |
| round 7 final (`qtmm-results-s6`) | pass | pass | pass |
| round 8 final, run 1 | **fail** (5100 ms would have done) | **fail** | pass |
| round 8 final, run 2 (251 passed, 7 failed) | pass | pass | **fail** |

**What I accept.**

* The attribution is plausible.
  * The symptom is a playback start just over the 5 s `QTRY` timeout, the known slow-start family.
  * The rows move between runs.
  * They pass 12/12 alone (`stress-alone.log`).
* I checked the code path.
  * The darwin plugin is unchanged since round 7's final state except a comment.
  * tst_qmediaplayerbackend uses no QVideoWindow, so none of M5's code runs. The only window is a
    `QQuickView`, `:4084`.
  * M5's `QVideoSink` change is a private accessor.
* So round 8's changes can't be the cause.
* Run 2's remaining failures are also the known families: the 5 `invalidHttpsAddress` rows,
  `stressTest_setupAndTeardown_keepVideoOutput(video, playing)`, and
  `destruction_doesNotDeadlock_afterMediaPlayerCall(AVM_none)`.

**What's missing.**

* A new failure family on a regression suite, in 2 runs of 2, and on 0 runs of 4 before, deserves
  more than "the code didn't change".
* The four clean runs include one of upstream and three of the series' own plugin code. So this
  doesn't separate "the series" from "this machine tonight" either.

**Fix:**

* record run 2 in TESTING, replacing the "PENDING" entry;
* run a short interleaved A/B of the three `(video, playing)` stress rows, upstream against final
  (`/tmp/ab/swap.sh`), for example four runs each. They take about a minute per run;
* note that my probe build and run overlapped run 2 (see "How I checked"). It's unlikely to
  matter, but you should know.

### R9-6: nit

* **Over 100 columns** (Qt's limit), both new in M5:
  * `qavfhelpers.mm:174` is 101 characters;
  * `tst_qvideoframebackend.cpp:552` is 102.
* **`/tmp/mm/r8/negative-checks.log`.**
  * It shows `videoWindow_preferredFrameRate_followsTheDisplay()`, the test's earlier name.
    TESTING (`:97`) names `_isOnlySetForVariableRefreshRate`.
  * It doesn't say which breakage produced which line.
  * The meaningful negative check for R8-1 is missing: bypass the helper in
    `setsPreferredFrameRate()`, and the test fails. It's easy to add.
* **TESTING `:109`, the FFmpeg row of the menu table.** The probe's lambda has no context object,
  so FFmpeg frames are counted on the renderer thread, not on the main thread like the darwin rows.
  Say so, or connect with `&sink` as context.
* **The finish messages.** `qtbase-docs.txt` says "review rounds 4 to 8", and `qt5-pointers.txt`
  says "the round 8 series". Update them when the series changes for R9-1.
* **Check order.** `setVideoFrame()` asks AppKit about the screen (`NSScreen.screens`, device
  descriptions) for every frame, before the cheaper player check. That's cheap (microseconds a
  frame), but checking the player first would skip AppKit for camera and screen capture sources.

---

## Commit by commit: other checks, all found fine

* **M1.** Identical to rounds 7 and 8. Leak probe 0 observers and 0 links at every state
  (`leakprobe/S{1..5}.heap`, `S6-r8.heap`; the same pattern finds 20 and 20 in `upstream-pools.heap`).
* **M2.** The skip comes after the media check. The `CFStringRef` is released before the check. The
  S2 state has the include. The message is at most 71 columns, and its iOS paragraph is accurate:
  `UITrackingRunLoopMode` is in the common modes, and Qt's iOS dispatcher delivers there.
* **M3, M4.** Unchanged patches. The messages are still accurate at their commits.
* **M5.**
  * `setsPreferredFrameRate()` uses the same condition as `QCocoaWindow::updatesWithDisplayLink()`
    (`requestedFormat().swapInterval()`).
  * The helper is safe:
    * a null screen gives false;
    * so does a non-cocoa screen, through the `dynamic_cast`;
    * so does a disconnected display (`nativeScreen()` is nil);
    * it's only called on the GUI thread (the sink's signal is queued);
    * it doesn't reference AppKit classes (only messages), so QtMultimedia needs no new link
      dependency;
    * `minimum`/`maximumRefreshInterval` exist from macOS 12 on.
  * Per-frame cost: a `QString` copy, a `QSurfaceFormat` copy, a `qstrcmp`, a `dynamic_cast`, a
    short `NSScreen.screens` scan, a qobject_cast and a loop of at most 1000 modulo steps. That's
    fine.
  * `QVideoSink::source()`: a private non-virtual member with a friend in a public header, so
    binary compatible, and `\internal`.
  * On iOS and the other platforms, `setsPreferredFrameRate()` returns false, and nothing else
    changes.
  * The hook in `qvideowindow_p.h` is inside the Qt namespace. Its definition is unconditional:
    in non-developer builds it's an unexported function, and the check is a static bool read.
* **M6.** Comment only since round 8.
* **Messages.** Lines at most 71 columns, summaries at most 70, a blank line before each
  Change-Id, six distinct Change-Ids. M5's only inaccuracy is R9-1's sentence.
* **States.** `/tmp/mm/states8/` matches TESTING:
  * S1 13 passed, S2 and S3 15, S4 16, S5 21, on both backends;
  * tst_qmultimediautils 302 passed at S5 (34 table rows), and tst_qvideowidget 8 passed and 1 skipped;
  * destruction rows 80, 78, 79, 79 and 80 passed.

  S5 was rerun after the `stable_sort` change: the logs are from 02:09-02:10, the trees file from
  02:07. The rerun didn't recompile `qavfhelpers.mm` or `qmultimediautils.cpp`, which is correct,
  as they're the same in S5 and S6. The final build linked the library at 02:10:50, after the
  sources were restored at 02:10:40.

## The final-state suites (question 5)

* tst_qvideoframebackend: 23 passed and 1 skipped (two screens) on both backends. Every M2, M4, M5
  and M6 function ran.
* QML, widgets and mock suites: as TESTING says.
* The 13 darwin tst_qmediaplayerbackend failures of run 1, and the 7 of run 2, are:
  * the 5 `invalidHttpsAddress` rows (FormatError instead of ResourceError, the same upstream);
  * duration rows (run 1 only);
  * destruction slow starts;
  * the stress slow starts.

  I accept the attribution to known timing families for the first three, which have the upstream
  A/B. I accept it provisionally for the stress rows, pending R9-5's A/B.

## Note for the qtbase reviewer (carried from round 8)

The `QWindow::preferredFrameRate` documentation (`qwindow.cpp:1278-1347`) still doesn't say that a
window alone on its screen is delivered on a fixed grid at the preferred rate, whose phase is
CoreAnimation's. So content timed by another clock waits up to one interval. VIDEO.md advises video
applications to set the property and doesn't mention it either. For goal 2 ("a video app must be
able to really use it"), that belongs in the documentation, or in the "No public frame timing"
limitation.

---

## Verdict: REQUEST CHANGES

Severity counts: blocker 1, major 0, minor 4, nit 1.

Round 8:

* R8-2 to R8-7 are closed.
* R8-1 is closed for windows that stay on one kind of display, with its transition gap as R9-1.
* The R6-6 and R7-5 deferrals are still accepted, with R9-4.

Open findings:

- R9-1: blocker: the preference isn't reset when the window's display stops qualifying (moved to a fixed-rate display, display set to a fixed rate, vertical sync off). It stays for the window's life (probe: 24 kept for 25 fps frames, no frame, detached player), and qtbase paces it on the new display: R7-1 judder or dropped frames, R8-1 latency (M5)
- R9-2: minor: the preference applies while the player is paused, so seek frames wait for the content-rate grid and are capped at the content rate (M5)
- R9-3: minor: trade-off documentation: "once every 500 frames" (1000 for 23.976 and 29.97, shown twice as long), no doubled frame in README, 29.97 and jitter missing, "30 fps anywhere", the darwin backend's decode link voids the gain, no public doc note (M5, README)
- R9-4: minor: `hasVariableRefreshRate()` has never been observed returning true; list the concrete checks for the ProMotion and two-screen session, which looks feasible on this machine (M5, README)
- R9-5: minor: the `(video, playing)` stress rows failed in both round 8 final runs and in none of the four earlier ones; record run 2 and A/B them against upstream (TESTING)
- R9-6: nit: two new lines over 100 columns, negative-check log names a renamed test and lacks the helper-bypass check, the FFmpeg menu row counts on the renderer thread, round numbers in the finish messages, check order (M5, TESTING, tooling)
