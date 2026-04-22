# CLI: `bin/orchestra`
## tmux-orchestra v0.1.0

*Part of the [implementation spec](implementation-spec.md). See [core.md](core.md) for the option schema and window target resolution.*

## CLI surface

Exact argument shapes. Deviating from these breaks the Claude Code / Codex / OpenCode templates.

```
orchestra set-status <key> <value> [--icon GLYPH] [--color COLOR] [--window ID]
orchestra clear-status <key> [--window ID]
orchestra list-status [--window ID]
orchestra set-progress <float> [--label TEXT] [--window ID]
orchestra clear-progress [--window ID]
orchestra notify --title T [--body B] [--subtitle S] [--quiet] [--window ID]
orchestra set-state <running|waiting|done> [--action TEXT] [--window ID]
orchestra clear-state [--window ID]
```

`set-state` is sugar for `set-option @ab_agent_state` + optional `@ab_current_action`. It exists so harness templates are one-liners. When `--action` is omitted, the previous action is cleared (the sidebar shows a bare state glyph).

`notify` always writes `@ab_unread` and `@ab_last_notification`; `--quiet` suppresses only the platform notifier (`bin/orchestra-notify`). Use `--quiet` for hooks that want the sidebar marker + context line without firing a desktop toast (e.g. "file changed in background", bulk marker setup in manual tests).

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
