#!/usr/bin/env node
/**
 * G6 import boundary: only adapter.ts imports paymob client; adapter stays inside provider/.
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const aboRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

const ADAPTER_SUFFIX = path.normalize("provider/paymob/adapter");
const CLIENT_SUFFIX = path.normalize("provider/paymob/client");

const SOURCE_EXTENSIONS = new Set([".ts", ".js", ".mts", ".mjs"]);

function usage() {
  process.stderr.write(
    "Usage: node scripts/check-import-boundary.mjs <tree-root>\n",
  );
}

function walkSourceFiles(rootDir) {
  const files = [];
  if (!fs.existsSync(rootDir)) {
    return files;
  }
  const stack = [rootDir];
  while (stack.length > 0) {
    const current = stack.pop();
    const entries = fs.readdirSync(current, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(fullPath);
        continue;
      }
      const ext = path.extname(entry.name);
      if (SOURCE_EXTENSIONS.has(ext)) {
        files.push(fullPath);
      }
    }
  }
  return files;
}

function normalizeSpecifier(specifier) {
  return specifier.replace(/\\/g, "/").replace(/\.(ts|js|mts|mjs)$/u, "");
}

function classifyImport(specifier) {
  const normalized = normalizeSpecifier(specifier);
  if (
    normalized.endsWith(CLIENT_SUFFIX) ||
    normalized.includes("/provider/paymob/client")
  ) {
    return "client";
  }
  if (
    normalized.endsWith(ADAPTER_SUFFIX) ||
    normalized.includes("/provider/paymob/adapter")
  ) {
    return "adapter";
  }
  return null;
}

function extractImportSpecifiers(source) {
  const specifiers = [];
  const staticImport =
    /\bfrom\s+["']([^"']+)["']/gu;
  const dynamicImport =
    /\bimport\s*\(\s*["']([^"']+)["']\s*\)/gu;
  for (const match of source.matchAll(staticImport)) {
    specifiers.push(match[1]);
  }
  for (const match of source.matchAll(dynamicImport)) {
    specifiers.push(match[1]);
  }
  return specifiers;
}

function isAdapterFile(filePath) {
  const normalized = filePath.replace(/\\/g, "/");
  return normalized.endsWith("/provider/paymob/adapter.ts");
}

function isUnderProviderDir(filePath, scanRoot) {
  const relative = path.relative(scanRoot, filePath).replace(/\\/g, "/");
  if (relative.startsWith("..")) {
    const normalized = filePath.replace(/\\/g, "/");
    return normalized.includes("/provider/");
  }
  return relative.startsWith("provider/");
}

function resolveScanRoot(argument) {
  const resolved = path.isAbsolute(argument)
    ? argument
    : path.resolve(aboRoot, argument);
  const srcChild = path.join(resolved, "src");
  if (fs.existsSync(srcChild) && fs.statSync(srcChild).isDirectory()) {
    return srcChild;
  }
  return resolved;
}

function main() {
  const argument = process.argv[2];
  if (!argument) {
    usage();
    process.exit(2);
  }

  const scanRoot = resolveScanRoot(argument);
  const violations = [];

  for (const filePath of walkSourceFiles(scanRoot)) {
    const source = fs.readFileSync(filePath, "utf8");
    for (const specifier of extractImportSpecifiers(source)) {
      const kind = classifyImport(specifier);
      if (kind === "client" && !isAdapterFile(filePath)) {
        violations.push(
          `${filePath}: imports paymob client (${specifier}) outside adapter`,
        );
      }
      if (kind === "adapter" && !isUnderProviderDir(filePath, scanRoot)) {
        violations.push(
          `${filePath}: imports paymob adapter (${specifier}) outside provider/`,
        );
      }
    }
  }

  if (violations.length > 0) {
    for (const line of violations) {
      process.stderr.write(`${line}\n`);
    }
    process.exit(1);
  }

  process.exit(0);
}

main();
