# PR: CADisplayLink and frame-rate control for Qt on Apple platforms

This directory describes every change on the `wip/cadisplaylink` branches, one file per commit, so
that a reviewer (human or agent) can review the whole PR without the conversation that produced it.
Review findings and the author's answers are kept in [review/](review/).

## Goal (the original request)

1. Stop using the deprecated **CVDisplayLink** on macOS and use **CADisplayLink**.
2. Let professional applications built with Qt (video players, editors, games) **control their
   frame rate**, so that on high refresh rate displays (120 Hz ProMotion, 240 Hz external) the
   system arbitrates the refresh rate from the application's intent instead of every animating
   window running at the maximum.
3. Public API couldn't change at first, so a private mechanism came first; a public API prototype
   (`QWindow::preferredFrameRate`) followed, for Qt 6.13.
4. Tests that prove there is no regression, and that frame rates can be controlled.
5. CAMetalDisplayLink was considered and deferred (see `../API-PROPOSAL.md`).

## Where the code is

| Repo | Branch | Base | Fork |
|---|---|---|---|
| qtbase | `wip/cadisplaylink` | `25d8223e59f` (dev) | git@github.com:anthonyliot/qtbase.git |
| qtdeclarative | `wip/cadisplaylink` | `ec2f2fdea8` (dev) | git@github.com:anthonyliot/qtdeclarative.git |
| qtmultimedia | `wip/cadisplaylink` | `635067497` (dev) | git@github.com:anthonyliot/qtmultimedia.git |
| qt5 | `wip/cadisplaylink` | dev | git@github.com:anthonyliot/qt5.git (submodule pointers only) |

Full diffs: `git -C qtbase diff 25d8223e59f..wip/cadisplaylink -- . ':!wip-cadisplaylink'`,
`git -C qtdeclarative diff ec2f2fdea8..wip/cadisplaylink` and
`git -C qtmultimedia diff 635067497..wip/cadisplaylink`.

## Architecture in one page

* **One CADisplayLink per screen** (`QCocoaScreen`, `QIOSScreen`), created from the NSScreen /
  UIScreen, on the main run loop in common modes (iOS: default mode, unchanged). It's paused when
  no window on the screen has a pending update request, and resumed by the next
  `QWindow::requestUpdate()`. Multiple displays: each has its own link and rate.
* **Frame-rate intent per window**: `QWindow::preferredFrameRate` (public, 6.13), or the internal
  `_q_preferredFrameRateRange` property / `QT_APPLE_PREFERRED_FRAME_RATE_RANGE` env var. The public
  rate is mapped to an exact rate the display supports: the refresh rate divided by one of its
  divisors (CoreAnimation only runs links at whole rates dividing the refresh rate), the slowest
  one not below the preference (so 25 fps gives 30 on 120 Hz).
* **Shared link, per-window pacing**: the link's `preferredFrameRateRange` is the union of the
  pending windows' ranges (greatest common rate for exact rates, so 24 fps video + 60 fps UI keep
  the link at 120 on a 120 Hz panel). Windows wanting less than the link's rate skip frames based
  on the link's target timestamps (`QAppleFrameRateRange::shouldDeliverFrame`).
* **Frame interval for animations**: `QWindowPrivate::updateRequestInterval` is set during
  delivery to the interval the window is paced at; Qt Quick's animation driver advances by it.
* **Timer platforms** (xcb, Windows without DXGI vsync, Android, eglfs, offscreen): the preference
  is a minimum interval in `QPlatformWindow::requestUpdate()`.
* **Qt Widgets**: when the platform paces update requests (`QPlatformWindow::pacesUpdateRequests()`,
  i.e. the window has a preference on cocoa/ios with vsync on), top-level `update()`s go through
  `QWindow::requestUpdate()` instead of a posted `UpdateRequest` event.
* **Nested event loops** in delivery (modal dialog from a paint event) on macOS: a watchdog timer
  switches the screen's windows to timer based update requests until the loop returns.

## The Gerrit series (review round 2 on)

What goes to Gerrit, rebuilt from the final tree as logical changes (review round 1, R1-7), in
worktrees under `~/Desktop/bitbucket/qt5-series/`, branches `wip/cadisplaylink-gerrit`. Its tree
is identical to `wip/cadisplaylink` without `wip-cadisplaylink/`. Built and tested commit by commit,
see [TESTING.md](TESTING.md). Documents: [series/](series/).

