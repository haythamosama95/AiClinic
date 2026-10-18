/**
 * R8-LEGACY1 — executable metadata must not point to the deleted
 * `ai-platform/scripts/bootstrap-routing-policy.sh` (removed in spec 093;
 * the Access-checked routing-policy relays replace it).
 */

import { existsSync, readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const packageJson = JSON.parse(
  readFileSync(new URL("../package.json", import.meta.url), "utf8"),
) as {
  scripts?: Record<string, string>;
};

describe("package executable metadata", () => {
  it("R8-LEGACY1 no script references the deleted bootstrap-routing-policy script", () => {
    const scripts = packageJson.scripts ?? {};
    for (const [name, command] of Object.entries(scripts)) {
      expect(name).not.toContain("bootstrap-routing-policy");
      expect(command).not.toContain("bootstrap-routing-policy");
    }
    expect(scripts["bootstrap:routing-policy"]).toBeUndefined();
  });

  it("R8-LEGACY1 every shell script referenced by an npm script exists", () => {
    const scripts = packageJson.scripts ?? {};
    const referenced: Array<{ script: string; file: string }> = [];
    for (const [name, command] of Object.entries(scripts)) {
      const match = /(?:^|[ &])([\w./-]*scripts\/[\w./-]+\.(?:sh|py|mjs|js))\b/u.exec(
        command,
      );
      if (match !== null) {
        referenced.push({ script: name, file: match[1]! });
      }
    }
    for (const entry of referenced) {
      expect(
        existsSync(new URL(`../${entry.file}`, import.meta.url)),
        `npm script "${entry.script}" references missing file ${entry.file}`,
      ).toBe(true);
    }
  });
});
