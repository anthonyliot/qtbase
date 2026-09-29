# Round 7 review: qtmultimedia series (M1 to M5)

Reviewer: qt-cadisplaylink-pr-reviewer (independent, strict)
Repo: `qt5/qtmultimedia`, base upstream `635067497`. The series isn't committed yet: it's recorded as
trees (`/tmp/mm/series2-trees.txt`), and the working tree equals S5. Line numbers are at S5 unless
noted otherwise.

| # | Tree | Subject | Round 6 items |
|---|---|---|---|
| M1 | S1 `47653cfd479b` | darwin: Don't leak the display link of AVFDisplayLink | R6-3 |
| M2 | S2 `a1e88291a4f3` | darwin: Stop using the deprecated CVDisplayLink in AVFDisplayLink | (was `2152cdbd8`) |
| M3 | S3 `198815449c08` | Report the stream frame rate of played video frames | |
| M4 | S4 `6102ba5d546f` | QVideoWindow: Drive the window's preferred frame rate from the video | R6-1, R6-5 |
| M5 | S5 `3b2fda1ab1a4` | darwin: Poll for video frames in sync with the display the video is on | R6-2, R6-4, R6-7, R6-8, R6-10 |

How I checked:

* **Patches and documents.** `git diff-tree -p` of each state against the previous one, the
  messages in `/tmp/mm/`, `commit-series2.sh`, `states.sh`, the M1 to M5 documents, and the README
  and TESTING.md sections.
* **qtbase and qtdeclarative code.** The qtbase frame-rate model and platform code at the branch
  head: `qappleframerate.cpp`, the `qwindow.cpp` docs, `qplatformwindow.cpp`, `qcocoascreen.mm`,
  `qcocoaeventdispatcher.mm`, `qcocoawindow.mm`, and the `qscreen.cpp` native interface. Also
  qtdeclarative's `qquickwidget.cpp`.
* **The author's logs, read only.** `/tmp/qtmm-results-s5/`, `/tmp/ab/`, and the leak probe's
  heap(1) files.
* **My own scratch programs**, in `/tmp/rv7/`. The `.mm` probes use AppKit only, with no Qt. The two
  `.py` files are simulations. None of them touches `qtmm-build` or `qt5-build-nofw`:
  * `modes.mm`: display link callbacks per run loop mode.
  * `lifecycle.mm`: the S5 observer lifecycle, run with NSZombieEnabled.
  * `cycle.mm`: the author's retain-cycle probe, rebuilt.
  * `cadence2.py`: frame hold times with and without the preference.
  * `timerlag.py`: the qtbase timer path.
* As instructed, I built and ran nothing in the qtmultimedia worktree or in the shared builds.

---

## Summary

The round 6 fixes are good:

* **M1** fixes a real, pre-existing leak, and its analysis is right. I reproduced the cause
  (`cycle.mm`), and the heap counts in TESTING.md match the heap files. Folding R6-3 into M1 isn't
  just justified, it's required: without it, M1's destructor line would cause a use-after-free in
  `dealloc`.
* **M5's redesign** uses the display link of the window's screen, found through
  `QNativeInterface::QCocoaScreen`. It removes both round 6 blockers by construction: there's no
  `winId()` cast, and it doesn't depend on visibility. It's also simpler than the NSView version.
* **The reorder is clean.** M2's +/- lines are identical to `2152cdbd8`.

Three new problems remain. All of them are about applications that don't use the feature:

* **R7-1 (blocker, M4).** Every QVideoWindow, and so every QVideoWidget, now asks for the delivery
  rate. When the display can't show that rate exactly, qtbase paces the window at the next faster
  exact rate. For 25 fps content on any Apple display, and 24/23.976 fps content on a 60 Hz display,
  that rate is 30 Hz. So 5 to 6 frames per second are held about twice as long as the others, where
  today no hold is longer than one refresh beyond the frame's duration. That's visible judder. On
  fixed-rate displays nothing is gained in exchange, and QVideoWidget applications can't opt out.
