#!/bin/zsh
# count.sh <label> <players>: run the probe, count live observers and display links with heap(1)
P=${0:A:h}; F=${VIDEO:-/Users/anthony.liot/Desktop/bitbucket/qt5/qtmultimedia/tests/auto/integration/qvideoframebackend/testdata/colors.mp4}
O=$P/build; mkdir -p $O   # outputs next to the build, which git ignores
QT_MEDIA_BACKEND=darwin $P/build/leakprobe $F $2 $3 > $O/$1.out 2>&1 &
local pid=$!
for i in $(seq 1 120); do grep -q "^ready" $O/$1.out && break; sleep 0.5; done
heap $pid > $O/$1.heap 2>&1
echo "$1: $(grep '^ready' $O/$1.out) | DisplayLinkObserver: $(grep -E ' DisplayLinkObserver ' $O/$1.heap | awk '{print $1}') | CADisplayLink: $(grep -E ' CADisplayLink ' $O/$1.heap | awk '{print $1}')"
kill $pid 2>/dev/null; wait $pid 2>/dev/null
