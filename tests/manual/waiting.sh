#!/bin/sh
# Manual test: cycle between running and waiting to verify border color changes.
# Expected sidebar sequence (repeating):
#   running → waiting → running → waiting → ... → done → cleared

# Linux-only trick: create a symlink named "test-harness" pointing to bash.
# The kernel sets /proc/<pid>/comm from the executable basename, so tmux
# shows "test-harness" instead of "bash".
if [ "$(ps -p $$ -o comm= 2>/dev/null || echo '')" != "test-harness" ]; then
	ln -sf "$(command -v bash)" /tmp/test-harness
	exec /tmp/test-harness "$0" "$@"
fi

set -eu

REPO_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
ORCHESTRA="$REPO_DIR/bin/orchestra"

CYCLES=${1:-5}

echo "Cycling running/waiting ${CYCLES} times. Watch the border color change."

i=1
while [ "$i" -le "$CYCLES" ]; do
	echo "[cycle $i/$CYCLES] running..."
	"$ORCHESTRA" set-state running --spinner claude --action "Doing work (cycle $i)"
	sleep 2

	echo "[cycle $i/$CYCLES] waiting..."
	"$ORCHESTRA" set-state waiting --action "Allow action? (cycle $i)"
	sleep 2

	i=$((i + 1))
done

echo "Done. Clearing state."
"$ORCHESTRA" set-state done
sleep 1
"$ORCHESTRA" clear-state

echo "Check that the border turned amber on each 'waiting' step and back to normal on 'running'."