* **R7-2 (major, M4).** On timer platforms (X11, eglfs, Android), the preference is a minimum
  interval from the last delivery. A single GUI-thread stall therefore delays every later frame by
  the stall, for the rest of playback. Nothing is gained there either.
* **R7-3 (major, M2).** On macOS 14.x, the CVDisplayLink delivered in every common run loop mode.
  The CADisplayLink that replaces it is scheduled only in the default mode. So with the AVFoundation
  backend, the video freezes while a menu is open, during live resize, and behind any
  application-modal dialog. My round 4 approval of this commit rested on the premise that the
  fallback never ran, which was wrong, as the author has now noted.

---

## Round 6 findings

| ID | Round 6 severity | Response | Verified at S5 | Status |
|---|---|---|---|---|
| R6-1 | blocker | Fixed in M4: stream rate × \|playbackRate\| | `qvideowindow.cpp:535-538`. `QVideoSink::source()` is cleared when the player is destroyed (`qmediaplayer_p.h:80-81`, `qmediaplayer.cpp:225`), so the per-frame `qobject_cast` is safe. `_followsPlaybackRate` fails without the fix. | **Closed.** The policy itself is R7-1/R7-2. |
| R6-2 | blocker | Redesign: link of the window's screen via `QNativeInterface::QCocoaScreen` | The interface is resolved with `dynamic_cast` (`qtbase/src/corelib/global/qnativeinterface_p.h:46`), which returns null for `QOffscreenScreen`, and the code then falls back to the main screen. No `winId()` cast is left. The author's offscreen probe doesn't crash. | **Closed** on the code evidence. I had asked for `tst_qvideoframebackend` under `QT_QPA_PLATFORM=offscreen QT_MEDIA_BACKEND=darwin`; please still run it once the machine is free (not blocking). |
| R6-3 | major | Fixed in M1 | `avfdisplaylink.mm:59`. My `lifecycle.mm` ran construct, start, recreate with a nil screen, recreate, destroy, three times under NSZombieEnabled: no message to a freed object, 0 ticks while the link is nil, about 48 ticks in 0.2 s after recreation, and all 3 observers deallocated. | **Closed** |
| R6-4 | major | Redesign: screen link | A screen link isn't tied to the window, so hidden, minimized and occluded windows all keep getting frames, by construction. The probe measured 25/25/25 (shown/hidden/shown again). `_whileHidden` guards against a return to view links. | **Closed** |
| R6-5 | minor | Documented (M4 message, M4 document, README) | Present | **Closed** |
| R6-6 | minor | Deferred as a follow-up (fixed-rate display only) | Documented in M5's document and the README | **Accepted deferral.** The AVFoundation backend isn't the default, and the author has no ProMotion display to measure on. Note that together with R7-1, this backend may get the judder without the panel dropping. Please measure before Gerrit if a ProMotion display becomes available. |
| R6-7 | minor | Tests added | `_whileHidden`, `_canBeDeleted_whilePlaying`, `_afterMovingToAnotherScreen` (skipped with one screen), and the mock-backend QVideoWidget test | **Closed.** The remaining gaps are carried as R7-5. |
| R6-8 | minor | `renderWindowFor()` | `qquickvideooutput.cpp:472-478` | **Closed**, with nit R7-7 |
| R6-9 | minor | Documented | README:237, M4 document | **Closed** |
| R6-10 | nit | The code is gone | | **Closed** |

---

## New findings

| ID | Severity | Title | Commit |
|---|---|---|---|
| R7-1 | blocker | The automatic preference makes the cadence worse for rates the display can't show exactly (25/50 fps everywhere, 24/23.976 fps on 60 Hz), with nothing gained on fixed-rate displays and no opt-out for QVideoWidget | M4 |
| R7-2 | major | On timer platforms the preference keeps the video late by the largest past stall, for the rest of playback | M4 |
| R7-3 | major | macOS 14.x: the new CADisplayLink runs only in the default run loop mode, so video freezes during menus, live resize and modal dialogs; M2's message doesn't say so | M2 |
| R7-4 | minor | M3 has no test of its own; its only check arrives in M4 | M3 |
| R7-5 | minor | M5's tests don't exercise its screen-following logic; one test's comment claims more than it checks | M5 |
| R7-6 | minor | Per-commit evidence is still PENDING; two TESTING.md rows present one mock-backend run as darwin and ffmpeg results | all |
| R7-7 | nit | `QQuickVideoOutput` computes the render window only once, and the offscreen window already follows the widget's screen | M5 |
| R7-8 | nit | Wording in the M3 and M5 messages and one comment; M1 could carry a Pick-to | M1, M3, M5 |

