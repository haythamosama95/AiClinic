import { existsSync, readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const EVAL_ROOT = path.dirname(fileURLToPath(import.meta.url));
const AI_PLATFORM_ROOT = path.resolve(EVAL_ROOT, "..", "..");
const REPO_ROOT = path.resolve(AI_PLATFORM_ROOT, "..");
const FRONTEND_LIB = path.join(REPO_ROOT, "frontend", "lib");

const FORBIDDEN_CLIENT_PATTERNS = [
  /deepseek/i,
  /gemini/i,
  /deepseek-chat/,
  /deepseek-v4-flash/,
  /gemini-1\.5-flash/,
  /gemini-3\.5-flash/,
  /clinical documentation assistant/i,
  /You are a clinical documentation assistant/i,
];

function listFilesRecursive(dir: string): string[] {
  if (!existsSync(dir)) {
    return [];
  }
  const entries = readdirSync(dir, { withFileTypes: true });
  const files: string[] = [];
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...listFilesRecursive(fullPath));
    } else if (entry.isFile() && entry.name.endsWith(".dart")) {
      files.push(fullPath);
    }
  }
  return files;
}

describe("T7 no_prompt_text_in_flutter_client", () => {
  it("introduces no Flutter client files carrying prompt text, provider names, or model identifiers", () => {
    const evalPaths = [
      path.join(EVAL_ROOT, "harness.ts"),
      path.join(EVAL_ROOT, "score-report.ts"),
      path.join(EVAL_ROOT, "golden.test.ts"),
      path.join(EVAL_ROOT, "live-smoke.test.ts"),
      path.join(EVAL_ROOT, "prohibitions.test.ts"),
    ];

    for (const evalPath of evalPaths) {
      expect(evalPath.startsWith(AI_PLATFORM_ROOT)).toBe(true);
      expect(evalPath.includes("frontend")).toBe(false);
    }

    const frontendEvalPaths = listFilesRecursive(path.join(FRONTEND_LIB, "eval"));
    expect(frontendEvalPaths).toEqual([]);

    const promptArtifacts = path.join(EVAL_ROOT, "prompts");
    for (const file of listFilesRecursive(promptArtifacts)) {
      expect(file.startsWith(EVAL_ROOT)).toBe(true);
      expect(file.includes("frontend")).toBe(false);
    }

    for (const file of listFilesRecursive(FRONTEND_LIB)) {
      const source = readFileSync(file, "utf8");
      for (const pattern of FORBIDDEN_CLIENT_PATTERNS) {
        expect(source).not.toMatch(pattern);
      }
    }
  });
});

describe("T8 harness_holds_no_per_request_server_state", () => {
  it("keeps eval tooling under test/eval with no src/eval module or request-path store", () => {
    expect(existsSync(path.join(AI_PLATFORM_ROOT, "src", "eval"))).toBe(false);
    expect(existsSync(path.join(EVAL_ROOT, "harness.ts"))).toBe(true);
    expect(existsSync(path.join(EVAL_ROOT, "score-report.ts"))).toBe(true);

    const harnessSource = readFileSync(path.join(EVAL_ROOT, "harness.ts"), "utf8");
    expect(harnessSource).not.toMatch(/\bD1Database\b/);
    expect(harnessSource).not.toMatch(/\bR2Bucket\b/);
    expect(harnessSource).not.toMatch(/\bDurableObject\b/);
    expect(harnessSource).not.toContain("src/eval");
  });
});

const CONVERSATION_MODULE_PATHS = [
  path.join(EVAL_ROOT, "conversation-harness.ts"),
  path.join(EVAL_ROOT, "conversation-score-report.ts"),
  path.join(EVAL_ROOT, "conversation.test.ts"),
  path.join(EVAL_ROOT, "clinic.chat_assistant"),
];

describe("no_prompt_text_in_flutter_client", () => {
  it("conversation module files introduce no Flutter client prompt, provider, or model strings", () => {
    for (const modulePath of CONVERSATION_MODULE_PATHS) {
      expect(existsSync(modulePath)).toBe(true);
      expect(modulePath.startsWith(AI_PLATFORM_ROOT)).toBe(true);
      expect(modulePath.includes("frontend")).toBe(false);
    }

    const dartFilesUnderEval: string[] = [];
    for (const modulePath of CONVERSATION_MODULE_PATHS) {
      if (modulePath.endsWith(".dart")) {
        dartFilesUnderEval.push(modulePath);
      }
    }
    expect(dartFilesUnderEval).toEqual([]);

    const scanTargets = [
      path.join(EVAL_ROOT, "conversation-harness.ts"),
      path.join(EVAL_ROOT, "conversation-score-report.ts"),
      path.join(EVAL_ROOT, "conversation.test.ts"),
    ];
    for (const filePath of scanTargets) {
      const source = readFileSync(filePath, "utf8");
      for (const pattern of FORBIDDEN_CLIENT_PATTERNS) {
        expect(source).not.toMatch(pattern);
      }
    }

    for (const file of listFilesRecursive(FRONTEND_LIB)) {
      const source = readFileSync(file, "utf8");
      for (const pattern of FORBIDDEN_CLIENT_PATTERNS) {
        expect(source).not.toMatch(pattern);
      }
    }
  });
});

describe("harness_holds_no_per_request_server_state", () => {
  it("conversation harness remains CI tooling with no per-request server-side state", () => {
    expect(existsSync(path.join(AI_PLATFORM_ROOT, "src", "eval"))).toBe(false);

    const conversationHarnessPath = path.join(
      EVAL_ROOT,
      "conversation-harness.ts",
    );
    expect(existsSync(conversationHarnessPath)).toBe(true);

    const harnessSource = readFileSync(conversationHarnessPath, "utf8");
    expect(harnessSource).not.toMatch(/\bD1Database\b/);
    expect(harnessSource).not.toMatch(/\bR2Bucket\b/);
    expect(harnessSource).not.toMatch(/\bDurableObject\b/);
    expect(harnessSource).not.toMatch(/\bKVNamespace\b/);
    expect(harnessSource).not.toContain("src/eval");
    expect(
      path
        .normalize(conversationHarnessPath)
        .includes(path.normalize(path.join("test", "eval"))),
    ).toBe(true);
  });
});
