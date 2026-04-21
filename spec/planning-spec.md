# Spec: Porting cmux Sidebar Features to tmux (`tmux-orchestra`)

## 1. cmux feature inventory (relevant subset)

cmux is a Swift/AppKit macOS terminal built on libghostty, not a tmux fork. The features that matter for a tmux port:

- **Vertical sidebar with per-workspace tabs**, each showing: name, git branch, cwd, listening ports, latest notification, status pills, a progress bar, recent log entries, unread badge.
- **Notification system**: pane gets a blue ring, sidebar tab lights up, OS-level desktop toast. Triggered by terminal escape sequences (OSC 9 / 99 / 777) **or** by the `cmux notify` CLI.
- **Sidebar-writable CLI surface** — the part agents/harnesses use:
  - `set-status <key> <value> [--icon X] [--color #hex]` / `clear-status` / `list-status`
  - `set-progress <0.0–1.0> [--label "text"]` / `clear-progress`
  - `log --level info|success|warning|error --source "agent" -- "msg"` / `list-log` / `clear-log`
  - `notify --title T --subtitle S --body B`
  - `trigger-flash --surface <ref>`
- **Layout/control CLI**: `list-workspaces`, `new-workspace`, `new-split`, `send`, `send-key`, `read-screen`, `close-surface`, etc.
- **Unix socket API** mirroring the CLI 1:1.
- **Auto-detection env vars** in spawned terminals: `CMUX_WORKSPACE_ID`, `CMUX_SURFACE_ID`, `CMUX_SOCKET_PATH`. Tools check these to decide whether to talk to cmux.
- **Defaults to caller's workspace/surface** when flags omitted, so commands run inside cmux "just work."

A few cmux features intentionally **out of scope** for the tmux port: the embedded WebKit browser pane, GPU-accelerated rendering, and macOS-native Sparkle auto-update.

## 2. Concept mapping: cmux → tmux

| cmux | tmux | Notes |
|---|---|---|
| Workspace | **Window** (recommended) or session | Window keeps everything in one tmux session, which is what most users want. |
| Pane | Pane | 1:1. |
| Surface (tab-in-pane) | Window | tmux has no horizontal tabs inside a pane; collapse to windows. |
| Sidebar | Dedicated pinned pane on the left of the active window | Same trick as `tmux-sidebar`. |
| Sidebar metadata KV store | **tmux user options** (`@ab_*`) scoped per window | Native, persistent for the session lifetime, free. |
| Socket API | The tmux command socket itself | Already exists; CLI wraps `tmux` invocations. |
| Desktop notification | Platform notifier (notify-send / osascript / BurntToast) | Abstracted in a small dispatcher. |
| Pane "blue ring" | `pane-border-style` conditional on `@ab_unread` | Less prominent than cmux's glow but visible. |

## 3. Assessment of `tmux-plugins/tmux-sidebar`

`tmux-sidebar` is a 600-star, MIT-licensed, pure-shell plugin. It does one thing: open a tree-listing pane on the left of the current pane, with smart per-cwd width caching and toggle behaviour. Mechanism: `split-window -bhd -l <width>` then run `tree` (or fallback). Tested on Linux, macOS, Cygwin.

**What to reuse:**

