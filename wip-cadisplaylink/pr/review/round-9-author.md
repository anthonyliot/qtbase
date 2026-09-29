# Round 9: author's response (qtmultimedia series)

Verdict received: REQUEST CHANGES (blocker 1, minor 4, nit 1). All accepted; R9-1 is a bug of my
round 8 change, confirmed by reading the code (the only write was inside the qualifying branch).
Trees: `/tmp/mm/series5-trees.txt` (S1 to S4 unchanged since round 8; S5 and S6 new); messages
`/tmp/mm/s7-{1..6}.txt` (M5 changed).

| ID | Response |
|---|---|
| R9-1 blocker | **Fixed (M5)**: the rate is 0 whenever the conditions don't hold, and it's written whenever it or the previous value the window set is non-zero, so it's reset once it no longer applies (another display, no vsync, player paused or gone), while a preference someone else set is left alone (`m_setPreferredFrameRate`). New mock-backend test `tst_QVideoWindow::preferredFrameRate_isResetWhenItNoLongerApplies` (fixed display, no vsync, player gone) and `_leavesAnotherPreferenceAlone`; with the reset removed on purpose, 4 tests fail (TESTING.md, "Round 9"). The M5 message's "follows the window to other screens" is now true. |
| R9-2 minor | **Fixed (M5)**: only while the player is in `PlayingState`. Tests: `tst_QVideoWindow::_isNotSetWhilePaused` (mock) and the real-backend `tst_QVideoFrameBackend::_isResetWhenPaused` (pause, seek, the seek's frame resets it), both failing when the state check is removed. The synthetic tests moved to the new mock-backend `tst_qvideowindow`, whose player plays without media; the integration tests keep real playback. |
| R9-3 minor | **Fixed**: the tolerance comment says one frame in 1001 twice as long (every 42 s at 23.976), at most one in 500; the M5 message, document and README "Known limitations" mention the doubled frame, 29.97, and a frame near a tick slipping to the next; README says "30 fps on 60, 120 and 240 Hz"; the darwin backend's decode link possibly keeping the panel at full rate (so only the latency is paid) is in the M5 document and README; and the `QVideoWidget` class documentation says what the widget does and what it costs. |
| R9-4 minor | **Done**: README "Before sending to Gerrit" lists the concrete checks for a session with the built-in ProMotion panel (lid open), which is also the two-screen setup: the AppKit probe saying "variable", `_isOnlySetForVariableRefreshRate` and `_afterMovingToAnotherScreen` there, the panel rate for 24 fps with both backends, the grid latency, and M6's manual run. It needs the lid open, so it's for the user's session. |
| R9-5 minor | **Done**: run 2 recorded (251 passed, 7 failed), and an interleaved A/B of the three stress functions, three runs each: the `(video, playing)` rows failed 3 times upstream (0, 1, 2 per run) and 2 times with the series (1, 1, 0), always a slow start; the round 9 final run had none (TESTING.md, "Round 9"). |
| R9-6 nits | **Fixed**: the two long lines (the helper line wrapped; the integration test line moved away with its test); the negative checks rerun with the current names and with the check that matters, the display check bypassed, which `_isOnlySetForVariableRefreshRate` now catches with real playback; the menu probe counts on the main thread (context object), FFmpeg 31/26/25; the finish messages no longer name a round; the player and playback state are checked before AppKit is asked. |

Note taken for the qtbase reviewer (not in this series): the `QWindow::preferredFrameRate` docs
don't mention the latency of pacing on a grid; recorded in README as a qtbase follow-up.
