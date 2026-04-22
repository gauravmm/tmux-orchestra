#!/bin/sh
# Manual test: 6 windows showing a mix of spinners, states, and unread flags
# simultaneously. Open the sidebar before running, then watch it update.
# Total runtime: ~60s (12 steps × 5s).
#
# Windows created:
#   claude     — cycling: reading → writing → waiting for approval → applying
#   opencode   — cycling: read_file → write_file → bash
#   ask        — alternating: waiting ↔ running
#   done       — static: done, no unread
#   notified   — static: done + unread notification
#   run+notice — static: running (claude) + unread notification

set -eu

REPO_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
ORCHESTRA="$REPO_DIR/bin/orchestra"

WINDOWS=''

new_win() {
    id=$(tmux new-window -dP -F '#{window_id}' -n "$1")
    WINDOWS="$WINDOWS $id"
    printf '%s' "$id"
}

cleanup() {
    printf '\nCleaning up windows...\n'
    for w in $WINDOWS; do
        tmux kill-window -t "$w" 2>/dev/null || true
    done
}
trap cleanup EXIT INT TERM

printf 'Creating 6 windows...\n'
w_claude=$(new_win 'claude')
w_ocode=$(new_win 'opencode')
w_ask=$(new_win 'ask')
w_done=$(new_win 'done')
w_notif=$(new_win 'notified')
w_runrd=$(new_win 'run+notice')

# Static windows — set once and leave alone.
"$ORCHESTRA" set-state done --window "$w_done"
"$ORCHESTRA" set-state done --window "$w_notif"
"$ORCHESTRA" notify --title "Claude" --body "Build finished with 2 warnings" --window "$w_notif"
"$ORCHESTRA" set-state running --spinner claude --action "Running test suite" --window "$w_runrd"
"$ORCHESTRA" notify --title "Claude" --body "Awaiting your review" --window "$w_runrd"

printf 'Running for ~60s. Watch the sidebar.\n\n'

STEPS=12
i=0
while [ "$i" -lt "$STEPS" ]; do
    # claude: reading → writing → waiting for approval → applying
    case $((i % 4)) in
        0) "$ORCHESTRA" set-state running --spinner claude --action "Reading codebase"   --window "$w_claude" ;;
        1) "$ORCHESTRA" set-state running --spinner claude --action "Writing changes"     --window "$w_claude" ;;
        2) "$ORCHESTRA" set-state waiting --action "Allow edit to config.py?"             --window "$w_claude" ;;
        3) "$ORCHESTRA" set-state running --spinner claude --action "Applying patch"      --window "$w_claude" ;;
    esac

    # opencode: cycling tool calls
    case $((i % 3)) in
        0) "$ORCHESTRA" set-state running --spinner opencode --action "read_file"  --window "$w_ocode" ;;
        1) "$ORCHESTRA" set-state running --spinner opencode --action "write_file" --window "$w_ocode" ;;
        2) "$ORCHESTRA" set-state running --spinner opencode --action "bash"       --window "$w_ocode" ;;
    esac

    # ask: alternates waiting ↔ running
    if [ $((i % 2)) -eq 0 ]; then
        "$ORCHESTRA" set-state waiting --action "Allow network request?"          --window "$w_ask"
    else
        "$ORCHESTRA" set-state running --spinner opencode --action "Continuing"   --window "$w_ask"
    fi

    i=$((i + 1))
    printf '[%d/%d] sleeping 5s...\n' "$i" "$STEPS"
    sleep 5
done
