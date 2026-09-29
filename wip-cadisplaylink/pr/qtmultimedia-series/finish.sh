#!/bin/zsh
# finish.sh: run with the user at the machine (AppleConnect prompts), after the reviewer approves.
# 1. qtmultimedia series  2. qtbase PR documents  3. pushes to the forks  4. qt5 submodule pointers
# Stops at the first failure; every step can be rerun (already done steps are detected).
HERE=${0:A:h}
Q=${QT5_REPO:-/Users/anthony.liot/Desktop/bitbucket/qt5}
for f in $HERE/{sign.sh,commit-series.sh,trees.txt,M1.txt,M2.txt,M3.txt,M4.txt,M5.txt,M6.txt,qtbase-docs.txt,qt5-pointers.txt}; do
  [[ -s $f ]] || { echo "MISSING: $f"; exit 1; }
done
source $HERE/sign.sh
$HERE/commit-series.sh || exit 1

cd $Q/qtbase || exit 1
if git status --porcelain -- wip-cadisplaylink | grep -q .; then
  git add -- wip-cadisplaylink && commit_signed $HERE/qtbase-docs.txt || exit 1
fi

# The fork's branch is the old, pre-review history (89c28908b); replace it only if it's still that.
if [[ $(git -C $Q/qtmultimedia ls-remote fork refs/heads/wip/cadisplaylink | cut -f1) != $(git -C $Q/qtmultimedia rev-parse wip/cadisplaylink) ]]; then
  git -C $Q/qtmultimedia push --force-with-lease=wip/cadisplaylink:89c28908b78c3e1c74f2b3846b712939cfeb7a69 fork wip/cadisplaylink || exit 1
fi
git -C $Q/qtbase push fork wip/cadisplaylink || exit 1

cd $Q || exit 1
git add qtbase qtmultimedia
if ! git diff --cached --quiet; then commit_signed $HERE/qt5-pointers.txt || exit 1; fi
git push fork wip/cadisplaylink || exit 1
echo "ALL DONE: $(git log -1 --format='%h %G? %s')"; git ls-tree HEAD qtbase qtdeclarative qtmultimedia | awk '{print "  "$4, $3}'
