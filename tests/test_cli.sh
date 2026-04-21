#!/bin/sh
set -eu

REPO_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/agentbar-cli.XXXXXX")
SOCKET=agentbar-test

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

tmux -f /dev/null new-session -d -s agentbar-tests
window_id=$(tmux display-message -p -t agentbar-tests '#{window_id}')

assert_eq() {
    expected=$1
    actual=$2
    message=$3
    if [ "$expected" != "$actual" ]; then
        printf 'assertion failed: %s\nexpected: %s\nactual:   %s\n' "$message" "$expected" "$actual" >&2
        exit 1
    fi
}

agentbar set-status phase build --icon '*' --color cyan --window "$window_id"
assert_eq 'build' "$(tmux show-options -v -w -t "$window_id" @ab_status_phase)" 'status text is written'
assert_eq '*' "$(tmux show-options -v -w -t "$window_id" @ab_status_phase__icon)" 'status icon is written'
assert_eq 'cyan' "$(tmux show-options -v -w -t "$window_id" @ab_status_phase__color)" 'status color is written'

list_output=$(agentbar list-status --window "$window_id")
assert_eq 'phase	build' "$list_output" 'status list reports written key'

agentbar clear-status phase --window "$window_id"
assert_eq '' "$(tmux show-options -v -w -t "$window_id" @ab_status_phase 2>/dev/null || printf '')" 'status text is cleared'

agentbar set-progress 0.42 --label 'Compile' --window "$window_id"
assert_eq '0.42' "$(tmux show-options -v -w -t "$window_id" @ab_progress)" 'progress is written'
assert_eq 'Compile' "$(tmux show-options -v -w -t "$window_id" @ab_progress_label)" 'progress label is written'
agentbar clear-progress --window "$window_id"
assert_eq '' "$(tmux show-options -v -w -t "$window_id" @ab_progress 2>/dev/null || printf '')" 'progress is cleared'

cat >"$TMP_DIR/notifier" <<'EOF'
#!/bin/sh
printf '%s|%s|%s\n' "$1" "$2" "$3" >"__OUTPUT__"
EOF
sed "s#__OUTPUT__#$TMP_DIR/notifier.out#g" "$TMP_DIR/notifier" >"$TMP_DIR/notifier.real"
mv "$TMP_DIR/notifier.real" "$TMP_DIR/notifier"
chmod +x "$TMP_DIR/notifier"
AGENTBAR_NOTIFIER="$TMP_DIR/notifier" agentbar notify --title 'Build' --body 'done' --subtitle 'CI' --window "$window_id"
assert_eq '1' "$(tmux show-options -v -w -t "$window_id" @ab_unread)" 'notify marks unread'
assert_eq 'Build — CI: done' "$(tmux show-options -v -w -t "$window_id" @ab_last_notification)" 'notify stores summary'
assert_eq 'Build|done|CI' "$(cat "$TMP_DIR/notifier.out")" 'notify calls notifier shim'

agentbar set-state running --action 'pytest' --window "$window_id"
assert_eq 'running' "$(tmux show-options -v -w -t "$window_id" @ab_agent_state)" 'state is written'
assert_eq 'pytest' "$(tmux show-options -v -w -t "$window_id" @ab_current_action)" 'action is written'
agentbar set-state 'done' --window "$window_id"
assert_eq 'done' "$(tmux show-options -v -w -t "$window_id" @ab_agent_state)" 'done state is written'
assert_eq '' "$(tmux show-options -v -w -t "$window_id" @ab_current_action 2>/dev/null || printf '')" 'done clears action'
agentbar clear-state --window "$window_id"
assert_eq '' "$(tmux show-options -v -w -t "$window_id" @ab_agent_state 2>/dev/null || printf '')" 'clear-state clears agent state'
