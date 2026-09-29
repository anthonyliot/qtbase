# Round 8 review: qtmultimedia series (M1 to M6)

Reviewer: qt-cadisplaylink-pr-reviewer (independent, strict)
Repo: `qt5/qtmultimedia`, base upstream `635067497`. The series isn't committed yet: it's recorded as
trees (`/tmp/mm/series3-trees.txt`), and the working tree equals S6. Line numbers are at S6 unless
noted otherwise.

| # | Tree | Subject | Round 7 items |
|---|---|---|---|
| M1 | S1 `47653cfd479b` | darwin: Don't leak the display link of AVFDisplayLink | none (unchanged) |
| M2 | S2 `5d2e99e0524e` | darwin: Keep polling for video frames while menus and dialogs are open | R7-3 (new commit) |
| M3 | S3 `9c3e0622edbf` | darwin: Stop using the deprecated CVDisplayLink in AVFDisplayLink | R7-3 (message) |
| M4 | S4 `46dc9110c930` | Report the stream frame rate of played video frames | R7-4, R7-8 |
| M5 | S5 `b7495084410a` | QVideoWindow: Let the display refresh at the video's frame rate | R7-1, R7-2 |
| M6 | S6 `0b2e8b2222e6` | darwin: Poll for video frames in sync with the display the video is on | R7-5, R7-7, R7-8 |

How I checked:

* **Patches, messages and documents.**
  * `git diff-tree -p` of each state against the previous one, and the diff from round 7's final
    tree to this one.
  * The messages `/tmp/mm/s7-{1..6}.txt`, and the scripts `commit-series3.sh`, `finish.sh`,
    `verify-states7.sh`.
  * The M1 to M6 documents, and the README and TESTING.md sections.
* **qtbase at the branch head.**
  * `qappleframerate.cpp`: the rate mapping.
  * `qcocoawindow.mm`: `requestUpdate()`, `updatesWithDisplayLink()`.
  * `qcocoascreen.mm`: `requestUpdate()`, `deliverUpdateRequests()`, `setDisplayLinkFrameRate()`.
  * `qplatformwindow.cpp`: the timer path.
  * `qioswindow.mm` and `qiosscreen.mm`.
  * The event dispatchers: `qcocoaeventdispatcher.mm`, `qeventdispatcher_cf.mm`, and
    `qoffscreenintegration.cpp`.
  * `QGuiApplication::platformName()`, `QWindow::setPreferredFrameRate()`, and `qRound`
    (`qnumeric.h`).
* **The author's logs, read only.**
  * `/tmp/mm/states7/`: I checked the list of test functions each state ran.
  * `/tmp/mm/r7/`.
  * The S6 logs written so far in `/tmp/qtmm-results-s6/`.
* **My own scratch programs**, in `/tmp/rv8/`. None of them touches the qtmultimedia worktree,
  `qtmm-build` or `qt5-build-nofw`.
  * `policy.cpp` copies `qVideoPreferredFrameRate()` and qtbase's `forPreferredFrameRate()`. It
    checks the 31 unit rows, the M5 document table, a sweep of 6.4 million (fps, Hz) pairs, and tiny
    rates.
  * `unpause.mm` uses AppKit only, with no window. It measures when a CADisplayLink with a (24, 24,
    24) range fires after it's unpaused.
  * `grid.py` simulates frame delivery with and without a preference, on the measured grid, with
    arrival jitter.
  * `offscreen_modes.cpp` is built against `qt5-build-cadisplaylink` and run on the offscreen and
    minimal platforms only. It checks whether `CFRunLoopRunInMode` delivers Qt's posted events.
  * `vrr.mm` reads the NSScreen refresh interval range of this display.

---

## Summary

The round 7 fixes are done as asked, and done well:

* **M2** fixes R7-3 in its own commit, before the CVDisplayLink removal. Its test fails without the
  fix, which is consistent with my round 7 probe.
* **M5's policy function is right.** My copy:
  * passes the 31 unit rows;
  * reproduces the M5 document table;
  * in a sweep of 6.4 million (fps, Hz) pairs over 32 refresh rates (23.976 to 1000 Hz, fractional
    ones included), always returns a rate that qtbase's mapping paces exactly, always the slowest
    one, and misses no exact rate.