| # | qtbase commit (`wip/cadisplaylink-gerrit`) | Contains (old commits) |
|---|---|---|
| [G1](series/G1-tests-delivery.md) | `33df309acc2` tst_QWindow: Test the rate and delivery of update requests | 07, 19 (baseline part) |
| [G2](series/G2-cadisplaylink.md) | `0bb7668b5f5` cocoa: Replace CVDisplayLink with CADisplayLink for update requests | 03, 09 (private interval), 10 (cocoa part), 16, 17, 18, 20, 28, 29; R1-1, R1-4, R1-5, R2-1 |
| [G3](series/G3-doc.md) | `e540b6b2c69` Doc: Refer to CADisplayLink instead of CVDisplayLink | 05 |
| [G4](series/G4-qwindow-api.md) | `4ecd0f4a096` Add QWindow::preferredFrameRate | 22 (generic parts); R1-6 |
| [G5a](series/G5a-framerate-model.md) | `d6efb26498f` Add a shared model of display link frame rates for Apple platforms | 02, 09 (helper part), 15, 23 (helper part), 30; R1-1, R1-2, R1-3, R1-11, R1-12 |
| [G5b](series/G5b-ios.md) | `bfdd5bad25a` ios: Pace update requests to the windows' preferred frame rates | 06, 10, 16, 18, 23 (iOS parts); R1-9, m9 |
| [G5c](series/G5c-cocoa.md) | `eaeb583f860` cocoa: Pace update requests to the windows' preferred frame rates | 04, 10, 23, 25 (cocoa parts), the Apple parts of the property doc |
| [G6](series/G6-widgets.md) | `fc439691c5e` Widgets: Pace top-level updates when the window has a preferred rate | 24, 32; R1-8, R1-13; the Widgets part of the property doc |
| [G7](series/G7-manual-test.md) | `09ff153f888` Add a manual test for update request pacing and frame rates | 08, 11, 14, 26 |

| # | qtdeclarative commit (`wip/cadisplaylink-gerrit`) | Contains (old commits) |
|---|---|---|
| [D1](series/D1-animation-interval.md) | `7c4be21eb2` Advance vsync based animations by the window's frame interval | 01-04, 06, the Animator test fixes |
| [D2](series/D2-qml-doc-tests.md) | `d8bc4071be` Document Window.preferredFrameRate, and test it from QML | 05, R1-6/R1-10 fixes |

### qtmultimedia (review rounds 4 to 12)

The qtmultimedia branch is itself the series (no WIP commits): six commits on `635067497`, each
built and tested at its own state (TESTING.md, "Series states"). Their trees are recorded in
`qtmultimedia-series/trees.txt` (and kept from `git gc` by `refs/cadisplaylink/series/S1..S6` in
qtmultimedia), messages in `qtmultimedia-series/M{1..6}.txt`, and
`qtmultimedia-series/commit-series.sh` commits them signed, refusing a tree that differs from the
tested one; `qtmultimedia-series/finish.sh` does the whole sequence. The probes are in
`../probes/qtmultimedia/`.

| # | Commit | Contains |
|---|---|---|
| [M1](series/M1-avfdisplaylink-leak.md) | darwin: Don't leak the display link of AVFDisplayLink | the observer/link retain cycle (pre-existing), R6-3 |
| [M2](series/M2-common-run-loop-modes.md) | darwin: Keep polling for video frames while menus and dialogs are open | R7-3 (pre-existing on macOS 15+ and iOS) |
| [M3](series/M3-drop-cvdisplaylink.md) | darwin: Stop using the deprecated CVDisplayLink in AVFDisplayLink | R1-10 (was `2152cdbd8`) |
| [M4](series/M4-stream-frame-rate.md) | Report the stream frame rate of played video frames | FFmpeg and AVFoundation, R7-4 test |
| [M5](series/M5-qvideowindow-preferred-rate.md) | QVideoWindow: Let the display refresh at the video's frame rate | R6-1, R6-5, R7-1, R7-2, R8-1, R8-2, R8-4, R8-5, R9-1 to R9-3, R10-1, R10-4, R11-1, R11-2, R11-5 |
| [M6](series/M6-per-screen-decode-clock.md) | darwin: Poll for video frames in sync with the display the video is on | R6-2, R6-4, R6-7, R6-8, R6-10, R7-5, R7-7 |

