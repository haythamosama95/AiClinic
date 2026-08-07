import type { EntityDef } from "./types";
import { requireValue } from "./types";

export const E2E_ENTITIES: EntityDef[] = [
  {
    id: "e2e.health",
    category: "e2e",
    title: "Health",
    description: "GET /health via gateway proxy.",
    mode: "proxy",
    fields: [],
    buildRequest: () => ({
      mode: "proxy",
      method: "GET",
      path: "/health",
      auth: "none",
    }),
  },
  {
    id: "e2e.verify-manifests",
    category: "e2e",
    title: "Verify manifests / prompt pins",
    description: "Subprocess: npm run verify-manifests in ai-platform.",
    mode: "subprocess",
    fields: [],
    buildRequest: () => ({
      mode: "subprocess",
      script: "npm",
      args: ["run", "verify-manifests"],
      cwd: "ai-platform",
    }),
  },
  {
    id: "e2e.golden-suite",
    category: "e2e",
    title: "Golden eval suite",
    description:
      "Subprocess: vitest run test/eval/golden.test.ts (Node pool).",
    mode: "subprocess",
    fields: [
      {
        name: "filter",
        label: "vitest -t filter (optional)",
        kind: "text",
        placeholder: "happy_path",
      },
    ],
    buildRequest: (values) => {
      const args = ["run", "test/eval/golden.test.ts"];
      if (values.filter?.trim()) {
        args.push("-t", values.filter.trim());
      }
      return {
        mode: "subprocess",
        script: "npx",
        args: ["vitest", ...args],
        cwd: "ai-platform",
      };
    },
  },
  {
    id: "e2e.conversation-suite",
    category: "e2e",
    title: "Conversation eval suite",
    description: "Subprocess: vitest run test/eval/conversation.test.ts",
    mode: "subprocess",
    fields: [
      {
        name: "filter",
        label: "vitest -t filter (optional)",
        kind: "text",
      },
    ],
    buildRequest: (values) => {
      const args = ["run", "test/eval/conversation.test.ts"];
      if (values.filter?.trim()) {
        args.push("-t", values.filter.trim());
      }
      return {
        mode: "subprocess",
        script: "npx",
        args: ["vitest", ...args],
        cwd: "ai-platform",
      };
    },
  },
  {
    id: "e2e.live-smoke",
    category: "e2e",
    title: "Live smoke",
    description:
      "Subprocess: vitest run test/eval/live-smoke.test.ts — needs provider keys in env.",
    mode: "subprocess",
    dangerous: true,
    fields: [
      {
        name: "filter",
        label: "vitest -t filter (optional)",
        kind: "text",
      },
    ],
    buildRequest: (values) => {
      const args = ["run", "test/eval/live-smoke.test.ts"];
      if (values.filter?.trim()) {
        args.push("-t", values.filter.trim());
      }
      return {
        mode: "subprocess",
        script: "npx",
        args: ["vitest", ...args],
        cwd: "ai-platform",
      };
    },
  },
  {
    id: "e2e.support-lookup",
    category: "e2e",
    title: "Support lookup (operator)",
    description: "POST /control/support/lookup?reference=",
    mode: "proxy",
    fields: [
      {
        name: "reference",
        label: "reference",
        kind: "text",
        required: true,
      },
    ],
    buildRequest: (values) => ({
      mode: "proxy",
      method: "POST",
      path: `/control/support/lookup?reference=${encodeURIComponent(requireValue(values, "reference"))}`,
      auth: "operator",
    }),
  },
  {
    id: "e2e.unit-suite",
    category: "e2e",
    title: "Unit suite",
    description: "Subprocess: npm run test:unit in ai-platform.",
    mode: "subprocess",
    fields: [
      {
        name: "filter",
        label: "vitest -t filter (optional)",
        kind: "text",
      },
    ],
    buildRequest: (values) => {
      if (values.filter?.trim()) {
        return {
          mode: "subprocess",
          script: "npx",
          args: ["vitest", "run", "-t", values.filter.trim()],
          cwd: "ai-platform",
        };
      }
      return {
        mode: "subprocess",
        script: "npm",
        args: ["run", "test:unit"],
        cwd: "ai-platform",
      };
    },
  },
];