* **The platform condition** is the same as `QCocoaWindow::updatesWithDisplayLink()`, and iOS
  always paces through its display link. The author's argument for evaluating the rate per frame
  instead of on `screenChanged` holds.
* **The per-state evidence** is now recorded and matches the logs.

But the exact-rate policy I proposed in round 7 isn't free, and I missed that then.

* **R8-1 (blocker, M5).** A preference puts a video window that's alone on its screen on a fixed
  grid at the preferred rate. CoreAnimation keeps that grid's phase across pause and unpause (I
  measured it), and the phase doesn't depend on the video clock. So:
  * a frame waits for the next tick: on average half a video frame instead of half a refresh, and
    up to a whole frame;
  * 23.976 fps film shows a frame for twice its duration every 42 s;
  * arrival jitter near a tick drops frames.

  On fixed-rate displays nothing is gained in exchange. That includes this 240 Hz display, most
  external monitors, the MacBook Air, and iPhones and iPads without ProMotion.
* **R8-2 (major, M5).** A camera reports its format's maximum rate, which it doesn't always
  deliver. So a camera preview in a QVideoWidget in low light gets R7-1's judder.
* The minors (R8-3 to R8-6) are a test that fails off the cocoa platform, a `qRound` overflow,
  tests that can pass trivially, and `finish.sh`. R8-7 is a nit.

---

## Round 7 findings

| ID | Round 7 severity | Response | Verified at S6 | Status |
|---|---|---|---|---|
| R7-1 | blocker | Fixed in M5: `qVideoPreferredFrameRate()` | `qmultimediautils.cpp:67-92`, `qvideowindow.cpp:545-552`. `policy.cpp`: 31/31 rows, the M5 table reproduced, and the sweep described in the summary (every result paced exactly by qtbase, always the slowest, none missed). The message no longer says "wastes power". | **Closed as specified.** But the policy I specified has a cost of its own, now R8-1 and R8-2 |
| R7-2 | major | Fixed in M5: only on `ios`, and `cocoa` with vsync | `qvideowindow.cpp:84-88`, the same test as `qcocoawindow.mm:1926-1931`. iOS always uses its display link (`qioswindow.mm:435-438`). On visionOS the plugin is also named "ios", but its screen has no display link and update requests aren't delivered, as before. The offscreen runs expect and get no preference (`/tmp/mm/r7/offscreen-ffmpeg.log`). `QCocoaWindow` still falls back to its timer while the screen can't deliver: during a nested event loop in delivery, a stalled link, or an offline screen (`qcocoascreen.mm:290-301`, `:402-406`). That's transient and acceptable. | **Closed** |
| R7-3 | major | Fixed in the new M2, and in M3's message | `avfdisplaylink.mm:62-73`. Qt delivers the posted event in the common modes on cocoa (`qcocoaeventdispatcher.mm:784`, `:801`) and on iOS (`qeventdispatcher_cf.mm:190`). For iOS the change is safe: Qt's own iOS link stays in the default mode, so frames fetched during UIKit tracking are rendered when it ends, as before. The "1 and 0 frames" failing run wasn't saved, but my round 7 probe measured 0 callbacks in those modes with the default mode. | **Closed.** The test's platform check is R8-3; wording is in R8-7 |
| R7-4 | minor | Test added in M4 | `tst_qvideoframebackend.cpp:389-417`. It fails without M4 (0 is not 25) and is skipped for the backends that don't report the rate. It's in S4's log. | **Closed** |
| R7-5 | minor | Comment, document, README | The comment now says it catches a broken recreation, not a missing one. The M6 document lists the gaps. The two-screen manual run is in README "Before sending to Gerrit". | **Closed** |
| R7-6 | minor | Every state built and tested; the mock rows fixed | `/tmp/mm/states7/` matches TESTING.md, and each state ran exactly its own functions: S1 upstream's, S2 and S3 add the two mode rows, S4 the stream rate test, S5 the three preference tests. No warnings in the changed files. See also R8-6: the first pass of the S6 run used a stale binary. | **Closed for S1 to S5.** S6 is pending (in progress, not counted) |
| R7-7 | nit | `m_window` as is | `qquickvideooutput.cpp:471-475` | **Closed** |
| R7-8 | nit | Wording; QTBUG and Pick-to left for the Gerrit decision | M4 names FFmpeg and AVFoundation, M6 says "On macOS" and "iOS is unchanged", `avfdisplaylink.mm:123` says "uses". The constructor comment (`:98-99`) still says "follow". Leaving the QTBUG and Pick-to to the author is fine. | **Closed.** The remainder is in R8-7 |
| R6-6 | minor | Deferred: ProMotion measurement | Still in README "Before sending to Gerrit" | Deferral still accepted. After R8-1 the ProMotion measurement matters more. |

