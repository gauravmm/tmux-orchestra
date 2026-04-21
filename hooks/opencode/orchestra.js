export const OrchestraPlugin = async ({ $ }) => {
  let pendingTools = 0;

  return {
    "tool.execute.before": async (input, output) => {
      pendingTools++;
      await $`orchestra set-state running --action ${input.tool}`.nothrow();
    },

    "tool.execute.after": async (input, output) => {
      pendingTools = Math.max(0, pendingTools - 1);
      if (pendingTools === 0) {
        await $`orchestra set-state done && orchestra clear-state`.nothrow();
      }
    },

    "permission.ask": async (input, output) => {
      const action = input.title || input.type || "permission";
      await $`orchestra set-state waiting --action ${action}`.nothrow();
    },

    event: async ({ event }) => {
      if (event.type === "session.idle") {
        pendingTools = 0;
        await $`orchestra set-state done && orchestra clear-state`.nothrow();
      }
    },
  };
};
