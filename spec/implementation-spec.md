# Implementation Spec: `tmux-orchestra` v0.1.0

This is a concrete hand-off spec. Design rationale and tradeoffs live in [planning-spec.md](planning-spec.md); don't re-litigate those decisions here — implement what's below.

## 0. Non-negotiables

- **POSIX shell only.** No Rust, Go, Python, or Node. Every executable in this repo is a `#!/bin/sh` script that passes `shellcheck -s sh`.
- **No external runtime deps** beyond tmux ≥ 3.2 and the platform notifier binary. Specifically: no `jq`, no `bash`-only features, no GNU-only flags (`sed -i` without arg, `grep -P`, `readlink -f`, etc.).
- **tmux is the only state store.** No files under `$XDG_RUNTIME_DIR`, no SQLite, no sockets beyond tmux's own.
- **TPM-installable.** User clones the repo into `~/.tmux/plugins/tmux-orchestra`, adds one line to `.tmux.conf`, reloads — done.

## 1. Repository layout

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

## 2. User-option schema (authoritative)

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
2. `$ORCHESTRA_WINDOW_ID` if set (see §5).
3. `tmux display-message -p -t "$TMUX_PANE" '#{window_id}'` if `$TMUX_PANE` set.
4. `tmux display-message -p '#{window_id}'` (current window).
5. Error: "not in tmux and no --window given."

Implement this as `resolve_window()` in `lib/common.sh` once; every CLI entrypoint calls it.

**Truncation.** `set_opt()` in `common.sh` truncates values to the per-field max (see table) before writing. Truncation adds a trailing `…`.

## 3. CLI surface (`bin/orchestra`)

Exact argument shapes. Deviating from these breaks the Claude Code / Codex / OpenCode templates.

```
orchestra set-status <key> <value> [--icon GLYPH] [--color COLOR] [--window ID]
orchestra clear-status <key> [--window ID]
orchestra list-status [--window ID]
orchestra set-progress <float> [--label TEXT] [--window ID]
orchestra clear-progress [--window ID]
orchestra notify --title T [--body B] [--subtitle S] [--window ID]
orchestra set-state <running|waiting|done> [--action TEXT] [--window ID]
orchestra clear-state [--window ID]
```

`set-state` is sugar for `set-option @ab_agent_state` + optional `@ab_current_action`. It exists so harness templates are one-liners. When `--action` is omitted, the previous action is cleared (the sidebar shows a bare state glyph).

**Argument parsing.** POSIX-compatible hand-rolled parser (no `getopts` long options). Template:

```sh
while [ $# -gt 0 ]; do
    case "$1" in
        --icon)   icon="$2"; shift 2 ;;
        --color)  color="$2"; shift 2 ;;
        --window) win="$2"; shift 2 ;;
        --) shift; break ;;
        -*) err "unknown flag: $1" ;;
        *) break ;;
    esac
done
```

**Exit codes:** 0 success, 1 usage error, 2 not-in-tmux, 3 tmux call failed.

**Dispatch:** single-file script; subcommand is `$1`, dispatch to `cmd_<name>` function.

## 4. Renderer (`bin/orchestra-render`)

Loop:

```
while true; do
    redraw
    # Wait up to 500 ms, but wake on SIGUSR1 (from set-hooks)
    sleep_interruptible 0.5
done
```

`sleep_interruptible`: trap SIGUSR1 to a no-op and run `sleep 0.5 &; wait $!` — the signal cancels the wait.

**Data read (one tmux call per tick):**

```sh
tmux list-windows -a -F '#{session_name}|#{window_id}|#{window_name}|#{window_active}|#{@ab_agent_state}|#{@ab_current_action}|#{@ab_branch}|#{@ab_cwd}|#{@ab_last_cmd}|#{@ab_progress}|#{@ab_progress_label}|#{@ab_unread}|#{@ab_last_notification}|#{@ab_status_phase}|#{@ab_status_phase__icon}|#{@ab_status_phase__color}'
```

For v0.1 only one status pill is rendered — `phase`. Iterating over arbitrary `@ab_status_*` keys requires a second tmux call per window and is deferred to v0.2.

**Per-window row format** (pseudocode; see §6 for glyphs):

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

**Active window** gets inverse colors on its title row.

