#!/bin/sh
# Manual test: simulate a full LLM turn with tool use.
# Expected sidebar sequence:
#   1. LLM writing          → running + action text
#   2. Tool starts          → running + tool name
#   3. Tool finishes        → running (spinner, no action)
#   4. LLM still writing    → running + action text
#   5. Turn complete        → done → cleared

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

echo "[1/5] LLM is writing a response..."
"$ORCHESTRA" set-state running
sleep 2

echo "[2/5] LLM calls a tool..."
"$ORCHESTRA" set-state running --action "read_file"
sleep 2

echo "[3/5] Tool finished, LLM still processing..."
"$ORCHESTRA" set-state running
sleep 2

echo "[4/5] LLM continues writing..."
"$ORCHESTRA" set-state running
sleep 2

echo "[5/5] Turn complete."
"$ORCHESTRA" set-state done
sleep 1
"$ORCHESTRA" clear-state

echo "Done. Check the sidebar showed: writing → tool → spinner → writing → done → clear."
