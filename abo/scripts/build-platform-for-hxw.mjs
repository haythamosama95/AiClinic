#!/usr/bin/env node
/**
 * Bundle the ai-platform worker for the H-XW cross-worker vitest harness.
 */

import { execSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "../..");
const platformDir = path.join(repoRoot, "ai-platform");
const outDir = path.join(platformDir, "dist/hxw");

execSync(
  "npx wrangler deploy --dry-run --outdir dist/hxw --env development",
  {
    cwd: platformDir,
    stdio: "inherit",
    env: process.env,
  },
);

console.log(`Platform bundle written under ${outDir}/worker.js`);
