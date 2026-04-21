# Claude Code hook template

Merge `settings.json` into `~/.claude/settings.json` to map Claude Code hook
events onto `agentbar` status updates.

## Note about jq

The template uses `jq` because Claude Code provides structured JSON hook input.
`tmux-agentbar` itself does **not** depend on `jq`; only this optional hook
template does.
