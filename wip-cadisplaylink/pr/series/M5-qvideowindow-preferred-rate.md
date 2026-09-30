# M5 QVideoWindow: Show frames evenly on variable refresh rate displays

| | |
|---|---|
| Repo, branch | qtmultimedia `wip/cadisplaylink` |
| Files | `src/multimedia/video/qvideowindow.cpp`, `qvideowindow_p.h`, `src/multimedia/video/qvideosink.h`, `qvideosink.cpp`, `src/multimedia/qmultimediautils.cpp`, `qmultimediautils_p.h`, `src/multimedia/darwin/qavfhelpers.mm`, `qavfhelpers_p.h`, `src/multimediawidgets/qvideowidget.cpp` (docs), `tests/auto/unit/multimedia/qvideowindow/` (new), `tests/auto/unit/multimedia/CMakeLists.txt`, `tests/auto/integration/qvideoframebackend/tst_qvideoframebackend.cpp`, `tests/auto/unit/multimedia/qmultimediautils/tst_qmultimediautils.cpp`, `tests/auto/unit/multimediawidgets/qvideowidget/tst_qvideowidget.cpp` |
| Tree | S5 `d7b28d110a2f` (`pr/qtmultimedia-series/trees.txt`) |
| Change-Id | `I9b397e8ac6623a11561d90acae176764f813d2d2` |
| Needs | qtbase `QWindow::preferredFrameRate` (G4, Qt 6.13) |
| From | the frame-rate integration; review rounds 6 (R6-1), 7 (R7-1, R7-2), 8 (R8-1, R8-2, R8-4, R8-5), 9 (R9-1 to R9-3), 10 (R10-1, R10-4), 11 (R11-1, R11-2, R11-5) and 12 (R12-3, R12-4), and the ProMotion measurement (TESTING.md, "ProMotion measurement") |

## What
For every frame, `QVideoWindow::setVideoFrame()` sets `QWindow::preferredFrameRate` to
`qVideoPreferredFrameRate(rate, screen()->refreshRate())`, where the rate is that of a
`QMediaPlayer`'s frames: the stream's frame rate times `|playbackRate|` (R6-1; `QVideoSink` gets
a private `source()`, friend `QVideoWindow`). `qVideoPreferredFrameRate()` returns:

* the slowest whole multiple of the rate that the display shows with an even cadence, i.e. that is
  the refresh rate divided by a whole number n >= 2 and a whole number itself (the rates qtbase
  paces exactly, `QWindow::preferredFrameRate` docs), or up to 0.2% slower than one (23.976,
  29.97), but not faster, whose frames would be dropped (R10-1; a 1e-6 slack for float rates). So
  on a display just below a whole refresh rate (59.94, 119.88 Hz), whose exact rates are just below
  whole ones (29.97), whole-rate content (30 fps) is faster and gets none (R11-1);
* otherwise 0, no preference: what the window got before. Also for less than a frame an hour, as
  qtbase's timer path, which keeps the multiples from overflowing `qRound` (R8-4).

It's only set where it's worth it (`QVideoWindowPrivate::setsPreferredFrameRate()`):

* on macOS, on the cocoa platform with vertical sync (`QCocoaWindow::updatesWithDisplayLink()`),
  where the preference paces update requests to the display (R7-2);
* on a display with a variable refresh rate, `QAVFHelpers::hasVariableRefreshRate()`:
  `NSScreen.maximumRefreshInterval > minimumRefreshInterval` (ProMotion, Adaptive-Sync) (R8-1);
* for a `QMediaPlayer`'s frames only (R8-2), and only while it plays (R9-2).

Otherwise the value is 0. It's written while the window's preference is the one the window set
itself, or none (R9-1, R10-4): so it's reset once it no longer applies (the window moved to a fixed
refresh rate display, the player paused or went away, vsync turned off), and a preference that
something else set on the window, before or after, is neither replaced nor reset (unless it's the
same value, set while the window's own is in effect, with no frame in between: QWindow tells
nothing about an unchanged value). Once another value is there, the window forgets its own
(the else branch, R12-3), so a later equal value isn't taken for its own either. The
`QVideoWidget` class documentation says what the widget's internal window does, and its cost.
iOS gets none: it doesn't tell whether a display has a variable refresh rate, and iOS applications
mostly use QML `VideoOutput`, which sets none anyway.