In short: on a macOS display with a variable refresh rate (ProMotion, Adaptive-Sync), a
`QVideoWindow` (and so `QVideoWidget`) asks, while a media player plays, for the rate its frames
arrive at (the stream's rate times the playback rate), when the display shows it with an even
cadence (24 fps on 120 Hz, 30 fps on 60, 120 and 240 Hz, ...), so that the display can refresh at
that rate; the qtbase changes turn it into a display rate per screen, and it's reset once it no
longer applies. Fixed refresh rate displays, iOS, paused players and cameras get none. The
AVFoundation backend's decode clock follows the display the video is shown on, and keeps running in
menus and modal sessions. QML `VideoOutput` sets no preference (R6-9): its window is the whole
scene's.

## Commits of the working branches and their documents

The working branches keep the history that led to the series; the documents below describe it.

`Plan` is what should happen to the commit when it goes to Gerrit (see "Upstreaming" below).

### qtbase

| # | Commit | Subject | Plan |
|---|---|---|---|
| 01 | `1183cae7f6a` | WIP: Add CADisplayLink audit, plan and API proposal | drop |
| [02](qtbase/02-qappleframerate-helper.md) | `efae5dc0bdf` | Add QAppleFrameRateRange helper for display link frame-rate intent | keep, + 15 |
| [03](qtbase/03-cocoa-cadisplaylink.md) | `f7240d14d39` | cocoa: Replace CVDisplayLink with CADisplayLink for update requests | keep, + 16, 17, 20, 28 |
| [04](qtbase/04-cocoa-preferred-range.md) | `07923f8f3d0` | cocoa: Let windows express a preferred frame-rate range | keep |
| [05](qtbase/05-doc-cadisplaylink.md) | `ad8e1183c91` | Doc: Refer to CADisplayLink instead of CVDisplayLink | keep |
| [06](qtbase/06-ios-preferred-range.md) | `8e35d2b83e2` | ios: Honor the preferred frame-rate range of windows | keep |
| [07](qtbase/07-tst-qwindow-pacing.md) | `1c4f0e03170` | tst_QWindow: Add tests for update request pacing and frame rates | keep, + 19 |
| [08](qtbase/08-manual-test.md) | `6527194bc72` | Add manual test for display link pacing and frame-rate preferences | keep, + 11, 14, 26 |
| [09](qtbase/09-update-request-interval.md) | `04eccb2734a` | Track the expected interval between paced update requests | keep, + 18 |
| [10](qtbase/10-report-interval.md) | `53f2184ac65` | cocoa, ios: Report the update request interval to the window | keep |
| [11](qtbase/11-manual-test-options.md) | `f48f930cd3c` | displaylink manual test: Add options for automated measurements | squash into 08 |
| 12 | `bbb0009a14e` | WIP: Record hands-on checks, benchmarks and the Effect Maker A/B | drop |
| 13 | `8b4a07cdddc` | WIP: Add cool-retro-term build notes and A/B benchmark | drop |
| [14](qtbase/14-manual-test-license.md) | `0adee5889c3` | displaylink manual test: Use the license required for tests | squash into 08 |
| [15](qtbase/15-round-pacing.md) | `a901ccb10aa` | QAppleFrameRateRange: Round pacing to the nearest frame count | squash into 02 |
| [16](qtbase/16-dont-pause-pending.md) | `7862556b859` | cocoa, ios: Don't pause the display link while a request is pending | keep (fixes a pre-existing bug) |
| [17](qtbase/17-stop-fallback-timer.md) | `925147b8de0` | cocoa: Stop the fallback update timer once the display link delivers | squash into 03 |
| [18](qtbase/18-interval-only-during-delivery.md) | `e1368147955` | cocoa, ios: Only report the update request interval during delivery | squash into 09/10 |
| [19](qtbase/19-tst-expectations.md) | `9e05b1ccbba` | tst_QWindow: Make the frame-rate expectations follow the pacing rules | squash into 07 |
| [20](qtbase/20-event-tap-comment.md) | `5cf2ecde754` | cocoa: Update the live resize event tap comment for CADisplayLink | squash into 03 |
| 21 | `37bfe3328a5` | WIP: Record ProMotion results and the patch set review | drop |
| [22](qtbase/22-qwindow-preferredframerate.md) | `71f67301a9b` | Add QWindow::preferredFrameRate | keep (API review) |
| [23](qtbase/23-apple-public-api.md) | `cbace1505b6` | cocoa, ios: Honor QWindow::preferredFrameRate with exact display rates | keep, + 29, 30 |
| [24](qtbase/24-widgets-paced-updates.md) | `1060540e5eb` | Widgets: Pace top-level updates when the window has a preferred rate | keep |
| [25](qtbase/25-tst-qwindow-api.md) | `0da9df72c2f` | tst_QWindow: Test QWindow::preferredFrameRate | keep |
| [26](qtbase/26-manual-test-rate-trace.md) | `a92aa4ade7c` | displaylink manual test: Add --rate and --trace | squash into 08 (after 22) |
| 27 | `a55bd739c73` | WIP: Record video frame rate results and the public API design | drop |
| [28](qtbase/28-drop-corevideo.md) | `7a6a8974c1a` | cocoa: Don't link CoreVideo anymore | squash into 03 |
| [29](qtbase/29-watchdog-tidy.md) | `5c00de26f2b` | cocoa: Tidy up the nested event loop watchdog | squash into 23 |
| [30](qtbase/30-supported-rates.md) | `13038efe719` | cocoa, ios: Only pick frame rates the display link supports exactly | squash into 23 |
| 31 | `5b860d5930f` | WIP: Record the supported display link rates and the self-review | drop |
| [32](qtbase/32-widgets-test-diagnostics.md) | see git log | tst_QWidgetRepaintManager: Report the rates when resetting the rate fails | squash into 24 |
| 33 | see git log | WIP: Add the PR documents for review | drop |

### qtdeclarative

| # | Commit | Subject | Plan |
|---|---|---|---|
| [01](qtdeclarative/01-animation-frame-interval.md) | `f30452bc3e` | Advance vsync based animations by the window's frame interval | keep, + 03, 04 |
| [02](qtdeclarative/02-tst-animation-steps.md) | `b7a304f21c` | tst_qquickanimations: Test animation steps with a preferred frame rate | keep |
| [03](qtdeclarative/03-animators-refresh-interval.md) | `52c20d84ba` | Don't step render thread animators by the paced GUI interval | squash into 01 |
| [04](qtdeclarative/04-default-driver-only.md) | `23ce107427` | Only set the frame interval on the default animation driver | squash into 01 |
| [05](qtdeclarative/05-qml-doc-and-tests.md) | `14a08b8318` | Document Window.preferredFrameRate and test it from QML | keep (after qtbase 22) |
| [06](qtdeclarative/06-supported-rates-test.md) | `d57406c0b8` | tst_qquickanimations: Expect only frame rates the display link supports | squash into 05 |

qt5: [qt5.md](qt5.md) (WIP submodule pointer commits only, all dropped).

## Upstreaming

The branches are a working history: later commits fix earlier ones. For Gerrit, the plan above
squashes the fixups and drops every `WIP:` commit (the `wip-cadisplaylink/` directory), giving:

1. qtbase: helper (02+15) → CADisplayLink switch (03+17+20+28) → doc (05) → don't pause while
   pending (16) → private frame-rate range, cocoa (04) and iOS (06) → update request interval
   (09+18, 10) → tests (07+19) → manual test (08+11+14) → public API (22) → Apple public API
   (23+29+30) → Widgets (24+32) → API tests (25) → manual test `--rate` (26).
2. qtdeclarative: frame interval for animations (01+03+04) → tests (02) → QML doc and tests
   (05+06), after the qtbase public API.

The copyright headers say "The Qt Company Ltd."; the contribution's copyright holder still has to
be decided before upstreaming.

## Before sending to Gerrit

* **Stall A/B on the 120 Hz ProMotion panel** (condition of review R1-1): run the manual test
  with `QT_APPLE_PREFERRED_FRAME_RATE_RANGE=120` and `=1,120` (and the default and `--rate 30`),
  many short launches, on this branch and on the CVDisplayLink baseline plugin, and record the
  stall counts in TESTING.md. With the round 1 changes, these ranges are sent as the default range.
* Done: the qtbase and qtdeclarative series (`wip/cadisplaylink-gerrit` in `qt5-series/`) are
  committed and signed (`%G?` G for all 11), with exactly the tested trees (checked again on
  2026-09-29 against the recorded lists).
* Done: the qtmultimedia series is committed and signed on `wip/cadisplaylink`, `f0c358d29` (M1)
  to `0e21dc1b3` (M6), each commit checked against its tested tree by `commit-series.sh`, and pushed
  to the fork on 2026-09-29 with the qtbase documents and the qt5 pointers. Qt's sanity bot hints
  that M6's test uses `qWait()` (`framesWithin()` waits a fixed time on purpose, to count frames).
* qtmultimedia, the author's decisions: a QTBUG and `Pick-to:` for M1 and M2, which fix released
  versions (R7-8).
* qtmultimedia, M5's two round 12 nits, when M5 is revisited after the measurement: a test for the
  window forgetting its own value (R12-3), and "internal" in the QVideoWidget documentation.
* qtmultimedia, a session with the MacBook's built-in ProMotion panel (R9-4, R10-2; steps 1 to 3
  done on 2026-09-29, TESTING.md "ProMotion panel"), which is also
  the two-screen setup with the G95SC. `B=~/Desktop/bitbucket`,
  `P=$B/qt5/qtbase/wip-cadisplaylink/probes/qtmultimedia`:
  0. Open the lid, and make the built-in display the main display (System Settings > Displays):
     test windows open on the main display.
  1. `clang++ -fobjc-arc -framework AppKit $P/vrr/vrr.mm -o /tmp/vrr && /tmp/vrr`: the built-in
     panel is reported "variable" (the first time `hasVariableRefreshRate()` would be true).
  2. `cd $B/qtmm-build/tests/auto/integration/qvideoframebackend && QT_MEDIA_BACKEND=ffmpeg
     ./tst_qvideoframebackend videoWindow_preferredFrameRate_isOnlySetForVariableRefreshRate
     videoWindow_receivesFrames_afterMovingToAnotherScreen`: the first logs "display with a
     variable refresh rate: true" and expects a preference; the second runs (two screens).
  3. A 24 fps file, `ffmpeg -f lavfi -i testsrc2=size=1280x720:rate=24 -t 300 -pix_fmt yuv420p
     /tmp/24fps.mp4`, played by the viewprobe (`cmake -S $P/viewprobe -B /tmp/vp
     -DCMAKE_PREFIX_PATH=$B/qt5-build-nofw && cmake --build /tmp/vp`), `QT_MEDIA_BACKEND=ffmpeg
     /tmp/vp/viewprobe /tmp/24fps.mp4 120`, which prints the frames, the preferred frame rate and
     the screen every second: 24 frames, preferredFrameRate 24.000 on the panel.
  4. The panel's refresh rate meanwhile: Instruments, "Animation Hitches" template, the Display
     track (refresh every 41.7 ms if the panel follows). Not with a probe of its own CADisplayLink:
     that asks for its own rate. Again with `QT_MEDIA_BACKEND=darwin`: whether AVFDisplayLink's
     decode link keeps the panel at 120 Hz (R6-6), in which case M5 costs latency for nothing
     there; if the panel doesn't drop with FFmpeg either, reconsider M5 (the round 10 approval's
     condition).
  5. The latency the 24 Hz grid adds (R8-1), in the same trace: from the video window's commit to
     the refresh that shows it, for `/tmp/24fps.mp4` (paced at 24) and for a 25 fps file (no
     preference, the full rate), e.g. the same ffmpeg line with `rate=25`, or the tests'
     `colors.mp4`.
  6. The move R9-1 is about: while step 3 plays, drag the window to the G95SC and back:
     preferredFrameRate goes to 0.000 on the G95SC (fixed rate) and back to 24.000 on the panel.
  7. M6 (R7-5): the same with `QT_MEDIA_BACKEND=darwin`, the window on the G95SC (not the main
     display): 24 frames per second there too, from the G95SC's display link.
