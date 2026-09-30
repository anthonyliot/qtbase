#!/bin/zsh
# measure.sh <label> <backend> <clip> <rate> <seconds> <full|child> [light|display|hitches]
#
# Plays <clip> with QT_MEDIA_BACKEND=<backend> in the viewprobe, full screen ("full", in a space of
# its own) or as a child window of a full screen window ("child", like QVideoWidget, composited by
# the window server). Check that the probe's window was exposed: a full screen space that isn't
# the one on the display leaves an idle panel at 24 Hz (analyze.py: NOT SHOWN). The probe first sets
# another preference <rate> on the video window (0: none), which M5 leaves alone: 120 on a 120 Hz
# display is the default range, as without M5. Records an Instruments trace of <seconds>, attached
# to the probe once playback has settled, then exports the display tables.
#
# "light" (the default) records the Display and Core Animation Commits instruments, as the l3 runs
# did. "display" records the Display instrument alone, as the c5 runs did. "hitches" records the
# Animation Hitches template, a whole kernel trace of about 300 MB per second: slow to save, and
# its runs had gaps of up to 4 s in the probe's frames that nothing explains; not for the rate.
# The probe logs its display link (qt.qpa.screen.updates) with wall-clock times, and prints whether
# its window is exposed every second: analyze.py only uses the log inside the recording (the trace's
# table of contents), and marks a run whose window delivered nothing there NOT SHOWN.
# xctrace was seen to hang when the attached process exits while it stops recording, so the probe
# plays until xctrace is done; a run whose xctrace isn't done 15 minutes after recording is
# interrupted and marked FAILED.
#
# PROMOTION_OUT is the output directory (default $TMPDIR/promotion), with the probe built in vp/:
#   cmake -S ../viewprobe -B $PROMOTION_OUT/vp -DCMAKE_PREFIX_PATH=<Qt>
#   cmake --build $PROMOTION_OUT/vp
O=${PROMOTION_OUT:-${TMPDIR:-/tmp}/promotion}
label=$1 be=$2 clip=$3 rate=$4 secs=$5 mode=$6 kind=${7:-light}
[[ -x $O/vp/viewprobe && -f $clip && -n $mode ]] ||
    { print "usage: see the comment; the probe goes in $O/vp"; exit 2; }
print "load before: $(sysctl -n vm.loadavg)" > $O/$label.probe.txt
QT_MEDIA_BACKEND=$be QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_RULES='qt.qpa.screen.updates*=true' \
QT_MESSAGE_PATTERN='%{time yyyy-MM-ddTHH:mm:ss.zzz} %{category} %{message}' \
    $O/vp/viewprobe $clip 1800 $rate $mode >> $O/$label.probe.txt 2> $O/$label.qtlog.txt &
pid=$!
sleep 6
case $kind in
  hitches) instruments=(--template 'Animation Hitches') ;;
  display) instruments=(--instrument Display) ;;
  *) instruments=(--instrument Display --instrument 'Core Animation Commits') ;;
esac
s=$(date +%s)
xcrun xctrace record $instruments --attach $pid --time-limit ${secs}s --output $O/$label.trace \
    > $O/$label.xctrace.log 2>&1 &
xpid=$!
while kill -0 $xpid 2>/dev/null; do
  if (( $(date +%s) - s > secs + 900 )); then
    kill -INT $xpid; sleep 60; kill -KILL $xpid 2>/dev/null; print FAILED >> $O/$label.probe.txt
    break
  fi
  sleep 2
done
wait $xpid; rc=$?
print "xctrace rc=$rc in $(( $(date +%s) - s )) s," \
      "load after recording: $(sysctl -n vm.loadavg)" >> $O/$label.probe.txt
kill -TERM $pid 2>/dev/null; wait $pid 2>/dev/null
xcrun xctrace export --input $O/$label.trace --toc > $O/$label.toc.xml 2>/dev/null
for t in display-vsyncs-interval displayed-surfaces-interval coreanimation-commit-interval; do
  xcrun xctrace export --input $O/$label.trace \
      --xpath "/trace-toc/run[@number=\"1\"]/data/table[@schema=\"$t\"]" \
      > $O/$label.$t.xml 2>/dev/null
done
