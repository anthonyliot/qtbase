# WIP: CADisplayLink / frame-rate intent for Qt on Apple platforms

Work-in-progress branch `wip/cadisplaylink` in qtbase. **This directory is not meant to be
upstreamed.** Drop the first commit before pushing to Gerrit.

* [AUDIT.md](AUDIT.md): where Qt uses CVDisplayLink, what's possible, what's missing, measured
  CADisplayLink behavior on a 240 Hz panel
* [PLAN.md](PLAN.md): commit-by-commit plan and verification
* [API-PROPOSAL.md](API-PROPOSAL.md): public API (QWindow::preferredFrameRate is now prototyped),
  update-request timing, CAMetalDisplayLink in QRhi
* [VIDEO.md](VIDEO.md): video frame rates on ProMotion, and guidance for video apps
* [REVIEW.md](REVIEW.md): the multi-agent code review and the status of its findings
* [DESIGN.md](DESIGN.md): the design panel for the public API and Widgets support
* [REVIEW-API.md](REVIEW-API.md): the review of the public API batch and what was done about it
* [CLAUDE-NOTES.md](CLAUDE-NOTES.md): session notes/state for resuming with Claude Code
* [probes/](probes/): standalone AppKit programs that produced the measurements
* [restore.sh](restore.sh): set up the branch and a build on another machine

## Using it in an application

Public API (prototype, proposed for Qt 6.13):

```cpp
window->setPreferredFrameRate(24000.0 / 1001);  // video: exact 24 Hz cadence on 120/240 Hz panels
window->setPreferredFrameRate(60);              // animated UI capped at 60
window->resetPreferredFrameRate();              // back to the system default
```

```qml
Window { preferredFrameRate: player.playing ? 24000 / 1001 : 60 }
```

Qt Widgets: set it on the top-level's window, `widget->windowHandle()->setPreferredFrameRate(30)`;
`update()` in that window (including QOpenGLWidget/QRhiWidget content) is then paced.

Qt picks the exact rate the display can show (refresh / n) closest to the preferred rate but not
below it, so 25 gives 30 on 120 Hz (see VIDEO.md). Windows with different rates stay exact
together.

Multiple displays: each screen has its own CADisplayLink, created from its NSScreen/UIScreen, so a
120 Hz built-in panel and a 60 Hz external display each run at their own rate, and a window's
preference only affects the display link of the screen it's on. When a window moves to another
screen, its pending update request moves to that screen's display link, and the old one pauses
if no window there needs updates. `tst_QWindow::preferredFrameRatePerScreen` checks this with two
screens connected.

For experiments without code changes (unsupported, will go away):

```cpp
// min = max = preferred = 30, rounded to the nearest exact rate
window->setProperty("_q_preferredFrameRateRange", 30);
window->setProperty("_q_preferredFrameRateRange", QVariantList{ 30, 120, 60 });
```

Application-wide default for windows without the property (also handy for unmodified apps):

```sh
QT_APPLE_PREFERRED_FRAME_RATE_RANGE=60 ./app            # 60 fps
QT_APPLE_PREFERRED_FRAME_RATE_RANGE=30,120,60 ./app     # min,max,preferred
```

Invalid values are ignored with a warning (logging category `qt.qpa.framerate`) and the system
default is used. CoreAnimation would otherwise throw.

The system can only run the display at an integer divisor of its refresh rate, and rounds up
when the request isn't one: 24 fps on a 60 Hz screen gives 30 fps, and 100 fps on a 240 Hz screen
gives 120 fps. Qt's per-window pacing follows the same rule.

Debug output: `QT_LOGGING_RULES="qt.qpa.screen.updates.debug=true;qt.qpa.framerate.debug=true"`.

## Restoring on another computer

Simplest, from the qt5 fork (its relative submodule URLs resolve to the qtbase/qtdeclarative forks):

```sh
git clone -b wip/cadisplaylink git@github.com:anthonyliot/qt5.git
cd qt5
git submodule update --init qtbase qtdeclarative
# Unchanged modules aren't forked, so point them at upstream:
git config submodule.qtshadertools.url https://github.com/qt/qtshadertools.git
git submodule update --init qtshadertools
```

Or with the script, for qtbase only:

```sh
# On this machine, publish the branch (pick one):
git -C qtbase push <your-remote> wip/cadisplaylink
git -C qtbase bundle create ~/cadisplaylink.bundle origin/dev..wip/cadisplaylink

# On the other machine:
curl -O <raw url of restore.sh>   # or copy it from the bundle/branch
sh restore.sh <remote-url-or-bundle> ~/qt5 ~/qt5-build-cadisplaylink
```
