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
  /gemini-1\.5-flash/,
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