---

### R7-1: blocker: the automatic preference makes the cadence worse for rates the display can't show exactly

* **Commit:** M4, `src/multimedia/video/qvideowindow.cpp:535-538`.
* **The mapping in qtbase.** A preference becomes the slowest exact display rate that isn't below
  it:
  * code: `qtbase/src/gui/platform/darwin/qappleframerate.cpp:174-202`
  * docs: `qwindow.cpp:1290-1300`
  * tests: `tst_qappleframerate.cpp:330-346`, whose rows include 25@60, 25@120 and 25@240 giving
    30, and 24@60 giving 30. On 120 and 240 Hz, 48 and 50 give 60.

  A window that is the only one with pending update requests is delivered on that grid, because the
  link runs at that range (`qcocoascreen.mm:485-490`).
* **Scenario.** Any QVideoWidget or QVideoWindow application, which can't opt out. Either backend,
  including FFmpeg, the default. macOS or iOS. The affected content is:
  * 25 fps content (PAL, European broadcast, 50 Hz-region cameras) on a 60, 120 or 240 Hz display;
  * 24 or 23.976 fps film on a 60 Hz display: most external monitors, the MacBook Air, iPhones and
    iPads without ProMotion;
  * 48 or 50 fps content on 120/240 Hz displays, and rates scaled by the playback rate (for
    example, 25 fps at 2x is 50).

  Before M4, each frame is shown at the next refresh of the display's full rate. After M4, it is
  shown at the next tick of the 30 (or 60) Hz grid.
* **Evidence.** `/tmp/rv7/cadence2.py` shows frame k at the first grid tick after k/fps, using the
  rule copied from `forPreferredFrameRate`. It counts the frames held at least 1.5 times their
  duration:

  | content | display | no preference: long holds/s, longest | M4: grid, long holds/s, longest |
  |---|---|---|---|
  | 24 | 60 | 0, 50.0 ms (3:2) | 30 Hz, **6.0**, 66.7 ms |
  | 23.976 | 60 | 0, 50.0 ms | 30 Hz, **6.0**, 66.7 ms |
  | 25 | 60 / 120 / 240 | 0, 50.0 / 41.7 / 41.7 ms | 30 Hz, **5.0**, 66.7 ms |
  | 48 | 120 | 0, 25.0 ms | 60 Hz, **12.0**, 33.3 ms |
  | 50 | 120 / 240 | 0, 25.0 / 20.8 ms | 60 Hz, **10.0**, 33.3 ms |
  | 24 | 120 / 240 | 0, 41.7 ms | 24 Hz, 0, 41.7 ms (the case M4 is for: fine) |
  | 30, 60 | any | 0 | 0 (fine) |

  A regular long hold every 4 to 5 frames is the classic judder that shows on pans.
  **Upstream reference: the "no preference" column.**
* **Nothing is gained on fixed-rate displays.**
  * A QVideoWindow renders once per video frame with or without the preference.
  * Without a preference, the cocoa link already pauses right after each delivery
    (`qcocoascreen.mm:492-499`), so wakeups are about one per frame either way.
  * The panel can't change rate.

  On ProMotion the panel can drop, for example to 30 Hz for 25 fps. That trades smoothness for
  power, which is the application's choice to make, not a default. With the AVFoundation backend,
  R6-6 suggests the decode link keeps the panel at 120 Hz anyway, which leaves only the judder.
* **QVideoWidget applications can't override it.** Its QVideoWindow is private, and M4 sets the
  property again on every frame. QML applications aren't affected (R6-9).
