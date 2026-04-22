import { which } from "bun";

export const OrchestraPlugin = async ({ $, directory }) => {
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

  const run = async (pieces, ...values) => {
    try {
      await $(pieces, ...values).quiet().nothrow();
    } catch {
      // ignore — orchestra is best-effort
    }
  };

  return {
    "tool.execute.before": async (input, output) => {
      pendingTools++;
      await run`${orchestra} set-state running --spinner opencode --action ${input.tool}`;
    },

    "tool.execute.after": async (input, output) => {
      pendingTools = Math.max(0, pendingTools - 1);
      if (pendingTools === 0) {
        // Tool finished, but LLM is still processing results.
        // Stay in "running" until the response is fully generated.
        await run`${orchestra} set-state running --spinner opencode`;
      }
    },

    "permission.ask": async (input, output) => {
      const action = input.title || input.type || "permission";
      await run`${orchestra} set-state waiting --action ${action}`;
    },

    event: async ({ event }) => {
      if (event.type === "session.idle") {
        pendingTools = 0;
        await run`${orchestra} set-state done`;
        await run`${orchestra} clear-state`;
      }
    },
  };
};
