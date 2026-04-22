# Codex hook template

This repository ships a stub `hooks.toml` for v0.1.

Planned mapping:

- tool start → `orchestra set-state running --action "..."`
- prompt / waiting state → `orchestra set-state waiting --action "..."`
- turn end / stop → `orchestra set-state done && orchestra clear-state`

Consult the current Codex hook documentation before filling in the exact TOML
syntax because Codex is intentionally left as a documented stub in v0.1.
