# Implementation Spec: `tmux-orchestra` v0.1.0

This is a concrete hand-off spec. Design rationale and tradeoffs live in [planning-spec.md](planning-spec.md); don't re-litigate those decisions here — implement what's below.

## Sub-specs

| File | Contents |
|---|---|
| [core.md](core.md) | Non-negotiables, repository layout, user-option schema, auto-discovery env vars, glyph & color defaults |
| [cli.md](cli.md) | CLI surface — exact argument shapes, exit codes, dispatch pattern |
| [renderer.md](renderer.md) | Renderer loop, data format, per-window row layout, flicker-free redraw |
| [integration.md](integration.md) | Platform notifier, prompt hooks (bash/zsh), agent harness templates (Claude Code, OpenCode, Codex) |
| [sidebar.md](sidebar.md) | Sidebar toggle, window-following, `orchestra.tmux` TPM entrypoint |
| [quality.md](quality.md) | Testing, out-of-scope list, definition of done |

## Reading order

- **Implementing anything**: read [core.md](core.md) first — it defines the option schema and conventions everything else depends on.
- **Adding a CLI subcommand**: [core.md](core.md) → [cli.md](cli.md).
- **Changing the sidebar rendering**: [core.md](core.md) → [renderer.md](renderer.md).
- **Adding a new agent harness**: [cli.md](cli.md) → [integration.md](integration.md).
- **Changing sidebar toggle/follow behavior**: [core.md](core.md) → [sidebar.md](sidebar.md).
- **Checking scope or acceptance criteria**: [quality.md](quality.md).
