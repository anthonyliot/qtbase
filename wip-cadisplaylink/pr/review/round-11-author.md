# Round 11: author's response (qtmultimedia series)

Verdict received: APPROVE (minor 3, nit 2). All findings addressed; the changes are confined to M5
(its tests, the QVideoWidget documentation, one comment and one line of ownership logic) and the
documents and tooling. S1 to S4 and M6's patch are unchanged. Trees:
`pr/qtmultimedia-series/trees.txt`, S5 `7fb32794b550`, S6 `f4801ada7da2`, and
`refs/cadisplaylink/series/S*` updated.

| ID | Response |
|---|---|
| R11-1 minor | **Fixed**: `exactRatesToPlayAt()` computes the rates from the actual refresh rate (29.97 and 19.98 at 59.94 Hz, qreal), `_isOnlySetForVariableRefreshRate` requires a non-zero expectation on a variable refresh rate display, unit rows for 30 fps at 59.94 Hz and 24 fps at 119.88 Hz (none) and 23.976 fps at 119.88 Hz (23.976), and a sentence in the M5 document and README "Known limitations" (whole-rate content on a display just below a whole rate gets none). The viewprobe prints the refresh rate with 3 decimals. |
| R11-2 minor | **Fixed**: the QVideoWidget documentation says it's the window the widget shows the video in that asks, and mentions the whole multiple. |
| R11-3 minor | **Fixed**: every M document gives its current tree and `pr/qtmultimedia-series/trees.txt`; README "about one frame in 1000"; TESTING points at `probes/qtmultimedia/` and says the logs are in `/tmp`; the verification scripts are in `pr/qtmultimedia-series/verify/` (`verify-states.sh`, `run-suites.sh`, `leak.sh`, `ab-swap.sh`, with `$TMPDIR` and the durable probe, no job directory), and this round's verification ran with them; README's qtbase/qtdeclarative item says it's done (re-checked: 11 commits, `%G?` G, trees equal to the recorded ones). |
| R11-4 nit | **Fixed**: the row is wrapped. |
| R11-5 nits | **Fixed**: the viewprobe counts on the main thread; the final-suite runner keeps the name before `shift` (this round's logs are named right); the docs commit message mentions the series files and the probes; `count.sh` writes under `build/` (ignored by git); "(unless it's the same value)" in the comment and M5's message, and the window forgets its own value once another one is set, so a later equal value isn't taken for its own; a test line for the other component resetting to 0 and the window setting its own again; `finish.sh` checks `sign.sh` before sourcing it; `commit-series.sh` derives its repository from `QT5_REPO` like `finish.sh`. |

The display note: AppKit reads max 240 fps again (refresh interval fixed at 4.167 ms), and
CoreGraphics 240.000 Hz; TESTING records both readings.
