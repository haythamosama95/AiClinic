/**
 * P4.1 — wrangler env clock binding checks (H-ABO).
 */

import { describe, expect, it } from "vitest";
import wranglerToml from "../../wrangler.toml?raw";

describe("wrangler clock config", () => {
  it("P4.1 production and staging wrangler envs carry no TEST_CLOCK", () => {
    const productionBlock = wranglerToml.match(
      /\[env\.production\][\s\S]*?(?=\n\[env\.|$)/u,
    )?.[0];
    const stagingBlock = wranglerToml.match(
      /\[env\.staging\][\s\S]*?(?=\n\[env\.|$)/u,
    )?.[0];
    expect(productionBlock).toBeDefined();
    expect(stagingBlock).toBeDefined();
    expect(productionBlock).not.toMatch(/TEST_CLOCK/u);
    expect(stagingBlock).not.toMatch(/TEST_CLOCK/u);
  });
});
