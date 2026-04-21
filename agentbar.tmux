#!/bin/sh
set -eu

# Resolve the plugin root the same way TPM plugins commonly do so the plugin
# works no matter how tmux sources this file.
CURRENT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

tmux set-option -gq @agentbar_nerd_fonts off
tmux set-option -gq @agentbar_key B
tmux set-option -gq @agentbar_width 32

tmux set-option -ga update-environment 'AGENTBAR'
tmux set-option -ga update-environment 'AGENTBAR_WINDOW_ID'
tmux set-option -ga update-environment 'AGENTBAR_PANE_ID'

tmux set-environment -g AGENTBAR 1
tmux set-environment -g AGENTBAR_PLUGIN_DIR "$CURRENT_DIR"
tmux set-environment -g PATH "$CURRENT_DIR/bin:$PATH"

key=$(tmux show-option -gvq @agentbar_key)
[ -n "$key" ] || key=B
tmux bind-key "$key" run-shell "$CURRENT_DIR/bin/agentbar-toggle"

notify_renderer='pid=$(tmux show-option -gvq -t "#{session_name}" @ab_sidebar_pid); [ -n "$pid" ] && kill -USR1 "$pid" 2>/dev/null || true'

# Keep discovery env vars fresh and clear unread state when the user returns to
# a window. The hook also nudges the renderer so the unread marker disappears
# immediately instead of waiting for the next poll tick.
tmux set-hook -g pane-focus-in "run-shell 'tmux set-option -wq -t \"#{window_id}\" @ab_unread \"\" >/dev/null 2>&1 || true; tmux set-environment -t \"#{session_name}\" AGENTBAR_WINDOW_ID \"#{window_id}\"; tmux set-environment -t \"#{session_name}\" AGENTBAR_PANE_ID \"#{pane_id}\"; $notify_renderer'"
tmux set-hook -g window-renamed "run-shell '$notify_renderer'"
tmux set-hook -g client-session-changed "run-shell '$notify_renderer'"
tmux set-hook -g after-resize-pane "run-shell 'sidebar=$(tmux show-option -gvq -t \"#{session_name}\" @ab_sidebar_pane_id); [ -n \"$sidebar\" ] && [ \"$sidebar\" = \"#{pane_id}\" ] && tmux set-option -q -t \"#{session_name}\" @ab_width \"#{pane_width}\" >/dev/null 2>&1 || true'"
