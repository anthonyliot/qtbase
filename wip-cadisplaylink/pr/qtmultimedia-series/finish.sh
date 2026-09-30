#!/bin/zsh
# finish.sh: run with the user at the machine (AppleConnect prompts), after the reviewer approves.
# 1. qtmultimedia series  2. qtbase PR documents  3. pushes to the forks  4. qt5 submodule pointers
# Stops at the first failure; every step can be rerun (already done steps are detected).
HERE=${0:A:h}
Q=${QT5_REPO:-/Users/anthony.liot/Desktop/bitbucket/qt5}
for f in $HERE/{sign.sh,commit-series.sh,trees.txt,M{1..6}.txt,qtbase-docs.txt,qt5-pointers.txt}; do
  [[ -s $f ]] || { echo "MISSING: $f"; exit 1; }
done
source $HERE/sign.sh
$HERE/commit-series.sh || exit 1

cd $Q/qtbase || exit 1
if git status --porcelain -- wip-cadisplaylink | grep -q .; then
  git add -- wip-cadisplaylink && commit_signed $HERE/qtbase-docs.txt || exit 1
fi

# A re-committed series replaces the fork's branch. --force-with-lease without a value expects the
# fork's branch where our last push left it (refs/remotes/fork/...), so it doesn't go stale from
# round to round, and still refuses a branch someone else moved.
fork_head=$(git -C $Q/qtmultimedia ls-remote fork refs/heads/wip/cadisplaylink | cut -f1)
if [[ $fork_head != $(git -C $Q/qtmultimedia rev-parse wip/cadisplaylink) ]]; then
  git -C $Q/qtmultimedia push --force-with-lease=wip/cadisplaylink fork wip/cadisplaylink || exit 1
fi
# qtmultimedia's Gerrit branch is its series too (worktree qt5-series/qtmultimedia, like qtbase's
# and qtdeclarative's): move it to the commits just pushed, and push it
QS=${QT5_SERIES:-${Q:h}/qt5-series}/qtmultimedia
head=$(git -C $Q/qtmultimedia rev-parse wip/cadisplaylink)
if [[ -d $QS && $(git -C $QS rev-parse HEAD) != $head ]]; then
  git -C $QS reset -q --keep $head || exit 1
  git -C $QS push --force-with-lease=wip/cadisplaylink-gerrit fork wip/cadisplaylink-gerrit \
      || exit 1
fi
git -C $Q/qtbase push fork wip/cadisplaylink || exit 1

cd $Q || exit 1
git add qtbase qtmultimedia
if ! git diff --cached --quiet; then commit_signed $HERE/qt5-pointers.txt || exit 1; fi
git push fork wip/cadisplaylink || exit 1
echo "ALL DONE: $(git log -1 --format='%h %G? %s')"
git ls-tree HEAD qtbase qtdeclarative qtmultimedia | awk '{print "  "$4, $3}'