---

## New findings

| ID | Severity | Title | Commit |
|---|---|---|---|
| R8-1 | blocker | An exact-rate preference puts the video on a fixed grid: up to a frame of extra video delay, a doubled frame every 42 s at 23.976 fps, frames dropped with arrival jitter, and nothing gained on fixed-rate displays | M5 |
| R8-2 | major | Cameras report their format's maximum rate; a camera in low light delivers fewer frames, which the preference paces unevenly (R7-1's judder) | M5 |
| R8-3 | minor | The run loop mode test fails on macOS off the cocoa platform (offscreen, minimal) | M2 |
| R8-4 | minor | Frame rates below about 4.7e-10 fps overflow `qRound`: `Q_ASSERT` in debug builds, UB in release | M5 |
| R8-5 | minor | The playback tests compare 0 with 0, and prove nothing, on displays where 30 and 15 fps aren't exact | M5 |
| R8-6 | minor | `finish.sh` commits the qtbase documents with a message file that doesn't exist | tooling |
| R8-7 | nit | A leftover "follow", a function-local static, M2's iOS wording, missing logs and "Not run" entries | M2, M5, M6 |

---

### R8-1: blocker: an exact-rate preference puts the video on a fixed grid

**Where:** M5, `src/multimedia/video/qvideowindow.cpp:545-552`, and
`src/multimedia/qmultimediautils.cpp:67-92`.

**Mechanism.**

* The usual playback case is a QVideoWindow alone on its screen. QVideoWidget's top level has
  nothing to update, and the video window requests one update per frame, so it has the only pending
  update request.
* qtbase then runs the screen's link at the window's mapped rate: (24, 24, 24) for 24 fps.
  * The rate comes from `qappleframerate.cpp:200-201` and is set at `qcocoascreen.mm:385-386` and
    `:634-635`.
  * The link is paused after each delivery (`:492-499`) and unpaused by the next request
    (`:388-391`).
* CoreAnimation keeps such a link on a fixed grid, across pause and unpause. In
  `/tmp/rv8/unpause.mm`, a link on the main screen (240 Hz) is paused after each callback and
  unpaused at a random time, the way frames arrive:

  | link range | unpause to callback, min / median / p90 / max | target timestamps on the grid of the first one |
  |---|---|---|
  | (24, 24, 24) | 1.4 / 20.9 / 34.7 / 41.7 ms | 60 of 60 |
  | (30, 30, 30) | 1.4 / 16.8 / 30.7 / 33.3 ms | 60 of 60 |
  | default | 1.0 / 3.8 / 5.0 / 18.1 ms | |

* The grid's phase is CoreAnimation's. When frames arrive depends on the video clock:
  * FFmpeg renders each frame at its presentation time;
  * AVFoundation's frames are polled at the full rate.

  So each frame is shown at the first tick after it arrives.

**Consequences.** `/tmp/rv8/grid.py` models this:

* frames arrive at k/fps plus a jitter drawn from U(0, J);
* each frame is shown at the first tick after it arrives;
* a frame replaced before a tick is never shown;
* 200 grid phases, 60 s of playback each.

