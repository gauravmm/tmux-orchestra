# Quality: Testing, Scope & Definition of Done
## tmux-orchestra v0.1.0

*Part of the [implementation spec](implementation-spec.md).*

## Testing

- **`tests/test_cli.sh`**: start a detached tmux server (`tmux -L orchestra-test`), run `orchestra set-status phase build`, assert `tmux show-options -v -w @ab_status_phase` returns `build`. Cover every CLI subcommand.
- **`tests/test_render.sh`**: feed `lib/render.sh` fixture option dumps and diff output against `tests/fixtures/*.expected` text files. Pure function, no tmux needed.
- **`shellcheck`** on every `bin/*` and `lib/*`.
- **`make test`** runs all three. Keep runtime under 10 s.

CI: GitHub Actions matrix — Ubuntu (tmux 3.2a and 3.4), macOS (Homebrew tmux).

## Out of scope for v0.1 — do not implement

Explicit list to prevent scope creep; each is parked in planning-spec.md §8 v0.2/v0.3.

- Progress-bar CLI rendering (the option is written, the renderer draws the bar, but no `SKILL.md` / agent guidance yet).
- `set-hook`-driven instant redraws (poll-only is fine).
- Pane-border-style unread indicator.
- `@ab_render_in_statusline` compact mode.
- `display-popup` summary view.
- Pane-scoped status keys.
- Mouse click → `select-window`.
- Fish / PowerShell prompt hooks.
- `orchestra dump` / `restore`.
- Cursor / Aider templates.

## Definition of done

- `git clone` into `~/.tmux/plugins/tmux-orchestra`, add `set -g @plugin 'gauravmm/tmux-orchestra'` (or equivalent path) to `.tmux.conf`, `prefix + I` (TPM install), `prefix + B` opens a sidebar pane.
- In a second pane, `orchestra set-status phase build --icon '*' --color cyan` — the sidebar row for that window shows a cyan `* build` pill within 500 ms.
- `orchestra set-state running --action "Bash: pytest"` — sidebar shows spinning glyph + action text.
- `orchestra notify --title "Build" --body "done"` — desktop toast fires, pane border marked unread, focus-in clears it.
- Source `hooks/prompt.bash` in a fresh shell, `cd /tmp && ls` — sidebar row updates to `cwd=/tmp  $ ls`.
- Install the Claude Code hook snippet, run a Claude Code session — sidebar shows `running` during tool use, `waiting` at user prompts, `done` after Stop.
- `shellcheck` clean, tests green on Linux and macOS.
