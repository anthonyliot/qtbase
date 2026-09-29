# Round 10: author's response (qtmultimedia series)

Verdict received: APPROVE (minor 3, nit 2), on the condition that M5 doesn't go to Gerrit before
the ProMotion session; README keeps that as a pre-Gerrit step, now with the approval's condition
spelled out (if the panel doesn't drop with FFmpeg, reconsider M5). I addressed every finding
anyway; the changes are confined to M5 and the documents, so S1 to S4 and M6's patch are unchanged.
Trees: `pr/qtmultimedia-series/trees.txt` (S5 `9d6582f3ca7b`, S6 `80569af10b23`).

| ID | Response |
|---|---|
| R10-1 minor | **Fixed (M5)** the cleanest way you proposed: only content at or below an exact rate counts (up to 0.2% slower, with a 1e-6 slack for float rates), so faster content is never paced below its rate. Rows for 0.1% faster than 24 fps (none; fails with the symmetric check) and 25 fps at `float(1.2)` (accepted). "About one frame in 1000" in the comment, message, M5 document and README. |
| R10-2 minor | **Fixed (README)**: the checklist uses durable paths (`probes/qtmultimedia/`), makes the built-in panel the main display first, names the 24 fps file (`ffmpeg -f lavfi … testsrc2 … rate=24`), the program (the viewprobe, which now has a timed mode printing frames, preference and screen every second), the measurement (Instruments' Display track, not a CADisplayLink probe of its own), the latency comparison, and the R9-1 move between the panel and the G95SC. |
| R10-3 minor | **Fixed**: the messages, trees and scripts are in `pr/qtmultimedia-series/` (self-locating scripts, temporary index in `$TMPDIR`), the probes in `probes/qtmultimedia/`, both committed by the qtbase documents commit; the six trees are kept from `git gc` by `refs/cadisplaylink/series/S1..S6` in qtmultimedia (refs to trees: checked in a scratch repo that `git log --all`, `gc --prune=now` and `fsck` are fine with them). `finish.sh` commits `wip-cadisplaylink` as a whole, the probes included. |
| R10-4 nit | **Fixed (M5)**: the window remembers the value it set (`m_preferredFrameRate`) and only writes while the window's preference is that value or none, so another value, set before or after, is neither replaced nor reset. `_leavesAnotherPreferenceAlone` covers before, after, and after with playback paused; with round 9's rule back it fails (120 replaced 12.3). |
| R10-5 nits | **Fixed**: README names the durable paths; the M2 and M5 "Verified" sections point at the right rounds; the M5 message says "iOS paces too, but doesn't tell"; the QVideoWidget documentation says the widget *asks* for the rate and the display *can* refresh slower; TESTING says which libraries each stress A/B run used; `r9/-mock.log` removed. |

Verified (TESTING.md, "Round 10"): S5 built and tested (20/20 on both backends, `tst_qvideowindow`
7, `tst_qvideowidget`, `tst_qmultimediautils` 304, all 78 `destruction` rows (80 passed with init and cleanup), no leak); the suites M5
touches at S6.