| content, display | wait for the next tick, mean / worst: no preference → preference | J = 0: frames held ≥ 1.5 frame durations, per min | J = 2 ms: playbacks with drops or long holds; drops per min, mean (worst playback) |
|---|---|---|---|
| 24 fps, 240 Hz (fixed) | 2.1 / 4.2 → 20.8 / 41.7 ms | 0 → 0 | 0% → 5%; 0 → 11.4 (356) |
| 24 fps, 120 Hz | 4.2 / 8.3 → 20.8 / 41.7 ms | 0 → 0 | 0% → 5%; 0 → 11.4 (356) |
| 23.976 fps, 120 Hz | 4.2 / 8.3 → 20.8 / 41.7 ms | 0 → 1.44, in every playback | 0% → 100%; 0 → 10.6 (22) |
| 30 fps, 60 Hz (fixed) | 8.3 / 16.7 → 16.7 / 33.3 ms | 0 → 0 | 12% → 6%. Without a preference those are holds of 1.5 frames, with no drops. With it, 17.7 drops/min (443) |
| 15 fps, 60 Hz (the tests' 0.6x) | 8.3 / 16.7 → 33.3 / 66.7 ms | 0 → 0 | 0% → 3%; 0 → 4.6 (226) |

* **The wait is an A/V offset.** The video lags the audio by that much for the whole playback,
  with a random amount for each playback. It doesn't depend on the jitter: it follows from the
  measured grid.
  * On average it's half a frame, and at worst a whole frame: 21/42 ms at 24 fps, 33/67 ms at
    15 fps. Without the preference it's half a refresh.
  * That's the kind of cost R7-2 was about (a persistent video delay of up to a frame). Here it
    needs no stall, and it's on the platforms M5 targets.
* **23.976 and 29.97 fps**, which count as exact through the 0.2% tolerance:
  * The frames drift against the 24 or 30 Hz grid by 0.1% per frame. So every 1000 frames (42 s,
    33 s) one frame is shown for two ticks: 83 ms at 23.976 fps.
  * Without the preference, that frame is shown one refresh longer: 50 ms instead of 42 ms at
    120 Hz.
  * With jitter, the crossing becomes a burst of dropped and repeated frames.
  * 23.976 fps is the rate of most film on streaming services and Blu-ray. It's the headline case.
* **Jitter near a tick.** When the grid's phase is near a frame's arrival time, jitter turns into a
  dropped frame and a repeated one. Without the preference, the same jitter moves a frame by one
  refresh. This part is a model, not a measurement. The delay and the 42 s doubled frame are
  deterministic.

**Nothing is gained on fixed-rate displays.**

* The window renders once per frame either way, as the M5 document says ("Why").
* The link is paused between frames either way.
* `vrr.mm` shows that this display is fixed rate: its minimum and maximum refresh intervals are
  both 1/240 s. The same holds for most external displays, the MacBook Air, and iPhones and iPads
  without ProMotion.

**The M5 message and code comment claim more than holds.**

* The message says "an even cadence, every frame for the same number of refreshes".
* `qmultimediautils.cpp:75-76` says "a frame is then shown longer once every 500 frames". It's
  shown for twice as long, and that's without jitter.

**Why blocker.**

* It's a regression for applications that don't use the feature: every QVideoWidget or
  QVideoWindow application on macOS and iOS gets it, and can't opt out.
* It applies to the most common content rates (24 and 23.976, 30 and 29.97, 60 fps), and on every
  display.
* On fixed-rate displays it buys nothing.
* R7-2 was major because it needed a stall. This doesn't.

This comes from my round 7 proposal. `cadence2.py` put every frame exactly on a grid tick, which
hides both the phase offset and the jitter. It's my miss, not the author's, but that doesn't change
the severity.

**Fix.**

1. Don't set the preference where the display can't change its refresh rate:
   * macOS: `NSScreen.maximumRefreshInterval > NSScreen.minimumRefreshInterval` (macOS 12 and
     later), read through `QNativeInterface::QCocoaScreen::nativeScreen()` in a helper in
     `src/multimedia/darwin/`. QtMultimedia core already builds `.mm` files there, for example
     `qavfhelpers.mm`.
   * iOS: `refreshRate() > 60`, which means ProMotion, or an equivalent UIKit check.
2. Where the preference is still set (variable refresh rate displays), either document the
   trade-off or reduce it:
   * Document it in the M5 message and document, in the code comments, and in README "Known
     limitations":
     * frames wait up to one frame for the grid, which is an A/V offset;
     * 23.976 and 29.97 fps content shows one frame for twice as long every 42 or 33 s;
     * arrival jitter near a tick drops a frame.
   * Or reduce it: drop the 0.2% tolerance and allow exact rates only. 24, 30 and 60 fps keep a
     preference; 23.976 and 29.97 fps get none.

   That's the author's decision to make with this data. I'll accept either, if it's documented.
3. Keep the unit table, and give the integration tests something real to check on a fixed-rate
   display too (see R8-5).

**Alternative.** A measured delivery trace that contradicts the delay above: the frame arrival
time in `setVideoFrame()` and the delivery time of the window's update request, for example with
`qt.qpa.screen.updates`.

**Resolved when** item 1 is in M5 with a test, and item 2 is decided and documented. The
alternative trace would also do.

**Note for the qtbase reviewer.** Applications that set `preferredFrameRate` themselves get the
same grid, and VIDEO.md advises video applications to do so. The `QWindow::preferredFrameRate`
docs could say that the window is then delivered on a grid at that rate, so content timed by
another clock waits up to one interval. That's the "No public frame timing" limitation.

### R8-2: major: cameras report their maximum rate, which a camera in low light doesn't deliver

**Where:** M5, `qvideowindow.cpp:546-551`. For sources other than a player, the stream rate is used
as is (M5 document, line 59).

**Camera frames carry the camera format's maximum frame rate.**

* FFmpeg backend: `ffmpeg/darwin/qavfcamera.mm:393` passes it on, and
  `qavfsamplebufferdelegate.mm:131` sets it on each frame.
* darwin backend: `qplatformcamera.cpp:63`.
* The FFmpeg camera sets the format without locking the frame duration (`qavfcamera.mm:402`,
  `qt_set_active_format(..., false)`). The device can then lower its rate with auto exposure,
  which built-in and USB cameras commonly do in low light.

**Scenario.**

* `QMediaCaptureSession` with a `QVideoWidget`, as in the camera example.
* A 30 fps format, in a dim room, where the camera runs at 24 or 20 fps.
* M5 asks for 30, so the window is paced at 30 Hz:
  * 24 fps frames are shown for 33 or 67 ms, which is R7-1's judder;
  * 20 fps frames alternate between 33 and 67 ms.
* Without M5:
  * at 60 Hz, 20 fps is exactly 3 refreshes per frame;
  * at 120 Hz, 24 and 20 fps are exact too (5 and 6 refreshes).

**Same class:** variable frame rate files whose average is within 0.2% of an exact rate. R6-5 only
documents the faster segments. The slower ones now get an uneven cadence.

**Not measured here.** The camera needs a privacy prompt. Please check with the built-in camera in
a dim room, or take the fix below.

**Fix:** use one of these, and document it:

* apply the automatic preference only to QMediaPlayer sources, whose stream rate is the content's;
* or apply it only when the measured arrival rate over the last few frames matches the rate.

**Resolved when:**

* the fix is in M5, with a test: frames from a source that isn't a player, or frames arriving
  slower than their `streamFrameRate`, get no preference;
* line 59 of the M5 document is updated.

### R8-3: minor: the run loop mode test fails on macOS off the cocoa platform

**Where:** M2, `tst_qvideoframebackend.cpp:353-387`. The skip at `:356` only checks `Q_OS_MACOS`.

**Why it fails.**

* On macOS, the offscreen and minimal platforms use `QUnixEventDispatcherQPA`
  (`qoffscreenintegration.cpp:368-377`, through `createUnixEventDispatcher()`). It doesn't use
  CFRunLoop, so `CFRunLoopRunInMode` delivers none of Qt's posted events.
* FFmpeg frames come from the renderer thread through a queued signal:
  `qffmpegplaybackengine.cpp:201` moves the renderer to its own thread, and
  `qplatformvideosink.cpp:54` emits the signal there.
* So `frames - before` is 0, and the test fails with FFmpeg. The darwin backend doesn't load media
  on those platforms, so it skips.

**Evidence.** `/tmp/rv8/offscreen_modes.cpp` has a worker thread post a queued call every 40 ms,
like the renderer does. On both the offscreen and the minimal platform:

* the Qt event loop delivers 12 calls in 0.5 s;
* then 1 s in each of the default, event tracking and modal panel modes delivers 0;
* in the last two modes, `CFRunLoopRunInMode` returns right away about 9 million times, because
  those modes have no sources.

The author's offscreen runs didn't include this function (`/tmp/mm/r7/offscreen-*.log`).

**Fix:** skip unless `QGuiApplication::platformName() == u"cocoa"`. These modes, and a posted-event
source in them, belong to the cocoa event dispatcher (`qcocoaeventdispatcher.mm:784`, `:801`).

### R8-4: minor: tiny frame rates overflow `qRound`

**Where:** M5, `qmultimediautils.cpp:86-87`.

**Problem.**

* The loop starts with the most refreshes per frame, where `multiple` is about 1/frameRate.
* Below about 4.7e-10 fps, that's outside int's range.
* Qt 6.13's `qRound` then fails a `Q_ASSERT` (`qnumeric.h:517-523`), which aborts in debug builds.
  In release builds the conversion is undefined behavior.

**Reachable** with positive, finite values through public API. `policy.cpp` reproduces all three:

* `QVideoFrameFormat::setStreamFrameRate()` on frames an application pushes to a QVideoWidget's
  sink;
* 25 fps content with `setPlaybackRate(1e-11)`;
* FFmpeg's smallest average frame rate (1/INT_MAX) played at 0.5x.

qtbase clamps for exactly this reason (`qappleframerate.cpp:188-192`, `qplatformwindow.cpp:814-816`).
REVIEW-API m6 was the same finding for qtbase.

**Fix:**

* return 0 below a sane rate, for example 1e-3 fps (one frame in 17 minutes), or use
  `QtPrivate::qSaturateRound`;
* add a tiny-rate row to the unit table, for example 1e-12 fps.

### R8-5: minor: the playback tests prove nothing on displays where 30 and 15 fps aren't exact

**Where:** M5, `tst_qvideoframebackend.cpp:503-563`. The expected value is computed with the policy
function itself (`:453-458`).

**Where they do check something:** on 60, 120 and 240 Hz displays, the expected values are 30 and
15. That's a real check, and since the unit table pins the function, using it for the expected
value is fine.

**Where they don't:**

* On a 50, 75, 100, 144 or 165 Hz display, both expected values are 0 on cocoa. The tests then
  compare 0 with 0, and pass even if QVideoWindow never sets anything.
* After R8-1's fix, the same happens on every fixed-rate display.

**Fix:**

* On the pacing platforms, skip with the refresh rate in the message when the expected value is 0,
  or derive the playback rate from the refresh rate so that the expected value isn't 0.
* After R8-1: on a fixed-rate display, check that no preference is set, which is then the real
  behavior.

### R8-6: minor: `finish.sh` can't commit the qtbase documents

**Problem.**

* `/tmp/mm/finish.sh:11` commits the qtbase PR documents with `/tmp/mm/qtbase-docs.txt`, and that
  file doesn't exist.
* So `git commit -F` fails, `commit_signed` returns 1, and the script exits after step 1. By then
  the six signed qtmultimedia commits exist, but nothing has been pushed.
* The script can resume, but that costs a second AppleConnect session with the user at the
  machine.

**Fix:** write the message file, and dry-run the script up to the signing step.

**For the record: the S6 run.**

* Its first pass wrote `/tmp/qtmm-results-s6/tst_qvideoframebackend-*.log` at 00:39. It ran a
  binary without M6's three test functions: the log lists 19, and none of them is M6's.
* The binary has since been rebuilt with them (00:54), and the run restarted.
* TESTING.md should record only the rerun. For tst_qvideoframebackend, that's 21 passed and 1
  skipped on each backend.

### R8-7: nit

* **`avfdisplaylink.mm:98-99`** still says "follow the main screen". R7-8's wording was fixed at
  `:123` but not here; it should say "uses".
* **`qvideowindow.cpp:86`**: the function-local static keeps the first QGuiApplication's platform
  name for the life of the process, and Qt supports creating a new application object (tests,
  plugins). `platformName()` is cheap, so read it each time.
* **M2's message and document** list macOS scenarios only. Please say what changes on iOS: UIKit's
  tracking mode, for example while a native scroll view is dragged.
* **The evidence and TESTING.md "Not run".**
  * Save the failing run behind "1 and 0 frames" with the other logs.
  * Add to "Not run":
    * the darwin plugin hasn't been compiled for iOS at any state, although M1, M2 and M6 change
      its iOS code;
    * no manual check with a real menu or a real live resize (the test runs the modes directly).

---

## Commit by commit: other checks, all found fine

* **M1:** the tree is identical to round 7's S1.
* **M2:**
  * `-start` and `-stop` pair in `NSRunLoopCommonModes`.
  * The Change-Id is new and differs from all the others.
  * Every state from S2 on runs the two new rows, and both pass on both backends.
* **M3:**
  * The +/- lines are unchanged.
  * The new paragraph is accurate at its commit: on 14.x the callback is on the main run loop, it
    comes from `NSScreen.mainScreen`'s link, and M2 comes first.
* **M4:** the test and the message; see R7-4 and R7-8 above.
* **M5:**
  * `QWindow::setPreferredFrameRate()` returns early when the value doesn't change
    (`qwindow.cpp:1356-1357`). So the per-frame cost is a modulo loop over at most
    `qRound(refreshRate)` candidates.
  * The per-frame evaluation argument holds:
    * QVideoWindow requests updates only in `setVideoFrame()` (`:555`) and after a failed
      `beginFrame()` (`:382`);
    * an expose event renders directly (`:510-514`);
    * QVideoWidget never requests updates on its video window.

    A stale value can pace at most one pending frame after a screen change.
  * `setVideoFrame()` always runs on the GUI thread: the sink's signal is queued from the FFmpeg
    renderer.
* **M6:**
  * `VideoOutput` passes its window.
  * `AVFVideoSink` and `AVFDisplayLink` keep the window in `QPointer`s.
  * On iOS, `setWindow()` only connects a slot that does nothing there.
* **Messages:**
  * every line is at most 72 columns, and every summary at most 70;
  * there's a blank line before each Change-Id;
  * the six Change-Ids are well formed and distinct, and M2's is new.
* **Scripts:** `commit-series3.sh` works like round 7's, now with six trees. `verify-states7.sh`
  checks every materialized tree, so the partial run described in TESTING.md couldn't have been
  recorded by mistake.

---

## Verdict: REQUEST CHANGES

Severity counts: blocker 1, major 1, minor 4, nit 1.

Round 7:

* R7-1 to R7-5, R7-7 and R7-8 are closed.
* R7-6 is closed for S1 to S5. S6 is pending (the run is in progress), and not counted.
* R6-6 is still an accepted deferral.

Open findings:

- R8-1: blocker: an exact-rate preference puts a lone video window on a fixed grid at that rate (measured): frames wait up to one frame (half on average) for a tick; 23.976 fps shows a frame twice as long every 42 s; jitter near a tick drops frames; nothing is gained on fixed-rate displays (M5)
- R8-2: major: cameras report their format's maximum rate; in low light they deliver fewer frames, which the preference paces unevenly (M5)
- R8-3: minor: `playback_deliversFrames_whileRunLoopIsInMode` fails on macOS on the offscreen and minimal platforms; skip unless the platform is cocoa (M2)
- R8-4: minor: frame rates below about 4.7e-10 fps overflow `qRound` (`Q_ASSERT` in debug builds, UB in release); clamp, and add a row (M5)
- R8-5: minor: the playback tests compare 0 with 0 on displays where 30 and 15 fps aren't exact (M5)
- R8-6: minor: `finish.sh` needs `/tmp/mm/qtbase-docs.txt`, which doesn't exist; record only the S6 rerun (tooling)
- R8-7: nit: a leftover "follow", the platform name static, M2's iOS wording, the missing failing-run log, and "Not run" entries (iOS build, real menu and live resize) (M2, M5, M6)