| content | 60 Hz | 120 Hz | 240 Hz |
|---|---|---|---|
| 24, 23.976 fps | none | 24 | 24 |
| 25 fps | none | none | none |
| 30, 29.97 fps | 30 | 30 | 30 |
| 48 fps | none | none | 48 |
| 50 fps | none | none | none |
| 60 fps | none (full rate) | 60 | 60 |

(on displays with a variable refresh rate; on fixed ones, none at all)

## Why
The request's goal 2 is that the system arbitrates the refresh rate from the application's intent.
The ProMotion measurement (TESTING.md, "ProMotion measurement") showed what the intent buys for
video, which isn't what this commit first assumed:

* The panel: with FFmpeg it follows the content without a preference (92.9% and 93% of the time at
  24 Hz in the two valid default runs), so the preference isn't what lets it slow down there. With
  AVFoundation, the one valid default run had the panel at 60 to 120 Hz for 4.5 s with only the
  video on screen, and the M5 run at 24 Hz once back in ProMotion: the preference may lower the
  panel's rate there, but one run per arm doesn't settle R6-6.
* The cadence: without a preference the window renders a frame at the first display link callback
  after it arrives, so a frame arriving early or late is shown a refresh earlier or later, for 33
  or 50 ms instead of 41.7. With FFmpeg, whose frames come from its own clock, 79% to 94% of the
  window's updates were 41.7 ms apart without the preference, fewer in stretches and while another
  window updated the display at 120 Hz, and 98% to 100% with it; on screen, in the one undisturbed
  pair, 88% of the frames were shown for 41.7 ms against 97%. AVFoundation's frames follow the
  display: about as even without it (96.5% of the updates, 90.5% on screen).

The limits come from three review rounds:

* R7-1: asking for a rate the display can't show exactly is worse than asking for nothing: qtbase
  paces it at the next faster exact rate, so 25 fps at 30 Hz shows every fifth frame for 67 ms
  where the full rate never holds one longer than 50 ms. Only exact cadences get a preference.
* R7-2: with timer based update requests the preference is a minimum interval from the previous
  request, so after one stall every later frame stays late. Only where it paces to the display.
* R8-1: even an exact rate has a price. Alone on its screen, the window is delivered on the grid of
  that rate (the reviewer measured CoreAnimation keeping a (24,24,24) grid across pause and
  unpause), so a frame waits up to one frame interval for a tick, on average half, instead of up to
  one refresh: a lasting offset from the audio. 23.976 fps paced at 24 shows a frame twice as long
  every 42 s. On a fixed refresh rate display nothing is gained in exchange (the window renders
  once per frame either way, and the cocoa link already pauses between frames), so only displays
  with a variable refresh rate get it. There the trade is an even cadence for that latency
  (measured: a median of 5 to 33 ms from the update request to its delivery with FFmpeg, depending
  on where the frames fall on the grid, against 3 to 6 ms without; 17 to 33 against 9 ms with
  AVFoundation; from commit to display nothing changes). A frame that misses its tick holds the
  previous one for a whole interval (under a heavy load, 7.6% of the updates in one run, against
  0.3% without). The 0.2% tolerance stays, as 23.976 is the most common film rate.
* R8-2: cameras report the maximum rate of their format but deliver fewer frames in low light, and
  screen captures deliver on changes: their rate isn't the delivery rate, so only media players.
* R9-1: the preference was only ever written while it applied, so it stayed when it stopped
  applying: after a move from a ProMotion panel to a 60 Hz monitor a stale 24 was paced at 30 Hz,
  R7-1's judder again. Now it's written whenever it changes from or to one the window set.
* R9-2: a paused player delivers frames when seeking; they shouldn't wait for the grid.

QVideoWidget shows its video in an internal QVideoWindow, so it gets the same.

