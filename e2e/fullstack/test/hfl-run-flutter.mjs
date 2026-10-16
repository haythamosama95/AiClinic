#!/usr/bin/env node

import { spawn } from "node:child_process";
import { setTimeout as delay } from "node:timers/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  ABO_URL,
  HARNESS_URL,
  PAYMOB_URL,
  PLATFORM_URL,
  seedAboOffers,
  seedPlatformGrantGlobals,
  startStack,
  SUPABASE_URL,
} from "./p7-3-stack.mjs";

const REPO_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../..",
);
const FRONTEND_ROOT = path.join(REPO_ROOT, "frontend");
const ACCEPTED_SUPABASE_STATUSES = new Set([200, 401, 404]);
const SIGNAL_EXIT_CODES = { SIGINT: 130, SIGTERM: 143 };

let stack = null;
let stackStartup = null;
let child = null;
let flutterPid = null;
let requestedSignal = null;
let cleanupPromise = null;
const signalHandlers = new Map();

const workerUrls = [PLATFORM_URL, ABO_URL, PAYMOB_URL, HARNESS_URL];

async function requireSupabaseReady() {
  let response;
  try {
    response = await fetch(`${SUPABASE_URL.replace(/\/$/, "")}/rest/v1/`, {
      signal: AbortSignal.timeout(3000),
    });
  } catch (error) {
    throw new Error(
      `Local Supabase is unavailable at ${SUPABASE_URL}. Start it with ` +
        "`supabase start` in backend/ before running the frontend fullstack campaign.",
      { cause: error },
    );
  }

  if (!ACCEPTED_SUPABASE_STATUSES.has(response.status)) {
    throw new Error(
      `Local Supabase at ${SUPABASE_URL} returned HTTP ${response.status}; ` +
        "the frontend fullstack campaign requires the local Supabase stack.",
    );
  }
}

async function rejectExistingWorkers() {
  const responding = [];
  for (const url of workerUrls) {
    try {
      await fetch(url, { signal: AbortSignal.timeout(500) });
      responding.push(url);
    } catch {
      // A refused or timed-out connection is available for this owned stack.
    }
  }
  if (responding.length > 0) {
    throw new Error(
      `H-FS worker ports are already in use (${responding.join(", ")}). ` +
        "Stop the existing stack before running the managed frontend fullstack campaign.",
    );
  }
}

function runFlutter(command, args) {
  return new Promise((resolve, reject) => {
    child = spawn(command, args, {
      cwd: FRONTEND_ROOT,
      env: process.env,
      stdio: "inherit",
      detached: process.platform !== "win32",
    });
    flutterPid = child.pid ?? null;
    child.once("error", reject);
    child.once("close", (code, signal) => {
      child = null;
      if (signal && !requestedSignal) {
        resolve(128 + (signal === "SIGINT" ? 2 : 15));
        return;
      }
      resolve(code ?? 1);
    });
  });
}

function signalFlutter(signal) {
  if (process.platform !== "win32" && flutterPid) {
    try {
      process.kill(-flutterPid, signal);
      return true;
    } catch (error) {
      if (error.code === "ESRCH") return false;
      throw error;
    }
  }
  if (!child) return false;
  if (child.exitCode !== null || child.signalCode !== null) return false;
  return child.kill(signal);
}

function flutterProcessGroupExists() {
  if (!flutterPid) return false;
  try {
    process.kill(-flutterPid, 0);
    return true;
  } catch (error) {
    if (error.code === "ESRCH") return false;
    throw error;
  }
}

async function stopFlutter() {
  if (process.platform !== "win32" && flutterPid) {
    signalFlutter("SIGTERM");
    const waitForGroupExit = async (timeoutMs) => {
      const deadline = Date.now() + timeoutMs;
      while (flutterProcessGroupExists() && Date.now() < deadline) {
        await delay(100);
      }
      return !flutterProcessGroupExists();
    };
    if (await waitForGroupExit(5_000)) {
      flutterPid = null;
      return;
    }
    signalFlutter("SIGKILL");
    if (!(await waitForGroupExit(1_000))) {
      throw new Error(`Flutter process group ${flutterPid} did not exit after SIGKILL`);
    }
    flutterPid = null;
    return;
  }
  if (!child) return;
  if (process.platform === "win32") {
    if (child.exitCode !== null || child.signalCode !== null) return;
    child.kill("SIGTERM");
    await new Promise((resolve) => {
      const timer = setTimeout(() => {
        child?.kill("SIGKILL");
        resolve();
      }, 5_000);
      child.once("close", () => {
        clearTimeout(timer);
        resolve();
      });
    });
    return;
  }

}

function requestShutdown(signal) {
  if (requestedSignal) return;
  requestedSignal = signal;
  try {
    signalFlutter(signal);
  } catch (error) {
    console.error(`Failed to signal Flutter after ${signal}:`, error);
  } finally {
    // Start cleanup now; the Flutter child may retain inherited stdio through
    // descendants and therefore never emit `close` on its own.
    void stopStack().catch((error) => {
      console.error("H-FS shutdown failed:", error);
    });
  }
}

function registerSignalHandlers() {
  for (const signal of Object.keys(SIGNAL_EXIT_CODES)) {
    const handler = () => requestShutdown(signal);
    signalHandlers.set(signal, handler);
    process.on(signal, handler);
  }
}

function removeSignalHandlers() {
  for (const [signal, handler] of signalHandlers) {
    process.off(signal, handler);
  }
  signalHandlers.clear();
}

async function stopStack() {
  if (!cleanupPromise) {
    cleanupPromise = (async () => {
      if (stackStartup) {
        try {
          await stackStartup;
        } catch {
          // startStack rolls back its own partial resources on failure.
        }
      }
      await stopFlutter();
      if (stack) {
        const activeStack = stack;
        stack = null;
        await activeStack.stop();
      }
    })();
  }
  return cleanupPromise;
}

async function main() {
  const separator = process.argv.indexOf("--");
  const commandArgs = separator === -1 ? [] : process.argv.slice(separator + 1);
  if (commandArgs.length === 0) {
    throw new Error("Usage: hfl-run-flutter.mjs -- <flutter command and arguments>");
  }

  registerSignalHandlers();
  let exitCode = 1;
  try {
    await requireSupabaseReady();
    if (requestedSignal) {
      exitCode = SIGNAL_EXIT_CODES[requestedSignal];
    } else {
      await rejectExistingWorkers();
      stackStartup = startStack({ createClinics: false, registerIssuer: false }).then(
        (startedStack) => {
          stack = startedStack;
          return startedStack;
        },
      );
      try {
        await stackStartup;
      } finally {
        stackStartup = null;
      }
      if (requestedSignal) {
        exitCode = SIGNAL_EXIT_CODES[requestedSignal];
      } else {
        await seedAboOffers();
        seedPlatformGrantGlobals();
        exitCode = await runFlutter(commandArgs[0], commandArgs.slice(1));
      }
    }
  } finally {
    await stopStack();
    removeSignalHandlers();
  }

  if (requestedSignal) {
    exitCode = SIGNAL_EXIT_CODES[requestedSignal];
  }
  return exitCode;
}

main()
  .then((code) => {
    process.exitCode = code;
  })
  .catch(async (error) => {
    console.error(error instanceof Error ? error.message : error);
    try {
      await stopStack();
    } catch (cleanupError) {
      console.error("H-FS worker cleanup failed:", cleanupError);
    }
    removeSignalHandlers();
    process.exitCode = 1;
  });
