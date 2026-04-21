# OpenCode hook template

This repository ships a documented stub for v0.1.

Planned mapping:

- `on_tool_call` → `agentbar set-state running --action "..."`
- response / user-input wait → `agentbar set-state waiting --action "..."`
- final response / stop → `agentbar set-state done && agentbar clear-state`

Fill in the concrete JSON schema from the OpenCode hook docs when promoting the
stub to a working template in a later release.
