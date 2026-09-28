# qtdeclarative 01 Advance vsync based animations by the window's frame interval

| | |
|---|---|
| Commit | `f30452bc3e` (qtdeclarative) |
| Files | `src/quick/scenegraph/qsgcontext{.cpp,_p.h}`, `qsgthreadedrenderloop.cpp` |
| Plan | Keep; squash 03 and 04 into it. Depends on qtbase 09 |

## What
* `QSGAnimationDriver::setFrameInterval()`/`frameInterval()`: the step per frame, falling back to
  the vsync interval when 0.
* `QSGDefaultAnimationDriver::advance()` adds `frameInterval()` instead of `m_vsync` in vsync mode,
  and uses it as the reference for lag detection (switch to timer mode after bad frames) and for
  switching back.
* New `virtual QSGContext::setFrameIntervalForAnimationDriver(driver, interval)`.
* Threaded render loop, GUI thread: `advanceAnimations` in `polishAndSync()` passes
  `QWindowPrivate::updateRequestInterval * 1000` (valid only during synchronous update request
  delivery; 0 in the queued expose path, which falls back to vsync). The multi-window timer path
  passes 0.
* Render thread (Animators): see 03.

## Why
With a window paced at 30 fps on a 240 Hz display, animations advanced 4.17 ms per 33 ms frame,
8 times too slow, until the lag detection switched to timer mode (uneven wall-clock steps).

## Risks and edge cases
* Private API; `QSGContext` subclasses in other modules get the default implementation.
* If the platform reports a wrong interval, animations run at the wrong speed until the lag
  detection kicks in (same as today with a wrong vsync).

## Tests
02 (`stepsWithPreferredFrameRate`).
