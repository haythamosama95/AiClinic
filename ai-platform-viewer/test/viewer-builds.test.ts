import { execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

describe("viewer_builds", () => {
  it("E2E-P7.1-03", () => {
    const viewerRoot = path.resolve(import.meta.dirname, "..");
    const repoRoot = path.resolve(viewerRoot, "..");
    const guardScript = path.join(
      repoRoot,
      ".github/scripts/control-residue-guard.sh",
    );
    const distPath = path.join(viewerRoot, "dist");

    execSync("npm run build", { cwd: viewerRoot, stdio: "inherit" });
    expect(fs.existsSync(distPath)).toBe(true);

    execSync(`bash "${guardScript}" "${distPath}"`, {
      cwd: repoRoot,
      stdio: "inherit",
    });
  });
});
