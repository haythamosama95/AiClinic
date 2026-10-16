/**
 * Build gate: npm run verify-manifests → this file (with manifest-registry-gate).
 * Fails CI when registry pins drift from indexed/disk prompt artifacts, or when a
 * published capability manifest pins missing/altered prompt refs.
 */
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { load } from "../src/manifest";
import {
  allRegistryPins,
  indexedArtifactContent,
  stableContentHash,
  verifyAllRegistryPins,
  verifyBuildPins,
} from "../src/prompt/registry";

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const PROMPTS_DIR = path.join(ROOT, "prompts");
const PUBLISHED_DIR = path.join(ROOT, "manifests", "published");

function listMarkdownArtifacts(dir: string): string[] {
  const results: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...listMarkdownArtifacts(full));
    } else if (entry.isFile() && entry.name.endsWith(".md")) {
      results.push(full);
    }
  }
  return results;
}

function diskPathToRef(absolutePath: string): string {
  const relative = path
    .relative(PROMPTS_DIR, absolutePath)
    .split(path.sep)
    .join("/");
  if (!relative.endsWith(".md")) {
    throw new Error(`Expected .md path: ${absolutePath}`);
  }
  return `${relative.slice(0, -".md".length)}@v1`;
}

describe("prompt-registry build gate", () => {
  it("verifyAllRegistryPins passes for every prompts/*/registry.json pin", () => {
    expect(() => verifyAllRegistryPins()).not.toThrow();
  });

  it("disk bytes hash equals registry pin and indexed ?raw content", () => {
    const pins = allRegistryPins();
    const mdFiles = listMarkdownArtifacts(PROMPTS_DIR);
    expect(mdFiles.length).toBeGreaterThan(0);
    expect(Object.keys(pins).length).toBe(mdFiles.length);

    for (const filePath of mdFiles) {
      const ref = diskPathToRef(filePath);
      const disk = readFileSync(filePath, "utf8");
      const diskHash = stableContentHash(disk);
      const pin = pins[ref];
      expect(pin, `registry pin missing for ${ref}`).toBeDefined();
      expect(diskHash).toBe(pin);

      const indexed = indexedArtifactContent(ref);
      expect(indexed, `indexed content missing for ${ref}`).toBeDefined();
      expect(stableContentHash(indexed!)).toBe(pin);
      expect(indexed).toBe(disk);
    }
  });

  it("verifyBuildPins passes for each published capability with prompt bindings", () => {
    const names = readdirSync(PUBLISHED_DIR).filter((name) =>
      name.endsWith(".json"),
    );
    expect(names.length).toBeGreaterThan(0);

    for (const name of names) {
      const json = JSON.parse(
        readFileSync(path.join(PUBLISHED_DIR, name), "utf8"),
      ) as Record<string, unknown>;
      if (!Object.hasOwn(json, "Prompt binding")) {
        continue;
      }
      const manifest = load(json);
      expect(() => verifyBuildPins(manifest)).not.toThrow();
    }
  });
});
