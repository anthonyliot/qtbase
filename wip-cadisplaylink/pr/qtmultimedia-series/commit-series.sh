#!/bin/zsh
# commit-series.sh: create the qtmultimedia series on 635067497, one signed commit at a time.
# Each commit is staged in the index from its tested tree (trees.txt, next to this script), so the
# working tree stays at the final state throughout. Checks each tree before and after committing,
# and stops at the first failure. Resumable: commits already made (same subject and tree) are kept.
HERE=${0:A:h}
cd ${QTMM_REPO:-${QT5_REPO:-/Users/anthony.liot/Desktop/bitbucket/qt5}/qtmultimedia} || exit 1
source $HERE/sign.sh
BASE=635067497
MSGS=($HERE/M1.txt $HERE/M2.txt $HERE/M3.txt $HERE/M4.txt $HERE/M5.txt $HERE/M6.txt)
TREES=(${(f)"$(cut -d' ' -f2 $HERE/trees.txt)"})
(( ${#TREES} == 6 )) || { echo "need 6 trees"; exit 1; }
for t in $TREES; do git cat-file -e "$t^{tree}" 2>/dev/null || { echo "tree $t is missing (see refs/cadisplaylink/series)"; exit 1; }; done
TI=${TMPDIR:-/tmp}/qtmm-series-check.$$.idx; rm -f $TI
wt=$(GIT_INDEX_FILE=$TI git read-tree HEAD && GIT_INDEX_FILE=$TI git add -A -- . && GIT_INDEX_FILE=$TI git write-tree); rm -f $TI
[[ $wt == ${TREES[6]} ]] || { echo "working tree $wt is not the final state ${TREES[6]}"; exit 1; }

# How many series commits are already on the branch?
done=0
for c in $(git rev-list --reverse --first-parent $BASE..HEAD 2>/dev/null); do
  i=$((done + 1))
  (( i <= 6 )) && [[ $(git rev-parse $c^{tree}) == ${TREES[$i]} && $(git log -1 --format=%s $c) == $(head -1 ${MSGS[$i]}) ]] || break
  done=$i
done
start=$(git rev-list --reverse --first-parent $BASE..HEAD | sed -n "${done}p"); [[ -z $start ]] && start=$BASE
echo "already committed: $done; continuing from $(git log -1 --format='%h %s' $start)"
git reset -q $start || exit 1

for (( i = done + 1; i <= 6; ++i )); do   # not seq: BSD seq counts down from 7 to 6
  git read-tree ${TREES[$i]} || exit 1            # stage exactly the tested state
  [[ $(git write-tree) == ${TREES[$i]} ]] || { echo "STOPPED: could not stage state $i"; exit 1; }
  commit_signed ${MSGS[$i]} || { git read-tree HEAD; exit 1; }
  [[ $(git rev-parse HEAD^{tree}) == ${TREES[$i]} ]] || { echo "STOPPED: commit $i has another tree"; exit 1; }
done
git log --format='%h %G? %s' $BASE..HEAD | cat
git status --short | grep -q . && echo "WARNING: working tree differs from HEAD" || echo "SERIES DONE, final tree == tested tree, working tree clean"
