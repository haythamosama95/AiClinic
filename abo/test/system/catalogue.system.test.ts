/**
 * P4.1 — catalogue and gate E2E tests (H-ABO).
 */

import { beforeEach, describe, expect, it } from "vitest";
import {
  billingFetch,
  mintAi,
  mintBilling,
  newIssuer,
  opsFetch,
  pinIssuer,
  resetHarnessState,
  tableCount,
} from "./harness";

beforeEach(async () => {
  await resetHarnessState();
});

describe("catalogue", () => {
  it("E2E-P4.1-01 missing or unsupported Abo-Contract-Version is 400 before auth", async () => {
    const tokenUseBefore = await tableCount("token_use");
    const contactBefore = await tableCount("billing_contact");

    const paths = [
      { fetch: billingFetch, path: "/v1/offers" },
      { fetch: opsFetch, path: "/ops/lookup" },
    ] as const;

    for (const { fetch, path } of paths) {
      for (const version of [undefined, "2"] as const) {
        const headers: Record<string, string> = {
          authorization: "Bearer invalid-token",
        };
        if (version !== undefined) {
          headers["Abo-Contract-Version"] = version;
        }
        const response = await fetch(path, { headers });
        expect(response.status).toBe(400);
        const json = (await response.json()) as Record<string, unknown>;
        expect(json.code).toBe("contract_version_unsupported");
        expect(json.message).toBe("contract_version_unsupported");
        expect(json.contract_version).toBe(1);
        expect(json.accepted_versions).toEqual([0, 1]);
        expect(response.headers.get("Abo-Contract-Version")).toBe("1");
      }
    }

    expect(await tableCount("token_use")).toBe(tokenUseBefore);
    expect(await tableCount("billing_contact")).toBe(contactBefore);
  });

  it("E2E-P4.1-02 AI token and unpinned kid are 401 and doctor is 403", async () => {
    const pinned = await newIssuer();
    await pinIssuer(pinned.kid, pinned.publicKey);
    const unpinned = await newIssuer();

    const now = Math.floor(Date.now() / 1000);
    const baseClaims = {
      sub: "user-test",
      org: "org-test",
      branch: "branch-test",
      iat: now,
      exp: now + 300,
      jti: crypto.randomUUID(),
    };

    const aiToken = await mintAi(pinned, {
      ...baseClaims,
      role: "administrator",
      scopes: ["clinic.visit_summary"],
    });
    const aiResponse = await billingFetch("/v1/offers", {
      headers: {
        authorization: `Bearer ${aiToken}`,
        "Abo-Contract-Version": "1",
      },
    });
    expect(aiResponse.status).toBe(401);
    const aiJson = (await aiResponse.json()) as Record<string, unknown>;
    expect(aiJson.code).toBe("unauthenticated");

    const unpinnedToken = await mintBilling(unpinned, {
      ...baseClaims,
      role: "administrator",
      jti: crypto.randomUUID(),
    });
    const unpinnedResponse = await billingFetch("/v1/offers", {
      headers: {
        authorization: `Bearer ${unpinnedToken}`,
        "Abo-Contract-Version": "1",
      },
    });
    expect(unpinnedResponse.status).toBe(401);
    const unpinnedJson = (await unpinnedResponse.json()) as Record<string, unknown>;
    expect(unpinnedJson.code).toBe("unauthenticated");

    const doctorToken = await mintBilling(pinned, {
      ...baseClaims,
      role: "doctor",
      jti: crypto.randomUUID(),
    });
    const doctorResponse = await billingFetch("/v1/offers", {
      headers: {
        authorization: `Bearer ${doctorToken}`,
        "Abo-Contract-Version": "1",
      },
    });
    expect(doctorResponse.status).toBe(403);
    const doctorJson = (await doctorResponse.json()) as Record<string, unknown>;
    expect(doctorJson.code).toBe("forbidden_role");
  });

  it("E2E-P4.1-06 cross-host paths are 404 before version and auth", async () => {
    const tokenUseBefore = await tableCount("token_use");

    const crossings = [
      { fetch: billingFetch, path: "/ops/lookup" },
      { fetch: opsFetch, path: "/v1/offers" },
    ] as const;

    for (const { fetch, path } of crossings) {
      const withoutVersion = await fetch(path);
      expect(withoutVersion.status).toBe(404);
      expect(await withoutVersion.text()).toBe("");
      expect(withoutVersion.headers.get("Abo-Contract-Version")).toBeNull();

      const withVersion = await fetch(path, {
        headers: { "Abo-Contract-Version": "1" },
      });
      expect(withVersion.status).toBe(404);
      expect(await withVersion.text()).toBe("");
      expect(withVersion.headers.get("Abo-Contract-Version")).toBeNull();
    }

    expect(await tableCount("token_use")).toBe(tokenUseBefore);
  });
});
