# AGENTS.md — tmux-orchestra

## Project overview

tmux-orchestra is a pure POSIX shell tmux plugin that renders a live sidebar pane showing per-window agent state (running/waiting/done), status pills, progress bars, and notifications. State flows exclusively through tmux user-options (`@ab_*`); there are no daemons, sockets, or files outside tmux itself. The renderer polls every 125 ms and wakes early on SIGUSR1.

## Repository layout

```
orchestra.tmux          TPM entrypoint — init, hooks, keybindings
bin/
  orchestra             CLI dispatcher (set-status, notify, set-state, …)
  orchestra-render      Long-lived sidebar TUI (125 ms polling loop)
  orchestra-toggle      Open/close sidebar, cache width per session
  orchestra-follow      Move sidebar pane to new window on focus switch
  orchestra-notify      Platform-detecting notifier shim
lib/
  common.sh             Option CRUD, window resolution, shared helpers
  render.sh             Pure rendering (boxes, glyphs, progress, ANSI)
  notify.sh             Platform notifier dispatch (Linux/macOS/WSL)
hooks/
  prompt.bash           Bash shell integration (cwd/branch/exit/cmd)
  prompt.zsh            Zsh shell integration
  claude-code/          Hook template for Claude Code (.claude/settings.json)
  opencode/             Hook plugin for OpenCode (orchestra.js, Bun)
  codex/                Stub — unimplemented pending Codex hook API
tests/
  test_cli.sh           Integration tests (spins up isolated tmux server)
  test_render.sh        Fixture-based render regression tests
  fixtures/             Pipe-delimited input + .expected output pairs
spec/
  implementation-spec.md  Authoritative design reference
  planning-spec.md        Design rationale and tradeoffs
  FUTURE.md               Planned v0.2+ features (do not implement now)
Makefile                `make test` (shellcheck + both test suites)
README.md               User-facing installation and quick-start guide
```

## Language and shell constraints

- **Pure POSIX sh only.** No bash-isms (`[[`, arrays, `local` outside functions, `$(< file)`, etc.). Every `.sh` file and every `bin/` script must pass `shellcheck -s sh`.
- No compiled dependencies, no build step, no runtime deps beyond tmux ≥ 3.4.
- All scripts begin with `#!/usr/bin/env sh` (or are sourced; check existing header conventions before changing).

## tmux option schema (authoritative)

All persistent state is stored as tmux user-options. Window-scoped unless noted.

| Option | Writer | Max | Notes |
|---|---|---|---|
| `@ab_agent_state` | harness hook | — | `running` \| `waiting` \| `done` \| empty |
| `@ab_current_action` | harness hook | 120 chars | Tool name or prompt text |
| `@ab_status_<key>` | `orchestra set-status` | 40 chars | Arbitrary status pill value |
| `@ab_status_<key>__icon` | `--icon` flag | 1 grapheme | Optional pill icon |
| `@ab_status_<key>__color` | `--color` flag | 32 chars | `#rrggbb` or ANSI name |
| `@ab_progress` | `orchestra set-progress` | — | Float [0, 1] |
| `@ab_progress_label` | `--label` flag | 60 chars | Progress bar label |
| `@ab_unread` | `orchestra notify` | — | `1` or empty; cleared on focus-in |
| `@ab_last_notification` | `orchestra notify` | 120 chars | `title — subtitle: body` |
| `@ab_branch` | prompt hook | — | `git symbolic-ref --short HEAD` |
| `@ab_cwd` | prompt hook | — | `$PWD` |
| `@ab_last_cmd` | prompt hook | 80 chars | Last shell command |
| `@ab_last_exit` | prompt hook | 32 chars | Last exit code |
| `@ab_width` | orchestra-toggle | 8 chars | Session-scoped: cached pane width |
| `@ab_sidebar_pane_id` | orchestra-toggle | — | Session-scoped: sidebar pane ID |
| `@ab_sidebar_pid` | orchestra-toggle | — | Session-scoped: renderer PID |

`set_opt` / `clear_opt` / `get_opt` in [lib/common.sh](lib/common.sh) are the only correct way to read/write these options. They enforce truncation and prefix namespacing. Do not call `tmux set-option` directly for `@ab_*` options.

## CLI interface (bin/orchestra)

```
orchestra set-status <key> <value> [--icon GLYPH] [--color COLOR]
orchestra clear-status <key>
orchestra list-status
orchestra set-progress <float> [--label TEXT]
orchestra clear-progress
orchestra notify --title T [--body B] [--subtitle S]
orchestra set-state <running|waiting|done> [--action TEXT]
orchestra clear-state
```

All subcommands accept `--window <id>` to target a specific window. Without it, window resolution falls through four steps (see `resolve_window` in [lib/common.sh](lib/common.sh)): explicit flag → `$ORCHESTRA_WINDOW_ID` → `$TMUX_PANE` → current window.

