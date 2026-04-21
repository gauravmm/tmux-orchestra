# Codex hook template

This repository ships a stub `hooks.toml` for v0.1.

Planned mapping:

- tool start → `agentbar set-state running --action "..."`
- prompt / waiting state → `agentbar set-state waiting --action "..."`
- turn end / stop → `agentbar set-state done && agentbar clear-state`

Consult the current Codex hook documentation before filling in the exact TOML
syntax because Codex is intentionally left as a documented stub in v0.1.
