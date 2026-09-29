# Round 7: author's response (qtmultimedia series)

Verdict received: REQUEST CHANGES (blocker 1, major 2, minor 3, nit 2). Every claim was checked
before acting (the qtbase mapping and timer path in the code, R7-3 with your probe rerun and a new
test, R7-7 in `qquickwidget.cpp`); all findings accepted. The series is now six commits, recorded
as trees in `/tmp/mm/series3-trees.txt` (signing still blocked), messages `/tmp/mm/s7-{1..6}.txt`.

| # | Subject | Tree | Changes in round 7 |
|---|---|---|---|
| M1 | darwin: Don't leak the display link of AVFDisplayLink | `47653cfd479b` | none |
| M2 | darwin: Keep polling for video frames while menus and dialogs are open | `5d2e99e0524e` | new (R7-3) |
| M3 | darwin: Stop using the deprecated CVDisplayLink in AVFDisplayLink | `9c3e0622edbf` | message (R7-3) |
| M4 | Report the stream frame rate of played video frames | `46dc9110c930` | test (R7-4), message (R7-8) |
| M5 | QVideoWindow: Let the display refresh at the video's frame rate | `b7495084410a` | policy (R7-1, R7-2), tests, message |
| M6 | darwin: Poll for video frames in sync with the display the video is on | `0b2e8b2222e6` | R7-5, R7-7, R7-8 |

| ID | Response |
|---|---|
| R7-1 blocker | **Fixed (M5)** as you proposed. New `qVideoPreferredFrameRate(frameRate, refreshRate)` (`qmultimediautils`): the slowest whole multiple of the delivery rate that is `refreshRate / n` (n >= 2, a whole divisor of the whole refresh rate, so a whole rate), within 0.2%, else 0. Evaluated per frame from `screen()->refreshRate()`, so it follows the window's screen; not on `screenChanged` too: without frames the window requests no updates that a stale value could pace (resize/expose render directly). 24/23.976 fps on 120/240 Hz keep 24, 30/29.97 keep 30 anywhere, 48 on 240 keeps 48; 25, 50, and 24 on 60 Hz get none. Tests: a 31-row unit table, and the integration tests now expect a preference for half the refresh rate and none for 2.5 refreshes per frame, and play at 1.2x and 0.6x (30 and 15 fps, exact on 60/120/240 Hz). The message now says what the benefit is (the panel rate of a variable refresh rate display) instead of "wastes power". |
| R7-2 major | **Fixed (M5)**: only on `ios`, and `cocoa` with vertical sync, the same condition as `QCocoaWindow::updatesWithDisplayLink()` (`requestedFormat().swapInterval() != 0`). Elsewhere the property isn't touched. Tested: on the offscreen platform the same tests expect and get no preference (both backends), and the synthetic test checks that `swapInterval(0)` gives none on cocoa. |
| R7-3 major | **Fixed (new M2, before the CVDisplayLink removal)**: `-start`/`-stop` use `NSRunLoopCommonModes`. New test `playback_deliversFrames_whileRunLoopIsInMode(event tracking, modal panel)`, which runs the main run loop in that mode for 1 s: with the default mode the darwin backend got **1 and 0** frames (fails), with the common modes both backends pass. M3's message now says what else changes on 14.x (main run loop instead of the CVDisplayLink's thread; `NSScreen.mainScreen` instead of `kCGDirectMainDisplay`). iOS gets the common modes too (the observer code is shared), which includes UIKit's tracking mode; Qt's CF dispatcher delivers posted events there (`qeventdispatcher_cf.mm:190`). |
| R7-4 minor | **Fixed (M4)**: `streamFrameRate_isReportedForPlayedFrames` plays `colors.mp4` and requires every valid frame of at least five to report 25 fps; skipped for backends that don't report it. |
| R7-5 minor | **Fixed**: the comment of `_afterMovingToAnotherScreen` says what it catches (a broken recreation, not a missing one); the M6 document lists what no automated test covers, and the two-screen manual run is in README "Before sending to Gerrit" for when a second display is connected. |
| R7-6 minor | **Fixed**: every state built and tested (TESTING.md, "Series states"); the mock-backend rows say "mock backend", run once. |
| R7-7 nit | **Fixed (M6)**: `VideoOutput` passes its window as is, with a comment on QQuickWidget keeping the offscreen window's screen in sync; the `qquickrendercontrol.h` include and the 101-column line are gone; M6's message corrected. |
| R7-8 nit | **Fixed**: M4 names FFmpeg and AVFoundation and says the others report 0; M6 says "On macOS" and "iOS is unchanged"; the comment says "uses the main screen at the time". QTBUG and `Pick-to:` for M1 and M2 are listed for the author's decision at Gerrit time (filing a QTBUG is outward-facing). |

R6-2's residual request is done: `tst_qvideoframebackend` under `QT_QPA_PLATFORM=offscreen` with the
darwin backend runs without a crash. The playback tests skip there because the darwin backend
never loads media on the offscreen platform (`testMediaFilesAreSupported`: stuck in LoadingMedia,
as upstream), and a pre-existing test, `toImage_returnsImage_whenCalledFromSeparateThread…`,
dereferences the unloaded URL without checking and aborts the full run, so the new functions were
run by name.

One transparency note: the first full ffmpeg run of the new tests, before they used the player's
actual playback rate (the FFmpeg backend keeps it as a float: 25 × float(1.2) = 30.0000012),
failed twice: that mismatch, and once `_isSetDuringPlayback` reading 0. The 0 didn't reproduce in 4
later full runs (3 on each backend, 1 with debug output showing 30 throughout).