* The M4 message's premise, "A video window rendered at the display's maximum refresh rate wastes
  power", doesn't hold either: the window renders once per frame. The real benefit is the panel
  rate on variable refresh rate displays.
* Round 5 approved M4 without considering cadence. Like R6-1, this was missed then.
* **Fix.** Only set a preference when it gives an exact cadence, otherwise use 0, which is today's
  behavior. Let R be `screen()->refreshRate()`. This is the display mode's nominal rate on cocoa and
  `maximumFramesPerSecond` on iOS, the same input qtbase uses, so there's no feedback loop when the
  panel drops. Take the smallest multiple `m * rate` for which `R / (m * rate)` is a whole number n
  (within about 0.2%) that divides `qRound(R)`. Set that multiple, or 0 if there is none or if
  n == 1.
  * Rates that keep a preference:
    * 24 and 23.976 on 120/240 Hz give 24 Hz, the headline ProMotion case;
    * 30/29.97 and 60/59.94 on any display keep their rate;
    * 48 on 240 Hz keeps 48.
  * Rates that get no preference: 25 and 50, and 24 on 60 Hz.

  Re-evaluate on `QWindow::screenChanged`. This can share code with R7-2's platform check.
* **Alternative.** A measured presentation trace (the displaylink manual test's `--trace`, or
  Instruments) showing that 25 fps content in a QVideoWidget on a 60, 120 or 240 Hz display isn't
  held longer with M4.
* **Resolved when:**
  * the policy is in M4;
  * a test shows that an exact rate (for example `refreshRate / 2`) is set and a non-exact one
    (`refreshRate / 2.5`) gives 0;
  * the existing M4 tests are adapted;
  * the M4 message and document describe the policy and the real benefit.

  Side note for the qtbase documentation, not this series: one sentence telling video applications
  that non-exact rates give an uneven cadence would help those that opt in themselves.

### R7-2: major: on timer platforms the preference keeps the video late by the largest past stall

* **Commit:** M4, `qvideowindow.cpp:535-538`. The mechanism is in qtbase,
  `qplatformwindow.cpp:810-822`: the minimum interval is measured from the last delivery.
* **Platforms:** xcb, eglfs, Android, offscreen, and Windows without DXGI vsync (see the note at
  `qwindow.cpp:1339-1344`). Wayland and Windows with DXGI vsync ignore the preference.
* **Scenario.** A QVideoWidget on X11 plays 25 fps content, and the GUI thread stalls once for
  30 ms (a layout, a slow paint).
  * The late frame is delivered 30 ms late. The next frames arrive on time, but none can be
    delivered sooner than 40 ms after the previous delivery.
  * So every following frame is shown about 35 ms late, for the rest of playback: until a pause, a
    seek, or a stall long enough to drop a frame.
  * Without a preference, each frame is delivered 5 ms after it arrives.
* **Evidence.** `/tmp/rv7/timerlag.py` models 0 to 3 ms of jitter and one 30 ms stall at 2 s:

  | | lag at 1 s | at 3 s | at 10 s |
  |---|---|---|---|
  | without a preference | 6.3 ms | 6.8 ms | 5.8 ms |
  | with M4 | 7.8 ms | 35.9 ms | 35.9 ms |

  A persistent video delay of up to one frame (40 ms at 25 fps) is close to the commonly cited
  threshold at which audio leading video becomes noticeable, about 45 ms (ITU-R BT.1359). It also
  adds to every other latency in the pipeline.
* **Nothing is gained on these platforms.** The window already requests exactly one update per
  frame, so the preference can only delay.
* **Fix.** Set the preference only where the platform paces update requests to the display (cocoa,
  ios), for example with a `QGuiApplication::platformName()` check or a QPA capability. It can be
  part of R7-1's policy. For the qtbase reviewer: VIDEO.md's advice to "set preferredFrameRate to
  the content rate" has the same effect for applications on timer platforms. A tolerance in the
  timer path, such as allowing a delivery up to half an interval early, would avoid it there.
