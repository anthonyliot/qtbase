# commit_signed <msgfile>: commit the index, signed via AppleConnect (ac-sign), giving the prompt
# SIGN_TIMEOUT seconds (default 600). Never bypasses signing. Returns 1 if blocked or unsigned.
commit_signed() {
  local log=${TMPDIR:-/tmp}/qtmm-series-commit.log
  git commit -q -F $1 > $log 2>&1 &
  local P=$! s a
  for s in $(seq 1 ${SIGN_TIMEOUT:-600}); do kill -0 $P 2>/dev/null || break; sleep 1; done
  if kill -0 $P 2>/dev/null; then
    for a in $(pgrep -f "ac-sign --status-fd"); do pgrep -P $P | grep -qx $a && kill $a; done
    kill $P; wait $P 2>/dev/null; echo "STOPPED: signing blocked for: $(head -1 $1)"; return 1
  fi
  wait $P || { echo "STOPPED: commit failed: $(head -1 $1)"; head -5 $log; return 1; }
  [[ $(git log -1 --format='%G?') == [GU] ]] || { echo "STOPPED: not signed: $(head -1 $1)"; return 1; }
  grep -E "Suspicious" -A4 $log | head -5
  echo "committed $(git log -1 --format='%h %G? %s')"
}