**No mouse support in v0.1** (deferred to v0.3). No horizontal scrolling. If a window has a very long `@ab_current_action`, truncate to pane-width minus 4 with trailing `…`.

**Color output:** use `tput setaf` via a small wrapper in `lib/render.sh`. On `TERM=dumb` or when `NO_COLOR` is set, drop all ANSI.

## 5. Auto-discovery env vars

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

## 6. Glyph and color defaults

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

## 7. Platform notifier (`bin/orchestra-notify`)

Arguments: `--title T [--body B] [--subtitle S]`.

Detection order:

1. `[ -n "$ORCHESTRA_NOTIFIER" ]` → use user's override.
2. Linux (`uname -s` = `Linux`) and `command -v notify-send` → `notify-send "$title" "$body"`.
3. macOS (`uname -s` = `Darwin`) and `command -v terminal-notifier` → `terminal-notifier -title "$title" -message "$body"`.
4. macOS fallback → `osascript -e "display notification \"$body\" with title \"$title\""`.
5. WSL (`uname -r` contains `microsoft`) and `command -v wsl-notify-send.exe` → that.
6. WSL/Cygwin/MSYS2 fallback → `powershell.exe -NoProfile -Command 'New-BurntToastNotification -Text ...'`.
7. No notifier found → `tmux display-message` + bell, exit 0. Never fail the `notify` call because of a missing notifier.

Escaping: the notifier shim must safely pass arbitrary user strings. Quote with POSIX `printf '%s'` and avoid `eval`.

## 8. Prompt hooks

### `hooks/prompt.bash`

```bash
_orchestra_publish() {
    local exit_code=$?
    [ -z "${TMUX:-}" ] && return
    local pane="${TMUX_PANE:-}"
    [ -z "$pane" ] && return
    local win
    win=$(tmux display-message -p -t "$pane" '#{window_id}') || return
    tmux set-option -t "$win" -w @ab_cwd "$PWD"
    tmux set-option -t "$win" -w @ab_last_exit "$exit_code"
    local branch
    branch=$(git -C "$PWD" symbolic-ref --short HEAD 2>/dev/null || printf '')
    tmux set-option -t "$win" -w @ab_branch "$branch"
    if [ -n "${_orchestra_last_cmd:-}" ]; then
        tmux set-option -t "$win" -w @ab_last_cmd "$_orchestra_last_cmd"
    fi
    return $exit_code
}
trap '_orchestra_last_cmd=$BASH_COMMAND' DEBUG
PROMPT_COMMAND="_orchestra_publish${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
```

### `hooks/prompt.zsh`

Uses `precmd` + `preexec` for `$_orchestra_last_cmd`. Same tmux calls.

Both hooks must be safe to source twice. Cost budget: ≤ 3 tmux calls per prompt.

## 9. Agent harness templates

### Claude Code (`hooks/claude-code/settings.json`)

Drop-in snippet users merge into `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [{
      "hooks": [{
        "type": "command",
        "command": "orchestra set-state running --action \"$(jq -r '.tool_name + \": \" + (.tool_input | tostring | .[0:100])' <<< \"$CLAUDE_HOOK_INPUT\")\""
      }]
    }],
    "Notification": [{
      "hooks": [{
        "type": "command",
        "command": "orchestra set-state waiting --action \"$(jq -r '.message // \"waiting for input\"' <<< \"$CLAUDE_HOOK_INPUT\")\" && orchestra notify --title \"Claude Code\" --body \"waiting for input\""
      }]
    }],
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "orchestra set-state done && orchestra clear-state"
      }]
    }]
  }
}
```

**Note**: the template uses `jq` because Claude Code hooks pass JSON on stdin and there's no shell-only way to parse it. `jq` is a dep *of the hook template*, not of `orchestra` itself. Document this in `hooks/claude-code/README.md`.

### Codex (`hooks/codex/hooks.toml`)

Maps Codex's `on_tool_start` / `on_tool_end` / `on_turn_end` to the same three `orchestra` calls. Stub for v0.1 — Codex hook docs are still stabilising.

### OpenCode (`hooks/opencode/orchestra.js`)

Working plugin for OpenCode (v0.2). Copy `orchestra.js` to `.opencode/plugins/` — it auto-loads on restart.