* **Resolved when** M4 sets no preference on timer platforms, with the tests adjusted per platform,
  or the qtbase timer path stops accumulating the delay.

### R7-3: major: on macOS 14.x, M2 freezes video during menus, live resize and modal dialogs

* **Commit:** M2, where the behavior on 14.x changes. `avfdisplaylink.mm:62-70`: `-start` and
  `-stop` schedule the link in `NSDefaultRunLoopMode`. That code is unchanged from upstream.
* **Before M2, on macOS 14.4 to 14.x** (where the `@available(macOS 15.0)` check is false):
  * The CVDisplayLink called back on its own thread and posted an event.
  * Qt delivers posted events in every common mode: the posted-events source is in
    `kCFRunLoopCommonModes` (`qcocoaeventdispatcher.mm:801`), and Qt adds `NSModalPanelRunLoopMode`
    to the common modes (`:784`).

  **After M2,** the CADisplayLink fires only while the main run loop is in the default mode.
* **Scenario.** macOS 14.x, the AVFoundation backend, a video playing. Any of these freezes it:
  * the user opens a menu bar menu, or live-resizes the window (both run in
    `NSEventTrackingRunLoopMode`);
  * the application shows an application-modal dialog: `QDialog::exec`, `QMessageBox`, or a native
    `QFileDialog`. These start a modal session (`qcocoawindow.mm:561-563`) that runs
    `[NSApp runModalSession:]` in `NSModalPanelRunLoopMode` (`qcocoaeventdispatcher.mm:345-349`).

  Before M2, the video keeps playing. After it, no new frames arrive until the interaction ends,
  while audio continues.
* **Evidence.** `/tmp/rv7/modes.mm` creates an NSScreen link the way AVFDisplayLink does. On the
  240 Hz display, callbacks in 1 s:

  | run loop mode | link scheduled in `NSDefaultRunLoopMode` | link scheduled in `NSRunLoopCommonModes` |
  |---|---|---|
  | `kCFRunLoopDefaultMode` | 241 | 241 |
  | `NSEventTrackingRunLoopMode` | 0 | 240 |
  | `NSModalPanelRunLoopMode` | 0 | 240 |
* **Why major rather than blocker:**
  * it's limited to macOS 14.x with the non-default backend;
  * the video resumes afterwards;
  * upstream already behaves like this on macOS 15 and later.

  But it is a regression on 14.x, and M2's message presents the change as dropping a path that
  isn't needed.
* My round 4 review approved `2152cdbd8` on the premise that the guard "was always true at
  runtime". That was wrong, and so was its conclusion that the run loop mode was "unchanged
  behavior".
* **Fix.** Schedule the link in `NSRunLoopCommonModes` in `-start` and `-stop`, as qtbase's cocoa
  display link does. Do it in a commit before M2: it also fixes macOS 15 and later, and iOS's
  `UITrackingRunLoopMode`, and can be picked to stable branches. Then say in M2's message what else
  changes on 14.x: the main run loop instead of the CVDisplayLink's thread, and
  `NSScreen.mainScreen` instead of `kCGDirectMainDisplay`.
* **Resolved when** the link fires in the common modes, and M2's message is updated. A reason why
  the default mode is required would also do.

### R7-4: minor: M3 has no test of its own

* M3 changes public, observable data: `QVideoFrameFormat::streamFrameRate()` of played frames, on
  two backends. The only check is in M4's `_isSetDuringPlayback`
  (`QTRY_VERIFY(streamFrameRate > 0)`), and M3's document says so. If M4 were reverted, or reviewed
  apart, M3 would have no test.
* **Fix:** add a test in M3. For example, in `tst_qvideoframebackend`, play `colors.mp4` with the
  current backend and `QCOMPARE` the valid frames' `streamFrameRate()` with the file's rate.
* **Resolved when** M3 has such a test.

### R7-5: minor: M5's tests don't exercise its logic, and one test's comment overstates it

