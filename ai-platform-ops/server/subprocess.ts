import { spawn } from "node:child_process";
import path from "node:path";
import type { BuiltRequest } from "../src/catalog/types";
import type { OpsRunResult } from "./types";

const SUBPROCESS_TIMEOUT_MS = 5 * 60 * 1000;
const ALLOWED_SCRIPTS = new Set(["npm", "npx"]);
const SHELL_METACHAR_RE = /[;&|`$<>(){}[\]!#*?~\n\r\\]/;

function hasShellMetacharacters(value: string): boolean {
  return SHELL_METACHAR_RE.test(value);
}

function resolveSubprocessCwd(
  repoRoot: string,
  cwd: string | undefined,
): { ok: true; cwd: string } | { ok: false; error: string } {
  const resolved = path.resolve(repoRoot, cwd ?? ".");
  const relative = path.relative(repoRoot, resolved);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    return { ok: false, error: "cwd must stay within the repository root" };
  }
  return { ok: true, cwd: resolved };
}

export async function runSubprocess(
  request: Extract<BuiltRequest, { mode: "subprocess" }>,
  repoRoot: string,
): Promise<OpsRunResult> {
  const started = Date.now();

  if (!ALLOWED_SCRIPTS.has(request.script)) {
    return {
      status: 400,
      contentType: "application/json",
      bodyText: JSON.stringify({
        error: `Script not allowlisted: ${request.script}`,
      }),
      headers: { "content-type": "application/json" },
      durationMs: Date.now() - started,
    };
  }

  const cwdResult = resolveSubprocessCwd(repoRoot, request.cwd);
  if (!cwdResult.ok) {
    return {
      status: 400,
      contentType: "application/json",
      bodyText: JSON.stringify({ error: cwdResult.error }),
      headers: { "content-type": "application/json" },
      durationMs: Date.now() - started,
    };
  }

  const args = request.args ?? [];
  for (const arg of args) {
    if (hasShellMetacharacters(arg)) {
      return {
        status: 400,
        contentType: "application/json",
        bodyText: JSON.stringify({
          error: `Disallowed shell metacharacter in arg: ${arg}`,
        }),
        headers: { "content-type": "application/json" },
        durationMs: Date.now() - started,
      };
    }
  }

  return new Promise((resolve) => {
    const child = spawn(request.script, args, {
      cwd: cwdResult.cwd,
      env: process.env,
      shell: false,
    });

    let stdout = "";
    let stderr = "";
    let settled = false;

    const finish = (status: number, bodyText: string) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      resolve({
        status,
        contentType: "text/plain",
        bodyText,
        headers: { "content-type": "text/plain" },
        durationMs: Date.now() - started,
      });
    };

    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      finish(
        500,
        `${stdout}${stderr}\n\n[ops] subprocess timed out after 5 minutes`,
      );
    }, SUBPROCESS_TIMEOUT_MS);

    child.stdout.on("data", (chunk: Buffer) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk: Buffer) => {
      stderr += chunk.toString();
    });

    child.on("error", (error) => {
      finish(500, `${stdout}${stderr}\n${error.message}`);
    });

    child.on("close", (code) => {
      const combined =
        stdout + (stderr ? (stdout ? "\n" : "") + stderr : "");
      finish(code === 0 ? 200 : 500, combined);
    });
  });
}