* Decide the copyright holder of the new files.

## Building and testing

Builds used (paths relative to `~/Desktop/bitbucket`):

* `qt5-build-cadisplaylink`: qtbase, framework build, developer build with tests.
* `qt5-build-nofw` + `qt5-build-nofw-qtdeclarative` (+ qtshadertools): non-framework build for Qt
  Quick (the framework build breaks moc include_next in qtdeclarative).
* `qt5-build-cadisplaylink-ios`: iOS simulator build of the qtbase tests.
* `qtmm-build`: qtmultimedia with tests, configured with `qt5-build-nofw/bin/qt-configure-module`
  (FFmpeg from Homebrew). Like every add-on built against an uninstalled qtbase, it writes its
  libraries and plugins into `qt5-build-nofw/lib` and `plugins/multimedia`, so an upstream A/B swaps
  those four files (`pr/qtmultimedia-series/verify/ab-swap.sh <set>`) instead of using a second
  build.

```sh
B=~/Desktop/bitbucket
cmake --build $B/qtmm-build --target tst_qvideoframebackend tst_qvideowidget tst_qmediaplayerbackend
cd $B/qtmm-build/tests/auto/integration/qvideoframebackend
QT_MEDIA_BACKEND=darwin ./tst_qvideoframebackend; QT_MEDIA_BACKEND=ffmpeg ./tst_qvideoframebackend
```

