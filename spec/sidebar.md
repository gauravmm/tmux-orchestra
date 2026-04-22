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

- Set default options (`focus-events on`, `mouse on`, `@orchestra_nerd_fonts off`, `@orchestra_wait_color '#d29922'`, `@orchestra_key B`, `@orchestra_width 32`). `focus-events` is required for `pane-focus-in` to fire on window/pane switches. `mouse on` is required for the sidebar click binding below.
- Bind `prefix + <key>` (from option) to `run-shell "$CURRENT_DIR/bin/orchestra-toggle"`.
- Register `pane-focus-in` hook: clear `@ab_unread`, write `ORCHESTRA_WINDOW_ID` / `ORCHESTRA_PANE_ID`, `kill -USR1` the renderer, and run `orchestra-follow` to move the sidebar pane to the current window if needed.
- Register `window-renamed`, `client-session-changed` hooks: `kill -USR1` the renderer process (look up PID from `@ab_sidebar_pid` session option).
- Register `after-resize-pane` hook: if the resized pane is the sidebar (`pane_id == @ab_sidebar_pane_id`), persist the new width into the session-scoped `@ab_width` option so the next `orchestra-toggle` restores the user-resized width.
- Bind `MouseDown1Pane` globally (see **Mouse bindings** below).
- Prepend `$CURRENT_DIR/bin` to `PATH` in the session env so `orchestra` is callable from any pane.

Follow the TPM convention for `$CURRENT_DIR` resolution (copy from `tmux-sidebar`'s `sidebar.tmux`).

## Mouse bindings

The sidebar is click-navigable: clicking on a window block in the sidebar selects that window. Non-sidebar clicks fall through to tmux's default `select-pane` + `send-keys -M` behaviour (so mouse support in application panes is unchanged).

Implementation:

```tmux
bind-key -n MouseDown1Pane \
    if-shell -F -t = '#{==:#{pane_id},#{@ab_sidebar_pane_id}}' \
        "run-shell '$CURRENT_DIR/bin/orchestra-click #{mouse_y} #{session_name}'" \
        'select-pane -t=; send-keys -M'
```

`bin/orchestra-click` maps a Y coordinate to a window block and runs `tmux select-window`. Each window block rendered by `render_window_block` is exactly 3 lines tall (top border, detail row, meta row), so `block_index = mouse_y / 3`. The script picks the Nth window returned by `tmux list-windows -t <session>` — so the click-to-window mapping is tied to the renderer's row height. If `render_window_block` ever changes its line count, update [bin/orchestra-click](../bin/orchestra-click) to match.
