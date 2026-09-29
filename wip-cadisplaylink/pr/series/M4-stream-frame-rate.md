# M4 Report the stream frame rate of played video frames

| | |
|---|---|
| Repo, branch | qtmultimedia `wip/cadisplaylink` |
| Files | `src/plugins/multimedia/ffmpeg/playbackengine/qffmpegvideorenderer.cpp`, `src/plugins/multimedia/darwin/mediaplayer/avfvideorenderercontrol.mm`, `tests/auto/integration/qvideoframebackend/tst_qvideoframebackend.cpp` |
| Tree | S4 `84212c21c771` (`pr/qtmultimedia-series/trees.txt`) |
| Change-Id | `Ic99b78a3f2c5e3da1263a85571302fa7c5ceceae` |
| From | the frame-rate integration; found by M5's end-to-end test |

## What
* FFmpeg: `format.setStreamFrameRate(av_q2d(stream->avg_frame_rate))` when the rate is valid.
* AVFoundation: `format.setStreamFrameRate(track.assetTrack.nominalFrameRate)`, computed once and
  reused for the frame's end time, which already used it.
* The other backends (android, gstreamer, ohos, qnx, wasm, windows) still report 0; the message
  names the two that change (R7-8).

## Why
`QVideoFrameFormat::streamFrameRate()` was 0 for every played frame with both backends, so a video
output couldn't know the rate the content plays at. M5 needs it. The first version of the M5 test
passed with a synthetic frame but failed when playing a file; this is the fix.

`avg_frame_rate` is the average: variable frame rate content reports its average (R6-5, documented
in M5). `r_frame_rate` often is a timebase-like value, so it isn't used.

## Tests
`tst_QVideoFrameBackend::streamFrameRate_isReportedForPlayedFrames` (R7-4): plays `colors.mp4`
(25 fps) and requires every valid frame of at least five to report 25. Skipped for the backends
that don't report it.

## Verified
Both backends, at S4 and on (TESTING.md, "Series states").
