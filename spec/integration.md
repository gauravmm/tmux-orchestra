# Integration: Notifier, Prompt Hooks & Agent Harnesses
## tmux-orchestra v0.1.0

*Part of the [implementation spec](implementation-spec.md). See [cli.md](cli.md) for the orchestra commands harnesses call.*

## Platform notifier (`bin/orchestra-notify`)

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

## Prompt hooks

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

## Agent harness templates

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

## Adding a new harness

New harness templates belong in `hooks/<name>/` and follow this contract:

1. Map "agent is working" events → `orchestra set-state running --action "<tool>"`.
2. Map "agent needs input" events → `orchestra set-state waiting --action "<prompt>"`.
3. Map "agent finished" events → `orchestra set-state done && orchestra clear-state`.
4. For significant events → `orchestra notify --title "…" --body "…"`.
5. Document in a `README.md` inside the hooks directory.
6. Never depend on non-standard binaries in the core path (`jq` is optional, used only in the Claude Code template).
