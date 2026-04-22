import { which } from "bun";

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

  const resolveWindow = async () => {
    const explicitWindow = trim(process.env.ORCHESTRA_WINDOW_ID);
    if (explicitWindow) {
      return explicitWindow;
    }

    const pane = trim(process.env.TMUX_PANE);
    if (pane) {
      const paneWindow = await tmux`tmux display-message -p -t ${pane} '#{window_id}'`;
      if (paneWindow) {
        return paneWindow;
      }
    }

    if (trim(process.env.TMUX)) {
      const paths = [directory, worktree].map(trim).filter(Boolean);
      if (paths.length > 0) {
        const windows = await tmux`tmux list-windows -F '#{window_id}|#{pane_current_path}|#{@ab_cwd}'`;
        if (windows) {
          for (const line of windows.split("\n")) {
            const [windowID, panePath, cwd] = line.split("|");
            if (!windowID) {
              continue;
            }
            if (paths.includes(trim(panePath)) || paths.includes(trim(cwd))) {
              return trim(windowID);
            }
          }
        }
      }

      const activeWindow = await tmux`tmux display-message -p '#{window_id}'`;
      if (activeWindow) {
        return activeWindow;
      }
    }

    return "";
  };

  const targetWindow = await resolveWindow();

  const run = async (pieces, ...values) => {
    try {
      await $(pieces, ...values).quiet().nothrow();
    } catch {
      // ignore — orchestra is best-effort
    }
  };

  const runState = async (state, action = "") => {
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
    if (targetWindow) {
      await run`${orchestra} clear-state --window ${targetWindow}`;
      return;
    }
    await run`${orchestra} clear-state`;
  };

  return {
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
    },

    event: async ({ event }) => {
      if (event.type === "session.idle") {
        pendingTools = 0;
        await runState("done");
        await clearState();
      }
    },
  };
};
