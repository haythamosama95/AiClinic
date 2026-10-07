#!/usr/bin/env node
/**
 * Operator wrapper for FM-19 ABO rebuild. Pass provider transaction references
 * copied from the provider dashboard export as positional arguments.
 */

import path from "node:path";
import { fileURLToPath } from "node:url";
import { getPlatformProxy } from "wrangler";
import { rebuildAbo, type RebuildEnv } from "../src/rebuild.js";
import type { Env } from "../src/worker.js";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const aboRoot = path.resolve(scriptDir, "..");

function printUsage(): void {
  process.stdout.write(
    "Usage: npx tsx scripts/rebuild-abo.ts [--env <name>] <provider-transaction-reference> ...\n\n" +
      "  Pass provider transaction references copied from the provider dashboard export.\n" +
      "  Run from the abo/ directory after emptying D1 per REBUILD.md.\n",
  );
}

function parseArgs(argv: string[]): {
  environment: string | undefined;
  providerTransactionReferences: string[];
} {
  const providerTransactionReferences: string[] = [];
  let environment: string | undefined;

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--env" || arg === "-e") {
      const value = argv[index + 1];
      if (value === undefined) {
        throw new Error(`Missing value for ${arg}`);
      }
      environment = value;
      index += 1;
      continue;
    }
    if (arg === "--help" || arg === "-h") {
      printUsage();
      process.exit(0);
    }
    if (arg.startsWith("-")) {
      throw new Error(`Unknown option: ${arg}`);
    }
    providerTransactionReferences.push(arg);
  }

  return { environment, providerTransactionReferences };
}

async function main(): Promise<void> {
  const { environment, providerTransactionReferences } = parseArgs(
    process.argv.slice(2),
  );

  const { env, dispose } = await getPlatformProxy<Env>({
    configPath: path.join(aboRoot, "wrangler.toml"),
    environment,
    remoteBindings: true,
  });

  try {
    await rebuildAbo(env as RebuildEnv, {
      providerTransactionReferences,
    });
    process.stdout.write("rebuildAbo finished\n");
  } finally {
    await dispose();
  }
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`rebuild-abo failed: ${message}\n`);
  process.exit(1);
});
