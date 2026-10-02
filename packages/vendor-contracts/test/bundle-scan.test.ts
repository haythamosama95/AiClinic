import { execFileSync } from "node:child_process";
import {
  mkdtempSync,
  readFileSync,
  readdirSync,
  readFile,
  statSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { describe, expect, it } from "vitest";

const readFileAsync = promisify(readFile);

const TESTKIT_MARKER = "vendor-contracts-testkit";
const packageRoot = path.resolve(import.meta.dirname, "..");
const aiPlatformRoot = path.resolve(packageRoot, "../../ai-platform");

function readPackageExports(): Record<string, string> {
  const packageJsonPath = path.join(packageRoot, "package.json");
  const packageJson = JSON.parse(readFileSync(packageJsonPath, "utf8")) as {
    exports?: Record<string, string>;
  };
  return packageJson.exports ?? {};
}

async function collectBundleText(outDir: string): Promise<string> {
  const chunks: string[] = [];

  async function walk(dir: string): Promise<void> {
    for (const entry of readdirSync(dir)) {
      const fullPath = path.join(dir, entry);
      const stats = statSync(fullPath);
      if (stats.isDirectory()) {
        await walk(fullPath);
        continue;
      }
      chunks.push(await readFileAsync(fullPath, "utf8"));
    }
  }

  await walk(outDir);
  return chunks.join("\n");
}

describe("production bundle scan", () => {
  it("E2E-P2.2-08 A production ai-platform bundle contains no testkit code", async () => {
    const exportsMap = readPackageExports();
    expect(exportsMap["./testkit"], "package.json exports ./testkit").toEqual(
      "./src/testkit/index.ts",
    );

    const outDir = mkdtempSync(path.join(tmpdir(), "abo-p22-bundle-"));
    const wranglerBin = fileURLToPath(
      new URL("../node_modules/wrangler/bin/wrangler.js", import.meta.url),
    );

    execFileSync(
      process.execPath,
      [
        wranglerBin,
        "deploy",
        "--dry-run",
        "--outdir",
        outDir,
        "--env",
        "production",
      ],
      { cwd: aiPlatformRoot, stdio: "pipe", encoding: "utf8" },
    );

    const bundleText = await collectBundleText(outDir);
    expect(bundleText).not.toContain(TESTKIT_MARKER);
  });
});
