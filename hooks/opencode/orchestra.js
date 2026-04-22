import { which } from "bun";
import { readlinkSync } from "node:fs";

export const id = "tmux-orchestra";

export const OrchestraPlugin = async ({ $, directory, worktree }) => {
  let pendingTools = 0;

  const home = process.env.HOME || "/";
  const candidates = [
    await which("orchestra"),
    `${home}/.tmux/plugins/tmux-orchestra/bin/orchestra`,
    `${home}/.config/tmux/plugins/tmux-orchestra/bin/orchestra`,
  ];
  const orchestra = candidates.find((p) => typeof p === "string" && p.length > 0);

  if (!orchestra) {
    console.warn("[orchestra] Binary not found. Install tmux-orchestra or ensure it is on PATH.");
    return {};
  }

  const trim = (value) => (typeof value === "string" ? value.trim() : "");

  const tmux = async (pieces, ...values) => {
    try {
      return trim(await $(pieces, ...values).quiet().nothrow().text());
    } catch {
      return "";
    }
  };

  const resolveTTY = () => {
    for (const fd of [2, 1, 0]) {
      try {
        const target = trim(readlinkSync(`/proc/self/fd/${fd}`));
        if (target.startsWith("/dev/")) {
          return target;
        }
      } catch {
        // ignore
      }
    }
    return "";
  };

  const launchTTY = resolveTTY();

  const resolveTTYWindow = async () => {
    if (!launchTTY) {
      return "";
    }

    const panes = await tmux`tmux list-panes -a -F '#{window_id}|#{pane_tty}'`;
    if (!panes) {
      return "";
    }

    for (const line of panes.split("\n")) {
      const [windowID, paneTTY] = line.split("|");
      if (trim(paneTTY) === launchTTY) {
        return trim(windowID);
      }
    }

    return "";
  };

  const windowExists = async (windowID) => {
    if (!windowID) {
      return false;
    }
    const actual = await tmux`tmux display-message -p -t ${windowID} '#{window_id}'`;
    return actual === windowID;
  };

  const resolveLaunchWindow = async () => {
    const ttyWindow = await resolveTTYWindow();
    if (ttyWindow) {
      return ttyWindow;
    }

    const pane = trim(process.env.TMUX_PANE);
    if (pane) {
      const paneWindow = await tmux`tmux display-message -p -t ${pane} '#{window_id}'`;
      if (paneWindow) {
        return paneWindow;
      }
    }

    const explicitWindow = trim(process.env.ORCHESTRA_WINDOW_ID);
    if (explicitWindow) {
      return explicitWindow;
    }

    return tmux`tmux display-message -p '#{window_id}'`;
  };

  const launchWindow = await resolveLaunchWindow();

  const resolveWindow = async () => {
    // TMUX_PANE can lag behind after pane moves; pane TTY is a steadier anchor.
    const ttyWindow = await resolveTTYWindow();
    if (ttyWindow) {
      return ttyWindow;
    }

    const pane = trim(process.env.TMUX_PANE);
    if (pane) {
      const paneWindow = await tmux`tmux display-message -p -t ${pane} '#{window_id}'`;
      if (paneWindow) {
        return paneWindow;
      }
    }

    const explicitWindow = trim(process.env.ORCHESTRA_WINDOW_ID);
    if (explicitWindow && await windowExists(explicitWindow)) {
      return explicitWindow;
    }

    if (launchWindow && await windowExists(launchWindow)) {
      return launchWindow;
    }

    const paths = [directory, worktree].map(trim).filter(Boolean);
    if (paths.length > 0) {
      const windows = await tmux`tmux list-windows -F '#{window_id}|#{window_active}|#{pane_current_path}|#{@ab_cwd}'`;
      if (windows) {
        const matches = [];
        for (const line of windows.split("\n")) {
          const [windowID, windowActive, panePath, cwd] = line.split("|");
          if (!windowID) {
            continue;
          }
          if (paths.includes(trim(panePath)) || paths.includes(trim(cwd))) {
            matches.push({
              windowID: trim(windowID),
              windowActive: trim(windowActive),
            });
          }
        }
        if (matches.length > 0) {
          const activeMatch = matches.find((match) => match.windowActive === "1");
          if (activeMatch) {
            return activeMatch.windowID;
          }
          return matches[0].windowID;
        }
      }
    }

    return tmux`tmux display-message -p '#{window_id}'`;
  };

  const run = async (pieces, ...values) => {
    try {
      await $(pieces, ...values).quiet().nothrow();
    } catch {
      // ignore — orchestra is best-effort
    }
  };

  const runState = async (state, action = "") => {
    const targetWindow = await resolveWindow();

    if (state === "running") {
      if (targetWindow && action) {
        await run`${orchestra} set-state running --spinner opencode --action ${action} --window ${targetWindow}`;
        return;
      }
      if (targetWindow) {
        await run`${orchestra} set-state running --spinner opencode --window ${targetWindow}`;
        return;
      }
      if (action) {
        await run`${orchestra} set-state running --spinner opencode --action ${action}`;
        return;
      }
      await run`${orchestra} set-state running --spinner opencode`;
      return;
    }

    if (state === "waiting") {
      if (targetWindow && action) {
        await run`${orchestra} set-state waiting --action ${action} --window ${targetWindow}`;
        return;
      }
      if (targetWindow) {
        await run`${orchestra} set-state waiting --window ${targetWindow}`;
        return;
      }
      if (action) {
        await run`${orchestra} set-state waiting --action ${action}`;
        return;
      }
      await run`${orchestra} set-state waiting`;
      return;
    }

    if (targetWindow) {
      await run`${orchestra} set-state done --window ${targetWindow}`;
      return;
    }
    await run`${orchestra} set-state done`;
  };

  const clearState = async () => {
    const targetWindow = await resolveWindow();
    if (targetWindow) {
      await run`${orchestra} clear-state --window ${targetWindow}`;
      return;
    }
    await run`${orchestra} clear-state`;
  };

  const notify = async (title, body, { quiet = false } = {}) => {
    const targetWindow = await resolveWindow();
    const args = ["notify", "--title", title];
    if (body) {
      args.push("--body", body);
    }
    if (quiet) {
      args.push("--quiet");
    }
    if (targetWindow) {
      args.push("--window", targetWindow);
    }
    await run`${orchestra} ${args}`;
  };

  return {
    "chat.message": async () => {
      await runState("running");
    },

    "tool.execute.before": async (input, output) => {
      pendingTools++;
      await runState("running", input.tool);
    },

    "tool.execute.after": async (input, output) => {
      pendingTools = Math.max(0, pendingTools - 1);
      if (pendingTools === 0) {
        // Tool finished, but LLM is still processing results.
        // Stay in "running" until the response is fully generated.
        await runState("running");
      }
    },

    "permission.ask": async (input, output) => {
      const action = input.title || input.type || "permission";
      await runState("waiting", action);
      await notify("OpenCode", action);
    },

    event: async ({ event }) => {
      if (
        event.type === "session.idle" ||
        event.type === "session.deleted" ||
        event.type === "server.instance.disposed"
      ) {
        pendingTools = 0;
        await runState("done");
        await clearState();
      }
    },
  };
};

export const server = OrchestraPlugin;

export default {
  id,
  server: OrchestraPlugin,
};
