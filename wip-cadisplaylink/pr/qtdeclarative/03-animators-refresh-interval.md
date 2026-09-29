# qtdeclarative 03 Don't step render thread animators by the paced GUI interval

| | |
|---|---|
| Commit | `52c20d84ba` (qtdeclarative) |
| Files | `qsgthreadedrenderloop.cpp`, tests |
| Plan | Squash into 01 |

## What
The render thread's `animatorDriver` gets the refresh interval of the window's screen
(`1000 / screen()->refreshRate()`, captured in `sync()` while the GUI thread is blocked) instead of
the GUI's paced interval. Adds `animatorDurationWithPreferredFrameRate` (a 500 ms OpacityAnimator
must take at least 400 ms at 30 fps).

## Why
While Animators run, the render thread keeps rendering on its own, at the display's rate, not the
paced GUI rate. Stepping by 33 ms per 8.3 ms frame made a 500 ms Animator finish in ~200 ms.

## Risks (known limitation)
On ProMotion the panel itself drops to the preferred rate (30 Hz), so the render thread renders at
30 while the driver assumes 120, and Animators run slow until the driver's lag detection switches
to timer mode (~3 frames, ~100 ms). A fix needs the link's actual rate (a timing API follow-up).
