# OpenCode hook template

Drop-in plugin for [OpenCode](https://opencode.ai/) that maps agent events to `orchestra` status updates.

## Installation

Copy `orchestra.js` into your OpenCode plugins directory:

```sh
# Global (applies to all projects)
cp hooks/opencode/orchestra.js ~/.config/opencode/plugins/

# Or project-local
mkdir -p .opencode/plugins
cp hooks/opencode/orchestra.js .opencode/plugins/
```

Restart OpenCode. The plugin auto-loads from `.opencode/plugins/` — no config changes needed.

## Event mapping

| OpenCode event | Orchestra state | Action |
|---|---|---|
| `chat.message` | `running` | — |
| `tool.execute.before` | `running` | Tool name |
| `tool.execute.after` | `done` (when last tool finishes) | — |
| `permission.ask` | `waiting` | Permission title |
| `session.idle` | `done` | — |
| `session.deleted` / `server.instance.disposed` | `done` + clear | — |

A pending-tool counter prevents flicker when OpenCode chains multiple tools in sequence. The `chat.message` hook makes the spinner appear during pure "thinking/responding" turns even when no tool runs.

## Notes

- The plugin calls `orchestra` via Bun's shell API. Ensure `orchestra` is on your `PATH` (set automatically by `orchestra.tmux` for new panes).
- All `orchestra` calls use `.nothrow()` so a missing binary or tmux disconnect won't crash OpenCode.
