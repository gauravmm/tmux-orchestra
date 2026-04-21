# OpenCode hook template

This repository ships a documented stub for v0.1.

Planned mapping:

- `on_tool_call` → `orchestra set-state running --action "..."`
- response / user-input wait → `orchestra set-state waiting --action "..."`
- final response / stop → `orchestra set-state done && orchestra clear-state`

Fill in the concrete JSON schema from the OpenCode hook docs when promoting the
stub to a working template in a later release.
