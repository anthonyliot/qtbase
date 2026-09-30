#!/bin/zsh
# matrix.sh <prefix> <full|child> <runs> [light|display|hitches] [seconds] [fps] [backends...]:
# the A/B, interleaved, per backend (default: ffmpeg darwin): the clip (default 24 fps) with M5's
# preference, and with the default range (another preference, 120, set first). Recordings of
# <seconds> (default 10; the c5 runs used 8). Clips in $PROMOTION_OUT, e.g. for 24, 25 and 30 fps:
#   ffmpeg -f lavfi -i testsrc2=size=1280x720:rate=24 -t 300 -pix_fmt yuv420p 24fps.mp4
# A 30 fps clip (M5: 30 on 120 Hz) tells a panel following the video (30 Hz) from an idle one
# (24 Hz); a 25 fps one gets no preference in either arm.
# Then, in $PROMOTION_OUT: analyze.py <labels>, cadence.py <labels>, qtlog.py <labels> (labels:
# <prefix>-<backend>-<fps>-m5-<run> and <prefix>-<backend>-<fps>-dflt-<run>).
O=${PROMOTION_OUT:-${TMPDIR:-/tmp}/promotion}
here=${0:A:h}
prefix=$1 mode=$2 runs=$3 kind=${4:-light} secs=${5:-10} fps=${6:-24}
backends=(${@[7,-1]})
(( ${#backends} )) || backends=(ffmpeg darwin)
for (( run = 1; run <= runs; ++run )); do
  for be in $backends; do
    $here/measure.sh $prefix-$be-$fps-m5-$run   $be $O/${fps}fps.mp4 0   $secs $mode $kind
    $here/measure.sh $prefix-$be-$fps-dflt-$run $be $O/${fps}fps.mp4 120 $secs $mode $kind
  done
done
print "ALL DONE"
