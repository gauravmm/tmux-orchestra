# Renderer: `bin/orchestra-render` + `lib/render.sh`
## tmux-orchestra v0.1.0

*Part of the [implementation spec](implementation-spec.md). Glyph tables and color defaults are in [core.md](core.md).*

## Loop

```
while true; do
    redraw
    # Wait up to 500 ms, but wake on SIGUSR1 (from set-hooks)
    sleep_interruptible 0.5
done
```

`sleep_interruptible`: trap SIGUSR1 to a no-op and run `sleep 0.5 &; wait $!` — the signal cancels the wait.

## Data read (one tmux call per tick)

```sh
tmux list-windows -a -F '#{session_name}|#{window_id}|#{window_name}|#{window_active}|#{@ab_agent_state}|#{@ab_current_action}|#{@ab_branch}|#{@ab_cwd}|#{@ab_last_cmd}|#{@ab_progress}|#{@ab_progress_label}|#{@ab_unread}|#{@ab_last_notification}|#{@ab_status_phase}|#{@ab_status_phase__icon}|#{@ab_status_phase__color}'
```

For v0.1 only one status pill is rendered — `phase`. Iterating over arbitrary `@ab_status_*` keys requires a second tmux call per window and is deferred to v0.2.

## Per-window row format

```
┌─ <window_name> ────────────────
│ <state_glyph> <activity_line>
│ <phase_pill>  <progress_bar>  <unread_dot>
└─
```

Where:

- `activity_line = @ab_current_action` if state ∈ {running, waiting}; else `"$ @ab_last_cmd"` if set; else `@ab_cwd`.
- `state_glyph` rotates through a 4-frame animation per tick for running (`⠋⠙⠹⠸`), waiting (`◐◓◑◒`), done (`✓` static), none (empty).
- `phase_pill` = `<icon> <text>` painted with `@ab_status_phase__color`. Nerd-font icon if terminal supports it (detect via `$TERM` containing `nerd`? — no, just honor user's `@orchestra_nerd_fonts` option, default off).
- `progress_bar` = `█████░░░░░ 42%` when `@ab_progress` set. Width: 10 cells.
- `unread_dot` = red `●` when `@ab_unread == 1`, else empty.

**Active window** gets heavy box-drawing borders and bold title text. Waiting state applies the `@orchestra_wait_color` color to borders and text.

## Flicker-free redraw

Do not use `\033[2J` (erase-screen) before drawing. Instead: move cursor to home (`\033[H`), overwrite the previous frame in place, then emit `\033[J` (erase from cursor to end of screen) to clear any leftover lines if content shrank. This ensures no blank frame is ever displayed between redraws.

## Constraints

- `lib/render.sh` must be pure — no tmux calls inside `render_rows` or any function it calls. All tmux I/O happens in the `redraw` function in `bin/orchestra-render` before rendering begins.
- **No mouse support in v0.1** (deferred to v0.3). No horizontal scrolling. If a window has a very long `@ab_current_action`, truncate to pane-width minus 4 with trailing `…`.
- **Color output:** use `tput setaf` via a small wrapper in `lib/render.sh`. On `TERM=dumb` or when `NO_COLOR` is set, drop all ANSI.
