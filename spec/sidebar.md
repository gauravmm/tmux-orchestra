# Sidebar: Toggle & TPM Entrypoint
## tmux-orchestra v0.1.0

*Part of the [implementation spec](implementation-spec.md). See [core.md](core.md) for session-scoped options (`@ab_sidebar_pane_id`, `@ab_sidebar_pid`, `@ab_width`).*

## Sidebar toggle (`bin/orchestra-toggle`)

Behavior:

1. Read session option `@ab_sidebar_pane_id`.
2. If set and pane still exists → `tmux kill-pane -t "$pid"`, unset option, return.
3. Else: read cached width from `@ab_width` (default 32). `tmux split-window -bhd -l "$width" -t "$current_window" -c "$PWD" orchestra-render`. Capture new pane id into `@ab_sidebar_pane_id`.

## Window-following (`bin/orchestra-follow`)

The sidebar pane is not fixed to a single window. On every `pane-focus-in`, `orchestra-follow` checks whether the focused window already contains the sidebar pane. If not, it runs:

```
tmux move-pane -hb -l <width> -s <sidebar_pane> -t <active_pane_in_current_window>
```

This transplants the pane (and its running `orchestra-render` process) into the new window's layout on the left edge. Because the same process moves with the pane, there is no restart flicker.

**Window-closing edge case.** If the source window contained only the sidebar pane, `move-pane` leaves it empty and tmux closes that window. This is acceptable behaviour — the user was already leaving that window by switching focus elsewhere.

## `orchestra.tmux` (TPM entrypoint)

Must:

- Set default options (`focus-events on`, `@orchestra_nerd_fonts off`, `@orchestra_key B`, `@orchestra_width 32`). `focus-events` is required for `pane-focus-in` to fire on window/pane switches.
- Bind `prefix + <key>` (from option) to `run-shell "$CURRENT_DIR/bin/orchestra-toggle"`.
- Register `pane-focus-in` hook: clear `@ab_unread`, write `ORCHESTRA_WINDOW_ID` / `ORCHESTRA_PANE_ID`, and run `orchestra-follow` to move the sidebar pane to the current window if needed.
- Register `window-renamed`, `client-session-changed` hooks: `kill -USR1` the renderer process (look up PID from `@ab_sidebar_pid` session option).
- Prepend `$CURRENT_DIR/bin` to `PATH` in the session env so `orchestra` is callable from any pane.

Follow the TPM convention for `$CURRENT_DIR` resolution (copy from `tmux-sidebar`'s `sidebar.tmux`).
