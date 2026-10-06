#!/usr/bin/env node
/**
 * Bundle the ai-platform worker for the H-XW cross-worker vitest harness.
 */

import { execSync } from "node:child_process";
import { cpSync, mkdirSync, rmSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const aboDir = path.resolve(scriptDir, "..");
const repoRoot = path.resolve(aboDir, "..");
const platformDir = path.join(repoRoot, "ai-platform");
const outDir = path.join(platformDir, "dist/hxw");
const harnessOutDir = path.join(aboDir, ".hxw-platform");

execSync(
  "npx wrangler deploy --dry-run --outdir dist/hxw --env development",
  {
    cwd: platformDir,
    stdio: "inherit",
    env: process.env,
  },
);

rmSync(harnessOutDir, { recursive: true, force: true });
mkdirSync(harnessOutDir, { recursive: true });
cpSync(outDir, harnessOutDir, { recursive: true });

console.log(`Platform bundle written under ${outDir}/worker.js`);
console.log(`Harness copy written under ${harnessOutDir}/worker.js`);