```sh
B=~/Desktop/bitbucket
cmake --build $B/qt5-build-cadisplaylink --target QCocoaIntegrationPlugin tst_qwindow \
      tst_qappleframerate tst_qwidgetrepaintmanager displaylink
$B/qt5-build-cadisplaylink/tests/auto/gui/platform/qappleframerate/tst_qappleframerate
$B/qt5-build-cadisplaylink/tests/auto/gui/kernel/qwindow/tst_qwindow
$B/qt5-build-cadisplaylink/tests/auto/widgets/kernel/qwidgetrepaintmanager/tst_qwidgetrepaintmanager
cmake --build $B/qt5-build-nofw && cmake --build $B/qt5-build-nofw-qtdeclarative \
      --target tst_qquickwindow tst_qquickanimations
$B/qt5-build-nofw-qtdeclarative/tests/auto/quick/qquickwindow/tst_qquickwindow
$B/qt5-build-nofw-qtdeclarative/tests/auto/quick/qquickanimations/tst_qquickanimations
```

The rate tests need a visible, uncovered window: don't use the machine while they run. Window
activation tests fail when the terminal keeps focus; they fail the same way without these changes
(`qt5-build-cadisplaylink/baseline-tst_qwindow.txt`).

Test results: [TESTING.md](TESTING.md).

