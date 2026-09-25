# WIP: CADisplayLink / frame-rate intent for Qt on Apple platforms

Work-in-progress branch `wip/cadisplaylink` in qtbase. **This directory is not meant to be
upstreamed.** Drop the first commit before pushing to Gerrit.

* [AUDIT.md](AUDIT.md): where Qt uses CVDisplayLink, what's possible, what's missing, measured
  CADisplayLink behavior on a 240 Hz panel
* [PLAN.md](PLAN.md): commit-by-commit plan and verification
* [API-PROPOSAL.md](API-PROPOSAL.md): public API we'd like later (QWindow frame-rate range,
  update-request timing, CAMetalDisplayLink in QRhi)
* [CLAUDE-NOTES.md](CLAUDE-NOTES.md): session notes/state for resuming with Claude Code
* [probes/](probes/): standalone AppKit programs that produced the measurements
* [restore.sh](restore.sh): set up the branch and a build on another machine

## Using it in an application (no public API needed)

```cpp
// Ask for ~30 fps for this window (min = max = preferred = 30)
window->setProperty("_q_preferredFrameRateRange", 30);

// Full control: minimum, maximum, preferred (like CAFrameRateRange)
window->setProperty("_q_preferredFrameRateRange", QVariantList{ 30, 120, 60 });
window->setProperty("_q_preferredFrameRateRange",
                    QVariantMap{ {"minimum", 30}, {"maximum", 120}, {"preferred", 60} });

// Back to the system default
window->setProperty("_q_preferredFrameRateRange", QVariant());
```

QML: declare the property on the window, e.g.
`Window { property var _q_preferredFrameRateRange: 60 }`.

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
