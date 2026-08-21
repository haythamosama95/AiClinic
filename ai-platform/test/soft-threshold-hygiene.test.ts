import { readdirSync, readFileSync } from "node:fs";
import { join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import * as softThreshold from "../src/soft-threshold";

const ROOT = resolve(fileURLToPath(new URL("..", import.meta.url)));
const SRC_ROOT = join(ROOT, "src");

function collectTsFiles(dir: string): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...collectTsFiles(full));
    } else if (entry.name.endsWith(".ts")) {
      out.push(full);
    }
  }
  return out;
}

describe("client routing-injection guard is test-only", () => {
  it("does not keep bodyHasClientRoutingInjection in production src", () => {
    const offenders: string[] = [];
    for (const file of collectTsFiles(SRC_ROOT)) {
      const source = readFileSync(file, "utf8");
      if (/\bbodyHasClientRoutingInjection\b/.test(source)) {
        offenders.push(relative(SRC_ROOT, file).split(sep).join("/"));
      }
    }
    expect(offenders).toEqual([]);
    expect("bodyHasClientRoutingInjection" in softThreshold).toBe(false);
  });
});
