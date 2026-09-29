# Round 8: author's response (qtmultimedia series)

Verdict received: REQUEST CHANGES (blocker 1, major 1, minor 4, nit 1). All accepted; the claims
checked first (R8-3 reproduced with the offscreen run, R8-4 by arithmetic, R8-6 by reading
`finish.sh`, R8-1's premise with an AppKit probe of this display's refresh interval range).
Trees: `/tmp/mm/series4-trees.txt`; messages `/tmp/mm/s7-{1..6}.txt` (M2 and M5 changed).

| ID | Response |
|---|---|
| R8-1 blocker | **Fixed (M5)** as proposed: the preference is only set on displays with a variable refresh rate. New `QAVFHelpers::hasVariableRefreshRate(QScreen *)` (`qavfhelpers.mm`, macOS): `NSScreen.maximumRefreshInterval > minimumRefreshInterval`; this display reports min = max = 4.167 ms, so it gets no preference (the new `_isOnlySetForVariableRefreshRate` checks that). iOS now gets none: it doesn't tell whether a display is variable, and iOS applications mostly use QML `VideoOutput`, which sets none. Where it's still set, the trade-off is in the M5 message and document: a frame may wait up to one frame interval for the grid (on average half), and 23.976 fps shows a frame twice as long every 42 s. The 0.2% tolerance stays: 23.976 is the most common film rate, so dropping it would drop the headline case; the README lists the ProMotion measurement of the panel rate and this latency as a pre-Gerrit item. |
| R8-2 major | **Fixed (M5)**: only a `QMediaPlayer` source's frames get a rate; cameras and screen captures get none (comment and message say why). New test `_isNotSetWithoutMediaPlayer`, which fails without the check (120 instead of 0). The other preference tests attach a player. |
| R8-3 minor | **Fixed (M2)**: the run loop mode test skips unless the platform is cocoa; offscreen now skips it (ffmpeg: 10 passed, 2 skipped). M2's test file state now includes `qguiapplication.h`. |
| R8-4 minor | **Fixed (M5)**: less than a frame an hour gets none (as qtbase's timer path), which keeps the multiples far from `qRound`'s range; rows for a frame an hour (1 Hz), every two hours (none), and 1e-12 fps (none). |
| R8-5 minor | **Fixed (M5)**: the playback tests play the 25 fps video at the speeds that make it the display's exact rates closest to 25 (240 Hz: 24 and 30; 60 Hz: 30 and 20; 144 Hz: 24 and 18), require a non-zero expectation where the platform paces, and require the second rate to change it. The synthetic tests use the refresh rate divided by its smallest whole divisor above 1, which also fixes a bug I found before your review: "half the refresh rate" isn't exact at 75 or 165 Hz. |
| R8-6 minor | **Fixed**: `/tmp/mm/qtbase-docs.txt` written, and `finish.sh` checks every file it needs (scripts, trees, all messages) before the first signature. It now runs `commit-series4.sh`. |
| R8-7 nits | **Fixed**: "use the main screen" in the constructor comment; the platform name is read per call, no static; M2's message says what changes on iOS (UIKit's tracking mode); the default-mode logs are kept; and instead of only listing them as not run: a real `NSMenu` and a real `runModalForWindow:` session with the AVFoundation backend (default mode: 1 and 0 frames in 1 s; common modes: 30 and 25), and an iOS simulator syntax check of `avfdisplaylink.mm` at upstream, S1, S2, S3 and the final state (clean). Live resize and a full iOS build are in "Not run". |

A disclosure on the tests, as you asked about circularity in round 8: `_isOnlySetForVariableRefreshRate`
follows `hasVariableRefreshRate()` by design (with the helper broken to always true it still passes);
the helper's answer for this display is established separately by the AppKit probe. The other
preference tests compare with `qVideoPreferredFrameRate()` for the window's actual inputs, and the
34-row unit table pins that function.
