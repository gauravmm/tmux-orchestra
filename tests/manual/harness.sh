#!/bin/sh
# Manual test: simulate a full LLM turn with tool use and permission prompt.
# Expected sidebar sequence:
#   1. LLM writing          → running (spinner)
#   2. Tool starts          → running + tool name
#   3. Tool finishes        → running (spinner, no action)
#   4. Permission prompt    → waiting + permission title
#   5. LLM continues        → running (spinner)
#   6. Turn complete        → done → cleared

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

echo "[1/6] LLM is writing a response..."
"$ORCHESTRA" set-state running --spinner braille
sleep 2

echo "[2/6] LLM calls a tool..."
"$ORCHESTRA" set-state running --spinner braille --action "read_file"
sleep 2

echo "[3/6] Tool finished, LLM still processing..."
"$ORCHESTRA" set-state running --spinner braille
sleep 2

echo "[4/6] LLM asks for permission..."
"$ORCHESTRA" set-state waiting --action "Allow file edit?"
sleep 2

echo "[5/6] LLM continues writing after approval..."
"$ORCHESTRA" set-state running --spinner braille
sleep 2

echo "[6/6] Turn complete."
"$ORCHESTRA" set-state done
sleep 1
"$ORCHESTRA" clear-state

echo "Done. Check the sidebar showed: writing → tool → spinner → waiting → writing → done → clear."
