# Core: Constraints, Schema & Conventions
## tmux-orchestra v0.1.0

*Part of the [implementation spec](implementation-spec.md). Design rationale lives in [planning-spec.md](planning-spec.md).*

## Non-negotiables

- **POSIX shell only.** No Rust, Go, Python, or Node. Every executable in this repo is a `#!/bin/sh` script that passes `shellcheck -s sh`.
- **No external runtime deps** beyond tmux ≥ 3.2 and the platform notifier binary. Specifically: no `jq`, no `bash`-only features, no GNU-only flags (`sed -i` without arg, `grep -P`, `readlink -f`, etc.).
- **tmux is the only state store.** No files under `$XDG_RUNTIME_DIR`, no SQLite, no sockets beyond tmux's own.
- **TPM-installable.** User clones the repo into `~/.tmux/plugins/tmux-orchestra`, adds one line to `.tmux.conf`, reloads — done.

## Repository layout

```
tmux-orchestra/
├── orchestra.tmux                 # TPM entrypoint. Sourced by tmux.
├── README.md
├── LICENSE                       # MIT
├── bin/
│   ├── orchestra                  # Main CLI (set-status, set-progress, notify, ...)
│   ├── orchestra-render           # Long-lived renderer TUI in the sidebar pane
│   ├── orchestra-notify           # Platform-detecting notifier shim
│   └── orchestra-toggle           # Open/close the sidebar pane
├── lib/
│   ├── common.sh                 # Shared helpers: resolve_window, set_opt, get_opt
│   ├── render.sh                 # Pure rendering helpers (format row, state glyph)
│   └── notify.sh                 # Platform detection
├── hooks/
│   ├── prompt.bash               # Source from ~/.bashrc
│   ├── prompt.zsh                # Source from ~/.zshrc
│   ├── claude-code/
│   │   ├── settings.json         # Drop-in Claude Code hooks config
│   │   └── README.md
│   ├── codex/
│   │   ├── hooks.toml
│   │   └── README.md
│   └── opencode/
│       ├── orchestra.js           # OpenCode plugin (auto-load from .opencode/plugins/)
│       ├── config.json
│       └── README.md
└── tests/
    ├── test_cli.sh
    ├── test_render.sh
    └── fixtures/
```

All shell scripts start with `#!/bin/sh` and `set -eu`. Library files in `lib/` use `. "$ORCHESTRA_LIB/common.sh"` style sourcing; they never `set -e` themselves.

## User-option schema (authoritative)

All options are tmux **window** options unless noted. Keys are literal — the renderer does `tmux list-windows -F '#{@ab_agent_state}|...'` and parses by position.

| Option | Type | Writer | Cleared by |
|---|---|---|---|
| `@ab_agent_state` | `running` \| `waiting` \| `done` \| empty | Harness hook | Harness hook on Stop |
| `@ab_current_action` | string ≤ 120 chars | Harness hook | Harness hook on Stop |
| `@ab_status_<key>` | string ≤ 40 chars | `orchestra set-status <key> <val>` | `orchestra clear-status <key>` |
| `@ab_status_<key>__icon` | one grapheme | `--icon` flag | with the pill |
| `@ab_status_<key>__color` | `#rrggbb` or named | `--color` flag | with the pill |
| `@ab_progress` | float in `[0,1]` | `orchestra set-progress` | `orchestra clear-progress` |
| `@ab_progress_label` | string ≤ 60 | `--label` flag | with progress |
| `@ab_unread` | `1` or empty | `orchestra notify` | focus-in hook |
| `@ab_last_notification` | string ≤ 120 | `orchestra notify` | never (overwritten) |
| `@ab_branch` | string | Prompt hook | overwritten each prompt |
| `@ab_cwd` | string | Prompt hook | overwritten |
| `@ab_last_cmd` | string ≤ 80 | Prompt hook | overwritten |
| `@ab_last_exit` | integer | Prompt hook | overwritten |
| `@ab_width` (session) | integer | `orchestra-toggle` | — |

**Target resolution.** Every CLI call resolves "which window?" in this order:

1. `--window <id>` flag if given.
2. `$ORCHESTRA_WINDOW_ID` if set (see Auto-discovery env vars below).
3. `tmux display-message -p -t "$TMUX_PANE" '#{window_id}'` if `$TMUX_PANE` set.
4. `tmux display-message -p '#{window_id}'` (current window).
5. Error: "not in tmux and no --window given."

Implement this as `resolve_window()` in `lib/common.sh` once; every CLI entrypoint calls it.

**Truncation.** `set_opt()` in `common.sh` truncates values to the per-field max (see table) before writing. Truncation adds a trailing `…`.

## Auto-discovery env vars

`orchestra.tmux` adds to the session-wide `update-environment` list:

```tmux
set-option -ga update-environment 'ORCHESTRA ORCHESTRA_WINDOW_ID ORCHESTRA_PANE_ID'
```

And the plugin sets per-session:

```tmux
setenv -g ORCHESTRA 1
```

Per-pane `ORCHESTRA_WINDOW_ID` / `ORCHESTRA_PANE_ID` are set by a `pane-focus-in` hook that runs:

```sh
tmux setenv -t "$session" ORCHESTRA_WINDOW_ID "$window_id"
tmux setenv -t "$session" ORCHESTRA_PANE_ID "$pane_id"
```

(Agents spawning new shells will see these on first shell start; they won't mutate inside an already-open shell. Acceptable for v0.1.)

## Glyph and color defaults

Two icon sets; selected by window option `@orchestra_nerd_fonts` (default: `off`).

| Purpose | Nerd | ASCII |
|---|---|---|
| State: running | `⠋` (animated braille) | `*` |
| State: waiting | `◐` (animated) | `?` |
| State: done | `` | `OK` |
| Unread dot | `●` | `!` |
| Progress filled | `█` | `#` |
| Progress empty | `░` | `-` |
| Branch | `` | `git:` |
| cwd | `` | `cd:` |

Default pill colors by semantic: `info=cyan`, `success=green`, `warning=yellow`, `error=red`. `set-status` takes whatever `--color` string the caller gives; no validation beyond "is it a known `tput` color name or a `#rrggbb`."
