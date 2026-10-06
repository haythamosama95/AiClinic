import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const aboRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
);
const scriptPath = path.join(aboRoot, "scripts", "check-import-boundary.mjs");
const badFixtureRoot = path.join(
  aboRoot,
  "test",
  "fixtures",
  "import-boundary",
  "bad",
);

test("E2E-P4.2-09 domain import of the adapter fails the boundary check", () => {
  const result = spawnSync(process.execPath, [scriptPath, badFixtureRoot], {
    cwd: aboRoot,
    encoding: "utf8",
  });
  assert.equal(result.status, 1, result.stderr || result.stdout);
});
