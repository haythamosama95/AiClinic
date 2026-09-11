import { execSync } from "node:child_process";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { InvoicesPage } from "../src/components/InvoicesPage.tsx";
import { PlansPage } from "../src/components/PlansPage.tsx";
import { StageXPage } from "../src/components/StageXPage.tsx";
import { UsageGaugePage } from "../src/components/UsageGaugePage.tsx";

describe("viewer_builds", () => {
  it("viewer_builds", () => {
    void PlansPage;
    void UsageGaugePage;
    void InvoicesPage;
    void StageXPage;

    const viewerRoot = path.resolve(import.meta.dirname, "..");
    execSync("npm run build", { cwd: viewerRoot, stdio: "inherit" });
    expect(true).toBe(true);
  });
});