Exit codes: `0` success, `1` usage error, `2` not in tmux, `3` tmux call failed.

## Renderer (bin/orchestra-render and lib/render.sh)

- `orchestra-render` runs in the sidebar pane. It reads all window state in **one** tmux call per tick (`tmux list-windows -F '...'`), then calls `render_rows` (pure function in [lib/render.sh](lib/render.sh)).
- Do not add tmux calls inside `render_rows` or any function it calls — rendering must remain pure.
- The pipe-delimited format read from tmux is:
  `session_name|window_id|window_name|window_active|state|action|branch|cwd|last_cmd|progress|progress_label|unread|last_notification|phase|phase_icon|phase_color`
- Animated glyphs (running: `⠋⠙⠹⠸`, waiting: `◐◓◑◒`) rotate via `FRAME_INDEX` incremented each tick. ASCII fallbacks exist for `TERM=dumb` or `NO_COLOR=1`.
- Nerd Font glyphs are gated on `@orchestra_nerd_fonts on|off` (no auto-detection).

## Testing

```sh
make test          # shellcheck + test_cli.sh + test_render.sh
make shellcheck    # shellcheck only
```

- `tests/test_cli.sh` spins up a detached tmux server on a private socket (`-L <socket>`), exercises every CLI subcommand, and asserts option values are written correctly. Always clean up the server with `tmux -L <socket> kill-server` at the end.
- `tests/test_render.sh` sources [lib/render.sh](lib/render.sh), feeds fixture data, and diffs stdout against [tests/fixtures/](tests/fixtures/) `.expected` files.
- **When adding a feature, add a corresponding test.** For rendering changes, add or update `.expected` fixture files.
- All tests must pass and shellcheck must be clean before a change is complete.

## Key conventions

### Option writes
Always go through `set_opt` / `clear_opt`. These enforce max-length truncation (trailing `…`) and correct tmux scope. Direct `tmux set-option -w @ab_*` calls bypass truncation and break renderer assumptions.

### Batched tmux calls
Prompt hooks batch multiple `set-option` calls with `\;` into one `tmux` invocation to minimize shell-prompt overhead. Follow this pattern whenever writing multiple options from a time-sensitive path.

### No new persistent state outside tmux options
Do not introduce temp files, FIFOs, sockets, or environment variables as a persistence mechanism. All cross-process communication goes through `@ab_*` options and SIGUSR1.

### SIGUSR1 wakeup
After writing state that should appear immediately in the sidebar (e.g., `notify`), send `kill -USR1 <renderer_pid>` where pid comes from `@ab_sidebar_pid`. The renderer may not be running (sidebar closed) — handle that case silently.

### Sidebar pane lifecycle
The sidebar is a real tmux pane running `orchestra-render`. `orchestra-follow` moves the pane across windows via `move-pane` on every `pane-focus-in`. The renderer PID stays alive across moves; always signal via `@ab_sidebar_pid`, not by searching process trees.

## Agent harness integration pattern

New harness templates belong in `hooks/<name>/` and follow this contract:
1. Map "agent is working" events → `orchestra set-state running --action "<tool>"`.
2. Map "agent needs input" events → `orchestra set-state waiting --action "<prompt>"`.
3. Map "agent finished" events → `orchestra set-state done && orchestra clear-state`.
4. For significant events → `orchestra notify --title "…" --body "…"`.
5. Document in a `README.md` inside the hooks directory.
6. Never depend on non-standard binaries in the core path (jq is optional, used only in Claude Code template).

## What not to implement (v0.1 scope)

The items in [spec/FUTURE.md](spec/FUTURE.md) are explicitly deferred. Do not implement:
- Per-window color theming or arbitrary multi-pill rendering.
- Pane-border unread indicators.
- Compact statusline integration.
- State dump/restore.
- Fish or PowerShell prompt hooks.
- Real-time tmux hook on arbitrary option writes (not achievable without polling).

## Quick orientation for common tasks

| Task | Where to look |
|---|---|
| Add a new CLI subcommand | `bin/orchestra` — add `cmd_<name>()` and a `case` branch |
| Change rendering layout | [lib/render.sh](lib/render.sh) — `render_window_block` and `render_rows` |
| Add a platform notifier | [lib/notify.sh](lib/notify.sh) — extend `orchestra_notify_dispatch` |
| Change default config/keys | [orchestra.tmux](orchestra.tmux) — top-level option and bind-key calls |
| Add a new harness template | `hooks/<name>/` — template files + README |
| Debug option state | `tmux show-options -w @ab_*` in the target window |
| Trace renderer input | `tmux list-windows -F '...'` (copy format from `orchestra-render`) |
