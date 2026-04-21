# tmux-agentbar

`tmux-agentbar` is a pure POSIX shell tmux plugin that exposes a small CLI for
agent status, notifications, and prompt-published context, then renders that
state in a dedicated sidebar pane.

## Highlights

- TPM-installable plugin entrypoint via `agentbar.tmux`
- `agentbar` CLI for status pills, progress, notifications, and agent state
- Long-lived `agentbar-render` sidebar pane
- Bash and zsh prompt hooks for cwd / branch / last command
- Claude Code hook template plus stub templates for Codex and OpenCode
- Shellcheck-clean shell implementation with tests under `make test`

## Installation

1. Clone this repository into `~/.tmux/plugins/tmux-agentbar`.
2. Add the plugin to `.tmux.conf`:

   ```tmux
   set -g @plugin 'gauravmm/tmux-agentbar'
   run '~/.tmux/plugins/tpm/tpm'
   ```

3. Reload tmux, then install plugins with `prefix + I`.
4. Toggle the sidebar with `prefix + B`.

## CLI quick start

```sh
agentbar set-status phase build --icon '*' --color cyan
agentbar set-progress 0.42 --label 'Tests'
agentbar set-state running --action 'pytest'
agentbar notify --title 'Build' --body 'done'
agentbar clear-state
```

## Prompt hooks

Source one of the prompt hooks from your shell startup file:

```sh
. ~/.tmux/plugins/tmux-agentbar/hooks/prompt.bash
# or
. ~/.tmux/plugins/tmux-agentbar/hooks/prompt.zsh
```

## Agent harness templates

- Claude Code: `hooks/claude-code/`
- Codex: `hooks/codex/`
- OpenCode: `hooks/opencode/`

## Testing

Run the full shellcheck + test suite:

```sh
make test
```

## Key implementation decisions

- **Polling renderer, hook-assisted wakeups:** tmux does not emit hooks for
  arbitrary user-option writes, so the renderer uses a single `list-windows`
  poll every 500 ms and lets hooks wake it early on focus and rename events.
- **tmux options as the only datastore:** every state update is written into
  tmux options to keep the plugin installable without files, sockets, or extra
  daemons.
- **Single rendered status pill in v0.1:** the CLI accepts arbitrary keys, but
  the renderer only draws the `phase` pill so rendering stays within one tmux
  query per tick.
- **Prompt hook tmux budget:** the hooks batch writes into one `tmux` command
  after resolving the window id so they stay lightweight in interactive shells.
