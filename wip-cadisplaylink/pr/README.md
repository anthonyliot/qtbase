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
| qt5 | `wip/cadisplaylink` | dev | git@github.com:anthonyliot/qt5.git (submodule pointers only) |

Full diffs: `git -C qtbase diff 25d8223e59f..wip/cadisplaylink -- . ':!wip-cadisplaylink'` and
`git -C qtdeclarative diff ec2f2fdea8..wip/cadisplaylink`.

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

## Commits and their documents

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

## Building and testing

Builds used (paths relative to `~/Desktop/bitbucket`):

* `qt5-build-cadisplaylink`: qtbase, framework build, developer build with tests.
* `qt5-build-nofw` + `qt5-build-nofw-qtdeclarative` (+ qtshadertools): non-framework build for Qt
  Quick (the framework build breaks moc include_next in qtdeclarative).
* `qt5-build-cadisplaylink-ios`: iOS simulator build of the qtbase tests.

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

See `../REVIEW-API.md` for the reasoning; in short:

* Mixing the private property / env var ranges with public-API windows can pace below a
  preference (m7) or depend on window order (m8).
* iOS doesn't report refresh rate changes, so `QScreen::refreshRate()` can be stale (m9).
* The render thread's Animator driver assumes the nominal refresh rate; on ProMotion the panel
  drops to the preferred rate, so Animators run slow for ~100 ms until it switches to timer mode.
* QQuickWidget: only the composition is paced, its scene renders from its own timer.
* iOS: nested event loops in delivery are not handled (re-entrant delivery).
* Delivery iterates raw `QWindow *` from `QGuiApplication::allWindows()`, as before this change; a
  delivery that deletes *another* window on the same screen is not guarded against.
* The live-resize event tap workaround is kept but not re-validated with CADisplayLink.
* No public frame timing (target presentation time) yet; video apps should pick frames by time.
