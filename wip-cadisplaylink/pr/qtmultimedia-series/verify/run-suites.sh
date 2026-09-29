#!/bin/zsh
# run-suites.sh: the full regression (every suite the series touches, both backends), on the
# worktree as it is; the test binaries are built by name and checked to be newer than their sources.
# The logs go to a new directory, never to one that exists: QTMM_RESULTS names where to create it
OUT=${QTMM_RESULTS:-$(mktemp -d ${TMPDIR:-/tmp}/qtmm-results.XXXXXX)}
[[ -e $OUT && ! -d $OUT ]] && { echo "$OUT isn't a directory"; exit 1; }
mkdir -p $OUT && [[ -z $(ls -A $OUT) ]] || { echo "$OUT isn't empty; not overwriting it"; exit 1; }
echo "logs in $OUT"
HERE=${0:A:h}; B=${QT5_REPO:-/Users/anthony.liot/Desktop/bitbucket/qt5}/..; T=$B/qtmm-build/tests/auto
TESTS=(tst_qvideoframebackend tst_qmediaplayerbackend tst_qquickvideooutput tst_qquickvideooutput_window
       tst_qvideowidget tst_qmediaplayerwidgets tst_qvideoframe tst_qvideoframeformat tst_qmediaplayer tst_qmultimediautils tst_qvideowindow)
# "all" doesn't include the tests in this build, so name them
cmake --build $B/qtmm-build --parallel --target Multimedia MultimediaQuick MultimediaWidgets QDarwinMediaPlugin QFFmpegMediaPlugin $TESTS \
    > $OUT/build.log 2>&1 || { echo "BUILD FAILED"; tail -5 $OUT/build.log; exit 1; }
# Every test binary must be newer than its own source (the build tracks headers and static
# libraries; a changed shared library is loaded at run time, without relinking)
S=${QTMM_REPO:-${QT5_REPO:-/Users/anthony.liot/Desktop/bitbucket/qt5}/qtmultimedia}/tests
for t in $TESTS; do bin=$(find $T -name $t -type f -perm +111 | grep -v "\.app/" | head -1); src=$(find $S -name $t.cpp | head -1)
  (( $(stat -f %m $bin) >= $(stat -f %m $src) )) || { echo "STALE BINARY: $t"; exit 1; }; done
echo "all ${#TESTS} test binaries are newer than their sources"
echo "build ok, warnings in the changed files: $(grep -E 'warning:' $OUT/build.log | grep -E -c 'avfdisplaylink|avfvideo|qvideowindow|qvideosink|qffmpegvideorenderer|qquickvideooutput|qplatformvideosink|qmultimediautils|tst_qvideo')"
run() { # name backend (mock: no QT_MEDIA_BACKEND)
  local bin=$(find $T -name $1 -type f -perm +111 | grep -v "\.app/" | head -1)
  [[ -z $bin ]] && { echo "$1 [$2]: binary not found"; return; }
  local log=$OUT/$1-$2.log
  if [[ $2 == mock ]]; then (cd ${bin:h} && timeout 3600 $bin > $log 2>&1); else (cd ${bin:h} && QT_MEDIA_BACKEND=$2 timeout 3600 $bin > $log 2>&1); fi
  echo "$1 [$2]: $(grep -h Totals $log | cut -c9-80)"
  grep -h "^FAIL" $log | cut -c1-170 | head -8
}
for t in tst_qvideoframebackend tst_qmediaplayerbackend tst_qquickvideooutput tst_qquickvideooutput_window; do
  for b in darwin ffmpeg; do run $t $b; done
done
for t in tst_qvideowidget tst_qmediaplayerwidgets tst_qvideoframe tst_qvideoframeformat tst_qmediaplayer tst_qmultimediautils tst_qvideowindow; do run $t mock; done
$HERE/leak.sh final