* **`_afterMovingToAnotherScreen`** (`tst_qvideoframebackend.cpp:466-497`):
  * Its comment (lines 473-476) says a link left on the old screen "wouldn't pace right". But a link
    on the old screen at 60 Hz or more still polls every frame of a 25 fps video. So the
    `frames >= streamFrameRate * 0.6` check passes with or without M5's recreation. It does catch a
    broken recreation, one that gives no frames after the move.
  * It has never run: there's only one screen, as TESTING.md says.
* **Not exercised by any automated test:**
  * that the link follows the window's screen;
  * the QVideoWidget child window with a real backend (`tst_qvideowidget` and
    `tst_qmediaplayerwidgets` use the mock backend, see R7-6);
  * the QML window change.

  `_whileHidden` also passes upstream: it guards against a return to view links, which is still
  useful.
* **Fix:**
  * reword the comment to say what the test checks;
  * write the untested paths in the M5 document;
  * when a second display is available, do a manual two-screen run, with the video on the screen
    that isn't the main one, using `QT_DEBUG_AVF` or a debug message naming the screen used, and
    record it.
* **Resolved when** the comment matches the check, and the gaps are in the M5 document.

### R7-6: minor: per-commit evidence is pending, and two rows overstate coverage

* **Per-commit states.** TESTING.md still says "Series states: PENDING", while README:83-84 says
  every commit was "built and tested at its own state". The S5 suites are now recorded, and they
  match `/tmp/qtmm-results-s5/`.
* **Mock-backend rows.** `tst_qvideowidget` and `tst_qmediaplayerwidgets` use
  `Q_ENABLE_MOCK_MULTIMEDIA_PLUGIN`, which calls `QPlatformMediaIntegration::setBackend("mock")`.
  That takes precedence over `QT_MEDIA_BACKEND` (`qplatformmediaintegration.cpp:92-97`), so the
  darwin and ffmpeg columns of those two rows are the same mock run, twice.
* **Resolved when:**
  * S1 to S4 are recorded (build, and the targeted tests of `verify-states.sh`);
  * the README matches;
  * those two rows say "mock backend".

### R7-7: nit: QQuickVideoOutput computes the render window only once

* **Where:** `qquickvideooutput.cpp:472-478`. `renderWindowFor()` is read only on
  `ItemSceneChange`.
* **The common case gains nothing.** Typically the QML is loaded and the QQuickWidget is shown
  afterwards. At scene change the top-level window doesn't exist yet, so the offscreen window is
  used. That's correct anyway: QQuickWidget keeps the offscreen window's screen in sync
  (`qtdeclarative/src/quickwidgets/qquickwidget.cpp:191`, and 1885-1889, where `setScreen` on
  `ScreenChangeInternal` emits `screenChanged`).
* **When the render window is found, it can go stale.** It's kept after the QQuickWidget moves to
  another top-level window, where the offscreen window would have followed.
* So for QQuickWidget, `renderWindowFor()` doesn't help and can hurt. It only helps custom
  `QQuickRenderControl` setups.
* **Fix:** pass `m_window`, or keep the render window but say it's there for custom render
  controls. Correct M5's "with the window a QQuickWidget renders to". Line 476 is also 101 columns
  long.

### R7-8: nit: wording

* **M3 message:** "The media player backends ... left it at 0". Only FFmpeg and AVFoundation
  change; the other backends still report 0. Name them.
* **M5 message:** "The darwin sink then uses the display link of the window's screen". That's macOS
  only; iOS still uses the main screen's CADisplayLink.
* **`avfdisplaylink.mm:116-120`:** "it follows the main screen". The main screen is chosen when the
  link is created and not followed after that; "uses" is accurate.
* **M1 footers:** M1 fixes a leak in released versions and stands on its own. A QTBUG and a
  `Pick-to:` footer would let it go to the stable branches ahead of the rest.

---

## Commit by commit: other checks, all found fine