Hooks:
- `tool.execute.before` → `orchestra set-state running --action <tool>`
- `tool.execute.after` → `orchestra set-state done && orchestra clear-state` (only when the last pending tool finishes; a counter prevents flicker during multi-tool chains)
- `permission.ask` → `orchestra set-state waiting --action <permission_title>`
- `event` (`session.idle`) → `orchestra set-state done && orchestra clear-state`

All shell calls use `.nothrow()` so a missing `orchestra` binary won't crash OpenCode.

## 10. Sidebar toggle (`bin/orchestra-toggle`)

Behavior:

1. Read session option `@ab_sidebar_pane_id`.
2. If set and pane still exists → `tmux kill-pane -t "$pid"`, unset option, return.
3. Else: read cached width from `@ab_width` (default 32). `tmux split-window -bhd -l "$width" -t "$current_window" -c "$PWD" orchestra-render`. Capture new pane id into `@ab_sidebar_pane_id`.

### Window-following (`bin/orchestra-follow`)

The sidebar pane is not fixed to a single window. On every `pane-focus-in`, `orchestra-follow` checks whether the focused window already contains the sidebar pane. If not, it runs:

```
tmux move-pane -hb -l <width> -s <sidebar_pane> -t <active_pane_in_current_window>
```

This transplants the pane (and its running `orchestra-render` process) into the new window's layout on the left edge. Because the same process moves with the pane, there is no restart flicker.

**Window-closing edge case.** If the source window contained only the sidebar pane, `move-pane` leaves it empty and tmux closes that window. This is acceptable behaviour — the user was already leaving that window by switching focus elsewhere.

## 11. `orchestra.tmux` (TPM entrypoint)

Must:

- Set default options (`focus-events on`, `@orchestra_nerd_fonts off`, `@orchestra_key B`, `@orchestra_width 32`). `focus-events` is required for `pane-focus-in` to fire on window/pane switches.
- Bind `prefix + <key>` (from option) to `run-shell "$CURRENT_DIR/bin/orchestra-toggle"`.
- Register `pane-focus-in` hook: clear `@ab_unread`, write `ORCHESTRA_WINDOW_ID` / `ORCHESTRA_PANE_ID`, and run `orchestra-follow` to move the sidebar pane to the current window if needed.
- Register `window-renamed`, `client-session-changed` hooks: `kill -USR1` the renderer process (look up PID from `@ab_sidebar_pid` session option).
- Prepend `$CURRENT_DIR/bin` to `PATH` in the session env so `orchestra` is callable from any pane.

Follow the TPM convention for `$CURRENT_DIR` resolution (copy from `tmux-sidebar`'s `sidebar.tmux`).

## 12. Testing

- **`tests/test_cli.sh`**: start a detached tmux server (`tmux -L orchestra-test`), run `orchestra set-status phase build`, assert `tmux show-options -v -w @ab_status_phase` returns `build`. Cover every CLI subcommand.
- **`tests/test_render.sh`**: feed `lib/render.sh` fixture option dumps and diff output against `tests/fixtures/*.expected` text files. Pure function, no tmux needed.
- **`shellcheck`** on every `bin/*` and `lib/*`.
- **`make test`** runs all three. Keep runtime under 10 s.

CI: GitHub Actions matrix — Ubuntu (tmux 3.2a and 3.4), macOS (Homebrew tmux).

## 13. Out of scope for v0.1 — do not implement

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

## 14. Definition of done

- `git clone` into `~/.tmux/plugins/tmux-orchestra`, add `set -g @plugin 'gauravmm/tmux-orchestra'` (or equivalent path) to `.tmux.conf`, `prefix + I` (TPM install), `prefix + B` opens a sidebar pane.
- In a second pane, `orchestra set-status phase build --icon '*' --color cyan` — the sidebar row for that window shows a cyan `* build` pill within 500 ms.
- `orchestra set-state running --action "Bash: pytest"` — sidebar shows spinning glyph + action text.
- `orchestra notify --title "Build" --body "done"` — desktop toast fires, pane border marked unread, focus-in clears it.
- Source `hooks/prompt.bash` in a fresh shell, `cd /tmp && ls` — sidebar row updates to `cwd=/tmp  $ ls`.
- Install the Claude Code hook snippet, run a Claude Code session — sidebar shows `running` during tool use, `waiting` at user prompts, `done` after Stop.
- `shellcheck` clean, tests green on Linux and macOS.