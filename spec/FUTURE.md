# FUTURE

Features planned

## Near

- Pane-border unread indicator — red dot in the pane border when @ab_unread is set

## Far

- styling
- orchestra dump / restore — persist state across tmux server restarts
- Fish / PowerShell prompt hooks
- Compact status-line mode (@ab_render_in_statusline) for users who don't want a sidebar

## Done (moved out of FUTURE)

- Per-provider throbbers (claude, braille, opencode) — implemented via `@ab_spinner` and `orchestra set-state --spinner <name>`.
- Progress bar rendering — `render_progress` in [lib/render.sh](../lib/render.sh) draws `@ab_progress` + `@ab_progress_label` in the meta row.