* **M1:**
  * The cycle analysis is correct:
    * The rebuilt probe gives a retain count of 2 after creating the link, no dealloc after
      releasing the target, and a dealloc after `invalidate`.
    * The heap(1) counts in TESTING.md match `leakprobe/*.heap`:
      * 20/20 upstream and without the fix;
      * 0 observers with the fix;
      * with pools, 0/0.
  * The fix is complete on every path:
    * The macOS 15+ path and the UIKit path both create the observer.
    * On 14.x at S1, `m_observer` is nil, so the new line is skipped and `CVDisplayLinkRelease`
      runs as before.
    * At S5, `recreateDisplayLink()` goes through the same `setDisplayLink:`.
    * `dealloc` after `setDisplayLink:nil` sees nil and returns early, so there is no second
      invalidate.
  * Threads: `invalidate` runs in `~AVFDisplayLink`, on the thread that scheduled the link.
  * "Every media player" is accurate: each `AVFMediaPlayer` creates an `AVFVideoRendererControl`
    (`avfmediaplayer.mm:582`), which creates the link (`avfvideorenderercontrol.mm:66`).
  * The M1 message is accurate.
* **M2:**
  * Its +/- lines are identical to `2152cdbd8`'s (the diff of the +/- lines is empty). Only hunk
    offsets and one context block (M1's destructor lines) differ.
  * The corrected premise ("isn't needed") is accurate. What's missing is in R7-3.
* **M3:** unchanged from round 6's `4a5411069`, which was approved then.
* **Self-containment, by reading:**
  * `setDisplayWindow` appears only at S5, `QVideoSink::source()` from S4, no CVDisplayLink code
    from S2 on, and `setPreferredFrameRate` from S4 on.
  * The tests link `Qt::MultimediaPrivate`.
  * M4 and M5 need qtbase's `QWindow::preferredFrameRate`, which M4's message states. They can
    only be staged after a dependency update.
  * `QNativeInterface::QCocoaScreen` has been in qtbase since 6.11, and is in the pinned
    `25d8223e59f`.
  * `!QT_PLATFORM_UIKIT` on Apple platforms means macOS, where that interface is declared.
* **M5's screen following:**
  * A top-level window moving to another screen emits `screenChanged` for its child windows too.
  * Reparenting a QVideoWindow into a window on another screen emits it as well
    (`qwindow.cpp:862-863`), so QVideoWidget follows.
  * `setVideoSink(nullptr)` resets the window, and the QPointers cover deletion.
* **Messages:** every line is at most 72 columns, summaries are at most 70, and there's a blank
  line before `Change-Id:`. The trailing blank line in `c3.txt` is stripped by `git commit`.
* **`commit-series2.sh`:** stages each recorded tree, checks the tree and the signature after each
  commit, and can resume. I found no problem.
* **The upstream A/B is honest:**
  * `base-full.log:446-450` shows the upstream watchdog abort in `AMV_setSourceNull`.
  * The S5 darwin failures (5 `invalidHttpsAddress`, 1 `destruction` start) match TESTING.md.

---

## Verdict: REQUEST CHANGES

Severity counts: blocker 1, major 2, minor 3, nit 2. All ten round 6 findings are closed; R6-6 is
an accepted deferral.

- R7-1: blocker: QVideoWindow/QVideoWidget's automatic preference makes the cadence worse for rates the display can't show exactly (25/50 fps everywhere, 24/23.976 fps on 60 Hz), with nothing gained on fixed-rate displays and no opt-out (M4)
- R7-2: major: on timer platforms the preference keeps the video late by the largest past stall, for the rest of playback (M4)
- R7-3: major: macOS 14.x: CADisplayLink only in the default run loop mode, so video freezes during menus, live resize and modal dialogs; not in M2's message (M2)
- R7-4: minor: M3 has no test of its own (M3)
- R7-5: minor: M5's screen following, the QVideoWidget real-backend path and the QML window change are untested; one test comment overstates what it checks (M5)
- R7-6: minor: S1 to S4 evidence is PENDING; two TESTING.md rows present one mock-backend run as darwin and ffmpeg results (all)
- R7-7: nit: `renderWindowFor()` computed only once; the offscreen window already follows the widget's screen (M5)
- R7-8: nit: wording in the M3 and M5 messages and one comment; M1 could carry a Pick-to (M1, M3, M5)