## Limits (documented)
* Latency on variable refresh rate displays, as above (R8-1): up to one frame interval, a frame
  near a tick may slip to the next, and 23.976 and 29.97 fps show about one frame in 1000 twice as
  long, every 42 and 33 s (R9-3, R10-1; the tolerance allows at most one in 500).
* Variable frame rate content reports its average rate (R6-5), which may happen to be exact.
* QML `VideoOutput` doesn't set a preference: the window is shared by the whole scene; the
  application sets `Window.preferredFrameRate` (R6-9).
* The panel rate and the cadence were measured on a 120 Hz ProMotion panel only; the move between
  a ProMotion panel and a fixed refresh rate display (README steps 6 and 7) wasn't run: this setup
  has the built-in panel only.
* Whether AVFoundation's decode display link, at the screen's maximum rate, keeps a ProMotion panel
  above the video's rate without the preference is open (R6-6, above).

## Tests
The tests were written on a fixed refresh rate display (the G95SC), so most use the autotest hook
`qt_setVideoWindowAssumesVariableRefreshRate()` (`Q_AUTOTEST_EXPORT`, developer builds). On the
ProMotion panel they take the variable path: they log "display with a variable refresh rate: true",
and `_isResetWhenItNoLongerApplies` skips its fixed-display block.

* `tst_QMultimediaUtils::qVideoPreferredFrameRate_returnsRateWithEvenCadence`: 39 rows (the table,
  0.5 fps → 1, a frame an hour → 1, every two hours → none, 1e-12 fps → none, 12.5 fps at 100 Hz →
  25, 1% slower than an exact rate → none, 0.1% faster → none (R10-1), 25 fps at `float(1.2)` →
  accepted, 30 fps at 59.94 Hz and 24 fps at 119.88 Hz → none, 23.976 fps at 119.88 Hz → 23.976
  (R11-1), the full rate, NaN, infinity, unknown display).
* `tst_QVideoWindow` (new, mock backend, whose player plays without media), for a rate the display
  shows exactly (its refresh rate divided by its smallest whole divisor above 1, so also on 75 or
  165 Hz):
  * `preferredFrameRate_isSetForRatesTheDisplayShowsExactly`: set; 2.5 refreshes per frame, an
    unknown rate and no frame give none; the playback rate counts;
  * `_isResetWhenItNoLongerApplies` (R9-1): a fixed refresh rate display, no vsync, the player gone;
  * `_isNotSetWhilePaused` (R9-2); `_isNotSetWithoutMediaPlayer` (R8-2);
  * `_leavesAnotherPreferenceAlone` (R10-4, R11-5): set before the window's own, and after it:
    neither replaced while it would apply nor reset after; another component then sets exactly
    the window's former value while paused, and it stays (R12-3: fails without the else branch,
    which forgets the window's own value); reset to 0 by the one who set it, the window sets its
    own again.
* `tst_QVideoFrameBackend`, real playback of `colors.mp4` (25 fps) at the speeds that make it the
  display's exact rates closest to 25, from the actual refresh rate (24 and 30 fps at 240 Hz, 30 and
  20 at 60, 24 and 18 at 144, 29.97 and 19.98 at 59.94; R11-1):
  `videoWindow_preferredFrameRate_isSetDuringPlayback`, `_followsPlaybackRate`,
  `_isResetWhenPaused` (pause, seek, the seek's frame resets it), and
  `_isOnlySetForVariableRefreshRate` (no hook: the real display, none on a fixed one; on a variable
  refresh rate display it requires a preference, R11-1).
* `tst_QVideoWidget::preferredFrameRate_followsStreamFrameRate` (mock backend, a playing player).
* Each fix broken on purpose is caught (TESTING.md, "Round 9" and "Round 10"): no reset, any
  playback state, the display check bypassed, any source, overwriting another preference, and
  the tolerance for faster rates.
* On the offscreen platform (a timer platform) the tests expect, and get, no preference.

## Verified
TESTING.md, qtmultimedia section, "Round 8" to "Round 10", "Series states", "Suites on the final
state", "ProMotion measurement" and "Round 13 changes".