- The split/toggle dance (preserves user's existing pane layout on close).
- Per-context width persistence (we'd cache per-window instead of per-cwd).
- TPM-compatible plugin layout (`sidebar.tmux` entrypoint, scripts directory).
- Cygwin compatibility — useful for the Windows story.

**What to drop / change:**

- It runs `tree` once and doesn't update. We need a long-lived renderer process.
- It's a single sidebar; we want per-window state aggregated.
- Its directory-tree purpose is orthogonal — `tmux-agentbar` could even coexist with it, bound to a different key.

**Recommendation:** Don't fork. Borrow the toggle pattern as a small shell module and build the renderer fresh.

## 4. Architecture

### Components

1. **`tmux-agentbar` plugin** — TPM-installable. `agentbar.tmux` registers key bindings, default options, and `set-hook`s.
2. **`agentbar` CLI** — POSIX-shell wrapper around `tmux set-option`, `tmux show-options`, `tmux display-message`. Single script. (Optional Go/Rust rewrite later for speed and to drop the `jq` dependency.)
3. **`agentbar-render`** — long-lived TUI living in the sidebar pane. Reads tmux state and redraws.
4. **Notification dispatcher** — `agentbar-notify` shim that detects OS and calls the right notifier.
5. **Shell integration snippets** — bash/zsh/fish/PowerShell prompt hooks that auto-publish cwd, git branch, and last exit code.

### State model — everything lives in tmux user options

| Scope | Option | Meaning |
|---|---|---|
| Window | `@ab_status_<key>` | Pill text |
| Window | `@ab_status_<key>__icon` | Nerd-font glyph or unicode |
| Window | `@ab_status_<key>__color` | Hex or named ANSI |
| Window | `@ab_progress` | Float 0.0–1.0 |
| Window | `@ab_progress_label` | String |
| Window | `@ab_unread` | 0/1 |
| Window | `@ab_last_notification` | String (truncated) |
| Window | `@ab_branch`, `@ab_cwd`, `@ab_ports` | Auto-published by shell hook |
| Server | `@ab_log_dir` | Where log JSONL files live (`$XDG_RUNTIME_DIR/agentbar`) |

Why user options: they're the tmux-native KV store, persist as long as the server lives, are readable from `tmux list-windows -F '#{@ab_branch}'` in one call, and don't require a second IPC channel. Logs go to disk because they're append-heavy and would bloat options.

### Sidebar pane

- Opened with `split-window -bhd -l <width>` (left side, no focus, fixed width).
- Runs `agentbar-render`, which:
  - Polls `tmux list-windows -F '#{window_id}|#{window_name}|#{@ab_branch}|#{@ab_cwd}|#{@ab_status_phase}|#{@ab_progress}|#{@ab_unread}|...'` every 500 ms.
  - Subscribes to `set-hook` notifications via SIGUSR1 for instant redraws on `window-renamed`, `pane-focus-in`, `client-session-changed`.
  - Renders blocks: title bar (workspace name + branch), pill row, unicode progress bar `█████░░░░░ 50%`, last log line, unread dot.
  - Highlights the active window; supports mouse click → `tmux select-window`.
- Toggle: `prefix + B` (avoiding tmux-sidebar's `prefix + Tab`). Cached width per-window.

### Notification flow

```
agent → agentbar notify --title T --body B
         │
         ├─ tmux set-option -w @ab_unread 1
         ├─ tmux set-option -w @ab_last_notification "T: B"
         ├─ tmux set-hook fires sidebar redraw
         ├─ platform notifier → desktop toast
         └─ optional: tmux display-message + bell
```

Focus-in hook on the window clears `@ab_unread` automatically.

### Pane-border indicator (substitute for cmux's blue ring)

```tmux
set -g pane-border-status top
set -g pane-border-format '#{?#{@ab_unread},#[fg=red] ● ATTENTION ,#[fg=default]}#{pane_current_command}'
```

## 5. Status-reporting mechanisms (ranked, easiest first)

The goal is that **any agent or harness in any language** can report status with one shell command. All five paths converge on the same tmux user-option store, so the sidebar renderer is agnostic to which one was used.

1. **CLI (universal default)** [TODO: Include this]
   `agentbar set-status phase build --icon  --color cyan`
   `agentbar set-progress 0.42 --label "Compiling crate 12/29"`
   `agentbar log --level error --source rustc -- "E0308 in main.rs:42"`
   `agentbar notify --title "Tests" --body "37 passed, 2 failed"`
   Defaults to caller's window/pane via `$TMUX_PANE`. Mirrors cmux's CLI surface so cmux-trained agents work unchanged after `alias cmux=agentbar`.

2. **Batched stdin ingest** [TODO: Exclude this]
   `... | agentbar ingest` accepts JSON lines, one event per line. Useful for high-frequency loggers.

3. **Shell prompt integration** (auto, no agent involvement) [TODO: Keep this]
   Bash `PROMPT_COMMAND`, zsh `precmd`, fish `fish_prompt`, PowerShell `prompt` function — each updates `@ab_cwd`, `@ab_branch`, `@ab_last_exit` once per prompt. This handles 80% of the "git branch + cwd" use case for free.

4. **Agent harness hooks** (Claude Code, Codex, OpenCode, Cursor agent, Aider…) [TODO: Do this for Claude Code, Codex, and OpenCode.]
   Ship template snippets that wire hooks to `agentbar` calls — e.g. Claude Code's `PostToolUse` → `agentbar log`, `SessionEnd` → `agentbar notify`. Same model cmux uses.

5. **OSC escape-sequence capture** (opt-in) [TODO: Drop this]
   `set -g @agentbar_osc on` activates a `pipe-pane -O` filter that scans for `\e]9;...\e\\` (iTerm-style) and `\e]777;notify;...\e\\` (urxvt-style) and translates them into `agentbar notify` calls. Off by default because `pipe-pane` adds per-byte overhead.

6. **Auto-discovery contract** for agents that want to mimic cmux's detection: [TODO: Keep this]

   ```
   AGENTBAR=1
   AGENTBAR_WINDOW_ID=@5
   AGENTBAR_PANE_ID=%12
   AGENTBAR_SOCKET=$TMUX        # tmux server socket path
   ```

   Exposed via tmux's `update-environment` so every new shell sees them. Agents check `[ -n "$AGENTBAR" ]` and switch behaviour.

## 6. Portability

| Platform | tmux | Notifier | Notes |
|---|---|---|---|
| Linux | native | `notify-send` (libnotify) | Pure default. |
| macOS | native (Homebrew) | `osascript -e 'display notification …'` or `terminal-notifier` if present | |
| Windows / WSL | native in WSL | `wsl-notify-send.exe` or `powershell.exe -c New-BurntToastNotification` shim | Recommended Windows path. |
| Windows / Cygwin / MSYS2 | works (tmux-sidebar already tests Cygwin) | `powershell.exe` toast bridge | Fallback for non-WSL Windows users. |
| Windows native (no WSL/Cygwin) | **unsupported** | — | Same limitation as tmux itself. Document this clearly and point users to `wmux` or `cmux-win` as alternatives if they need a native Windows experience. |

[TODO: Drop windows native.]

Hard requirements: tmux ≥ 3.2 (for `display-popup`, modern format expansions, and reliable `set-hook`), POSIX shell, `jq` (or a vendored fallback for the renderer). Nerd Font recommended for icons but not required — fall back to ASCII pills.

TODO: pros and cons of doing this in Rust

## 7. Tradeoffs and known limitations

- **The sidebar steals horizontal space.** Unlike cmux's GUI sidebar, ours is just another pane. Mitigation: bind `prefix + B` to toggle, and offer `prefix + Shift + B` to open an on-demand summary in `display-popup` instead (tmux 3.2+).
- **No true per-pane "blue ring."** `pane-border-style` driven by `@ab_unread` is the closest analogue. Visible, but less attention-grabbing than cmux's animated glow.
- **Surfaces (tabs inside a pane) don't exist in tmux.** We collapse them to windows. This is more tmux-idiomatic but breaks 1:1 with cmux's mental model — agent skills need a small adapter.
- **State persistence dies with the tmux server.** Recommend pairing with `tmux-resurrect` and providing an `agentbar dump` / `agentbar restore` pair that snapshots the user-option tree to `~/.cache/agentbar/state.json`. [TODO: Mark as FUTURE]
- **Polling vs hooks.** tmux's `set-hook` doesn't fire on arbitrary option changes, so the renderer needs a 250–500 ms poll fallback. Acceptable cost; renderer reads ~1 KB per tick.
- **OSC capture overhead.** `pipe-pane` filters every byte of pane output through a script. Opt-in only.
- **Status bar vs sidebar.** Some users will prefer their existing tmux status-bar setup. The plugin should expose `@ab_render_in_statusline` as an alternative low-information mode (badge count + active workspace pill in the existing status line) so sidebar-averse users still benefit.
- **Windows native** isn't possible without rewriting tmux. WSL is the practical answer.
- **Pane sidebar inside multi-pane windows.** When the active window already has many splits, opening a sidebar squeezes everything. The toggle UX has to be flawless — copy `tmux-sidebar`'s layout-restore trick exactly.
- **Concurrent writers.** Two agents in two panes both calling `agentbar set-status` race on the same option. tmux's option setter is atomic per call but not per logical update. Use namespaced keys (`@ab_status_<pane_id>_<key>`) when callers want pane-scoped pills.

## 8. Features

### v0.1.0

- CLI
- user-option storage
- basic sidebar pane TUI showing per-window cwd, branch, one status pill, unread badge.
- `agentbar notify`.
- TPM install.
- Bash/zsh prompt hook for command
- Claude Code / Codex / OpenCode hook templates

### v0.2.0

- Progress bars (with agent cooperation),
- Agent SKILL.md for use of progress bars/advanced features.
- `set-hook`-driven redraw,

### v0.3.0

- `agentbar dump`/`restore`,
- TODO: Propose additional here

## 9. Naming and licensing

- Suggested name: **`tmux-agentbar`** (emphasises the agent-status-bar purpose, avoids confusion with the directory-listing `tmux-sidebar`).
- License: MIT