## Known limitations (documented, not fixed)

* **Display link stall (review R1-1)**: on the 120 Hz ProMotion panel the display link was seen a
  few times to stop calling back while a window had a pending update request, with explicit
  private ranges for the maximum rate ((120,120,120), (1,120,0)). Not root-caused, and no
  CVDisplayLink A/B yet (the panel wasn't available for round 1). Mitigated: such ranges are sent as
  the default range, and a watchdog recreates a display link that hasn't called back for ten frames
  (at least 1 s) while update requests are pending (verified with a simulated stall).
* **qtmultimedia**: `AVFDisplayLink`'s CVDisplayLink fallback for macOS 14.x is removed (R1-10,
  resolved, M3). Still open there, all documented in the M documents:
  * Video only asks for its rate on macOS displays with a variable refresh rate, while a media
    player plays, and when the display shows it evenly: 25 and 50 fps content, and 24 fps on 60 Hz,
    keep the display at its full rate (R7-1, R8-1, R8-2, R9-2, by design). Where it asks, the window
    is shown on the grid of that rate: a frame may wait up to one frame interval, a frame near a
    tick may slip to the next, and 23.976 and 29.97 fps show about one frame in 1000 twice as long
    (R8-1, R9-3, R10-1). Content faster than an exact rate gets none, so on a display just below a
    whole rate (59.94 Hz) whole-rate content (30 fps) does too (R11-1). With the AVFoundation
    backend its decode display link may keep the panel at its full rate anyway (R6-6), so there the
    preference may only cost that latency; FFmpeg, the default backend, has no such link.
  * Variable frame rate video asks for its average rate (R6-5).
  * The AVFoundation decode clock runs at its screen's maximum rate, which may keep a ProMotion
    panel above the video's rate (R6-6, follow-up; not measurable on a fixed-rate display).
  * QML `VideoOutput` sets no preference; the application sets `Window.preferredFrameRate` (R6-9).
  * No automated test for the decode clock following the window's screen (one display here).

See `../REVIEW-API.md` for the reasoning; in short:

* Mixing the private property / env var ranges with public-API windows can pace below a
  preference (m7) or depend on window order (m8).
* iOS doesn't report refresh rate changes, so `QScreen::refreshRate()` can be stale (m9).
* The render thread's Animator driver assumes the nominal refresh rate; on ProMotion the panel
  drops to the preferred rate, so Animators run slow for ~100 ms until it switches to timer mode.
* QQuickWidget: only the composition is paced, its scene renders from its own timer.
* iOS: nested event loops in delivery are not handled (re-entrant delivery).
* The live-resize event tap workaround is kept but not re-validated with CADisplayLink.
* No public frame timing (target presentation time) yet; video apps should pick frames by time.
* Follow-up for the qtbase docs (G4, from the qtmultimedia review round 9):
  `QWindow::preferredFrameRate` doesn't say that a window paced below the display's rate is
  delivered on the grid of that rate, so an update may wait up to one interval of it. A sentence
  would help applications that opt in.
