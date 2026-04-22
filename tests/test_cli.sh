#!/bin/sh
set -eu

REPO_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/orchestra-cli.XXXXXX")
SOCKET=orchestra-test

cleanup() {
    PATH=$ORIGINAL_PATH tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

ORIGINAL_PATH=$PATH
cat >"$TMP_DIR/tmux" <<EOF
#!/bin/sh
exec $(command -v tmux) -L "$SOCKET" "\$@"
EOF
chmod +x "$TMP_DIR/tmux"
PATH=$TMP_DIR:$REPO_DIR/bin:$PATH

tmux -f /dev/null new-session -d -s orchestra-tests
window_id=$(tmux display-message -p -t orchestra-tests '#{window_id}')

assert_eq() {
    expected=$1
    actual=$2
    message=$3
    if [ "$expected" != "$actual" ]; then
        printf 'assertion failed: %s\nexpected: %s\nactual:   %s\n' "$message" "$expected" "$actual" >&2
        exit 1
    fi
}

"$REPO_DIR/orchestra.tmux"
mouse_binding=$(tmux list-keys -T root MouseDown1Pane)
case "$mouse_binding" in
    *"if-shell -F -t ="*"orchestra-click #{mouse_y} #{session_name}"*)
        :
        ;;
    *)
        printf 'assertion failed: MouseDown1Pane targets the pane under the mouse\nactual:   %s\n' "$mouse_binding" >&2
        exit 1
        ;;
esac

orchestra set-status phase build --icon '*' --color cyan --window "$window_id"
assert_eq 'build' "$(tmux show-options -v -w -t "$window_id" @ab_status_phase)" 'status text is written'
assert_eq '*' "$(tmux show-options -v -w -t "$window_id" @ab_status_phase__icon)" 'status icon is written'
assert_eq 'cyan' "$(tmux show-options -v -w -t "$window_id" @ab_status_phase__color)" 'status color is written'

list_output=$(orchestra list-status --window "$window_id")
assert_eq 'phase	build' "$list_output" 'status list reports written key'

orchestra clear-status phase --window "$window_id"
assert_eq '' "$(tmux show-options -v -w -t "$window_id" @ab_status_phase 2>/dev/null || printf '')" 'status text is cleared'

orchestra set-progress 0.42 --label 'Compile' --window "$window_id"
assert_eq '0.42' "$(tmux show-options -v -w -t "$window_id" @ab_progress)" 'progress is written'
assert_eq 'Compile' "$(tmux show-options -v -w -t "$window_id" @ab_progress_label)" 'progress label is written'
orchestra clear-progress --window "$window_id"
assert_eq '' "$(tmux show-options -v -w -t "$window_id" @ab_progress 2>/dev/null || printf '')" 'progress is cleared'

cat >"$TMP_DIR/notifier" <<'EOF'
#!/bin/sh
printf '%s|%s|%s\n' "$1" "$2" "$3" >"__OUTPUT__"
EOF
sed "s#__OUTPUT__#$TMP_DIR/notifier.out#g" "$TMP_DIR/notifier" >"$TMP_DIR/notifier.real"
mv "$TMP_DIR/notifier.real" "$TMP_DIR/notifier"
chmod +x "$TMP_DIR/notifier"
ORCHESTRA_NOTIFIER="$TMP_DIR/notifier" orchestra notify --title 'Build' --body 'done' --subtitle 'CI' --window "$window_id"
assert_eq '1' "$(tmux show-options -v -w -t "$window_id" @ab_unread)" 'notify marks unread'
assert_eq 'Build — CI: done' "$(tmux show-options -v -w -t "$window_id" @ab_last_notification)" 'notify stores summary'
assert_eq 'Build|done|CI' "$(cat "$TMP_DIR/notifier.out")" 'notify calls notifier shim'

orchestra set-state running --action 'pytest' --window "$window_id"
assert_eq 'running' "$(tmux show-options -v -w -t "$window_id" @ab_agent_state)" 'state is written'
assert_eq 'pytest' "$(tmux show-options -v -w -t "$window_id" @ab_current_action)" 'action is written'
orchestra set-state 'done' --window "$window_id"
assert_eq 'done' "$(tmux show-options -v -w -t "$window_id" @ab_agent_state)" 'done state is written'
assert_eq '' "$(tmux show-options -v -w -t "$window_id" @ab_current_action 2>/dev/null || printf '')" 'done clears action'
orchestra clear-state --window "$window_id"
assert_eq '' "$(tmux show-options -v -w -t "$window_id" @ab_agent_state 2>/dev/null || printf '')" 'clear-state clears agent state'

# Mouse click: orchestra-click <y> <session> selects the window at block y/4.
# Create a second window so we have two to click between.
window2_info=$(tmux new-window -t orchestra-tests -P -F '#{window_id}|#{pane_id}')
window2_id=${window2_info%%|*}
pane2_id=${window2_info#*|}
# Switch back to window 1 so it is the active window.
tmux select-window -t "$window_id"
active_before=$(tmux display-message -p -t orchestra-tests '#{window_id}')
assert_eq "$window_id" "$active_before" 'window 1 is active before click'
# Y=4 → block 1 → second window (0-indexed).
orchestra-click 4 orchestra-tests
active_after=$(tmux display-message -p -t orchestra-tests '#{window_id}')
assert_eq "$window2_id" "$active_after" 'orchestra-click selects the correct window'
# Y=0 → block 0 → first window.
orchestra-click 0 orchestra-tests
active_back=$(tmux display-message -p -t orchestra-tests '#{window_id}')
assert_eq "$window_id" "$active_back" 'orchestra-click y=0 selects first window'
# Y beyond last window → no crash, no window change.
orchestra-click 999 orchestra-tests
active_unchanged=$(tmux display-message -p -t orchestra-tests '#{window_id}')
assert_eq "$window_id" "$active_unchanged" 'orchestra-click out-of-range is a no-op'

# A stale ORCHESTRA_WINDOW_ID must not override the pane the command is
# actually running in.
TMUX_PANE="$pane2_id" ORCHESTRA_WINDOW_ID="$window_id" orchestra set-state running --action 'pane wins'
assert_eq 'running' "$(tmux show-options -v -w -t "$window2_id" @ab_agent_state)" 'TMUX_PANE resolves the target window before stale ORCHESTRA_WINDOW_ID'
assert_eq 'pane wins' "$(tmux show-options -v -w -t "$window2_id" @ab_current_action)" 'state from the pane lands on the pane window'
assert_eq '' "$(tmux show-options -v -w -t "$window_id" @ab_agent_state 2>/dev/null || printf '')" 'stale ORCHESTRA_WINDOW_ID is ignored when TMUX_PANE is present'
orchestra clear-state --window "$window2_id"

# Clean up extra window.
tmux kill-window -t "$window2_id"
