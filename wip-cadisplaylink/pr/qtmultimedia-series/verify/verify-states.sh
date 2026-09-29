#!/bin/zsh
# verify-states.sh S1 S2 ...: build and test states of the series (../trees.txt, kept by
# refs/cadisplaylink/series/S*) in the qtmultimedia worktree and its build, qtmm-build next to qt5.
# The worktree must be the final state; every file the series touches gets the state's content, and
# the final state is restored (and its tree checked) at the end, also when killed. Logs in $OUT.
HERE=${0:A:h}; PROBES=${HERE:h:h:h}/probes/qtmultimedia
Q5=${QT5_REPO:-/Users/anthony.liot/Desktop/bitbucket/qt5}
cd ${QTMM_REPO:-$Q5/qtmultimedia} || exit 1
B=${QT5_REPO:-/Users/anthony.liot/Desktop/bitbucket/qt5}/..
OUT=${QTMM_STATES_LOGS:-$(mktemp -d ${TMPDIR:-/tmp}/qtmm-states.XXXXXX)}; mkdir -p $OUT; echo "logs in $OUT"
typeset -A TREE; while read s t; do TREE[$s]=$t; done < $HERE/../trees.txt
FINAL=${TREE[S6]}
wtree() { local TI=${TMPDIR:-/tmp}/qtmm-verify.$$.idx; rm -f $TI
          GIT_INDEX_FILE=$TI git read-tree HEAD && GIT_INDEX_FILE=$TI git add -A -- . && GIT_INDEX_FILE=$TI git write-tree
          rm -f $TI; }
# Every file the series touches (all of them differ between S1 and the final state) gets the
# state's content, written only when it differs, and files the state doesn't have are removed, so
# builds stay incremental
materialize() { local f want; for f in $(git diff-tree -r --name-only $FINAL ${TREE[S1]}); do
                  if git cat-file -e "$1:$f" 2>/dev/null; then
                    want=$(git rev-parse "$1:$f"); mkdir -p ${f:h}
                    [[ -f $f && $(git hash-object $f) == $want ]] || git cat-file blob $want > $f || exit 1
                  else rm -f $f; fi; done; }
restore() { local f; for f in $(git diff-tree -r --name-only $FINAL ${TREE[S1]}); do mkdir -p ${f:h}; git cat-file blob $FINAL:$f > $f; done
            [[ $(wtree) == $FINAL ]] && echo "restored final state $FINAL" || echo "RESTORE FAILED: $(wtree)"
            cmake $B/qtmm-build > /dev/null 2>&1 || echo "reconfigure after restore failed"; }
# If a kill -9 left the worktree at an intermediate state, restore the final one with
#   git restore --source=$(grep '^S6 ' ../trees.txt | cut -d' ' -f2) --worktree -- .
# (the tested files only differ from it in the series' files; untracked build files aren't touched)
[[ $(wtree) == $FINAL ]] || { echo "working tree is not the final state"; exit 1; }
trap restore EXIT; trap "exit 143" TERM INT HUP   # a kill restores the final state as well
T=$B/qtmm-build/tests/auto
t() { # t <binary name> <backend> [functions...]: run, print the totals and failures
  local bin=$(find $T -name $1 -type f -perm +111 | grep -v "\.app/" | head -1); local name=$1 be=$2; shift 2
  (cd ${bin:h} && QT_MEDIA_BACKEND=$be timeout 1200 $bin "$@" > $OUT/$S-$name-$be.log 2>&1)
  echo "  $name [$be] $*: $(grep -h Totals $OUT/$S-$name-$be.log | cut -c9-70)"; grep -h "^FAIL" $OUT/$S-$name-$be.log | cut -c1-160 | head -5; }
for S in "$@"; do
  materialize ${TREE[$S]}
  [[ $(wtree) == ${TREE[$S]} ]] || { echo "$S: could not materialize"; exit 1; }
  echo "$S (${TREE[$S]:0:12}): $(git diff-tree -r --name-only 635067497 ${TREE[$S]} | wc -l | tr -d ' ') files differ from upstream"
  cmake $B/qtmm-build > $OUT/$S-configure.log 2>&1 || { echo "  configure failed"; exit 1; }   # CMakeLists may differ
  EXTRA=(); git cat-file -e "${TREE[$S]}:tests/auto/unit/multimedia/qvideowindow/tst_qvideowindow.cpp" 2>/dev/null && EXTRA=(tst_qvideowindow)
  cmake --build $B/qtmm-build --parallel --target Multimedia MultimediaQuick MultimediaWidgets QDarwinMediaPlugin QFFmpegMediaPlugin tst_qvideoframebackend tst_qvideowidget tst_qmediaplayerbackend tst_qmultimediautils $EXTRA > $OUT/$S-build.log 2>&1
  rc=$?; echo "  build rc=$rc, warnings in changed files: $(grep -E 'warning:' $OUT/$S-build.log | grep -E -c 'avfdisplaylink|avfvideo|qvideowindow|qvideosink|qffmpegvideorenderer|qquickvideooutput|qplatformvideosink|qmultimediautils|qavfhelpers|qvideowidget|tst_qvideo|tst_qmultimediautils')"
  (( rc == 0 )) || { grep -m5 "error:" $OUT/$S-build.log; exit 1; }
  $HERE/leak.sh $S | sed 's/^/  leak probe /'
  t tst_qvideoframebackend darwin; t tst_qvideoframebackend ffmpeg
  [[ $S == S5 ]] && { t tst_qvideowidget mock; t tst_qmultimediautils mock; t tst_qvideowindow mock; }
  t tst_qmediaplayerbackend darwin destruction_doesNotDeadlock_afterMediaPlayerCall
done
