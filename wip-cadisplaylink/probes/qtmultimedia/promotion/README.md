# ProMotion measurement

Tools for README "Before sending to Gerrit", steps 4 and 5: what M5's preference does to a
ProMotion panel's refresh rate, to the cadence of the window's updates and of its frames on screen,
and to the latency. Results: `../../../pr/TESTING.md`, "ProMotion measurement".

1. Build the viewprobe and make the clips, in `$PROMOTION_OUT` (default `$TMPDIR/promotion`):

   ```sh
   export PROMOTION_OUT=${TMPDIR:-/tmp}/promotion; mkdir -p $PROMOTION_OUT
   cmake -S ../viewprobe -B $PROMOTION_OUT/vp -DCMAKE_PREFIX_PATH=~/Desktop/bitbucket/qt5-build-nofw
   cmake --build $PROMOTION_OUT/vp
   for r in 24 25 30; do
     ffmpeg -f lavfi -i testsrc2=size=1280x720:rate=$r -t 300 -pix_fmt yuv420p $PROMOTION_OUT/${r}fps.mp4
   done
   ```

   24 fps is what M5 paces at 24 Hz on a 120 Hz panel; 25 fps gets no preference in either arm; 30
   fps (M5: 30) tells a panel following the video (30 Hz) from an idle one, which sits at its slowest
   rate, 24 Hz.

2. Keep the display quiet: nothing else updating on it (video calls, animations, Control Center, the
   mouse), no display mode changes, and no heavy jobs if possible. Then
   `./matrix.sh <prefix> full <runs>` (full screen, the panel's rate) or
   `./matrix.sh <prefix> child <runs>` (QVideoWidget's layout, composited, the cadence on screen);
   more arguments set the recording (`light`: Display and Core Animation Commits; `display`: Display
   alone), its length, the clip's rate and the backends. Each run is `measure.sh`: a recording
   attached to the probe, the probe's display link log, the trace's table of contents and the
   exported tables.

3. In `$PROMOTION_OUT`:
   * `analyze.py <labels>`: per run, inside the recording: the time at 24 and 120 Hz, the probe's
     frames on screen and their cadence, the render cadence and the wait from an update request to
     its delivery (from the display link log), commit to display, other processes' and unattributed
     surfaces, and the display modes the probe read. A run whose window delivered nothing while
     recording is marked NOT SHOWN, and one with other surfaces or other modes is disturbed.
   * `cadence.py <labels>`: the intervals between the probe's consecutive frames on screen (in
     composited runs), at 41.7 ms when even, with the gaps in the frame numbers.
   * `qtlog.py <labels>`: the display link log alone, inside the recording.

Don't use the Animation Hitches template (`measure.sh ... hitches`) for the rate or the latency: it
records a whole kernel trace, is slow to save, and its runs had gaps of up to 4 s in the probe's
frames that nothing explains.
