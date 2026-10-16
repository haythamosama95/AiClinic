import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  bootstrapE2e,
  controlFetch,
  count,
  queryAll,
  resetE2eState,
  type HttpResult,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const I0 = "3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d";

const CANONICAL_ENROLL_BODY = {
  org_id: "7a1b2c3d-4e5f-4a6b-9c8d-0e1f2a3b4c5d",
  display_name: "Verify Clinic",
  region: "eu-central",
  plan: "standard",
  public_key: "n4bQgYhMfWWaL-qgxVrQ1O91g3Z2Q4u2Zz8v0m5p8xk",
  algorithm: "EdDSA",
  kid: "c4d5e6f7-8a9b-4c0d-9e1f-2a3b4c5d6e7f",
} as const;

const ROTATE_BODY = {
  kid: "d5e6f7a8-9b0c-4d1e-8f2a-3b4c5d6e7f8a",
  public_key: "Aq7RtY2mZxCvB8nM3kLpQwErTyUiOpAsDfGhJkLzXcV",
  algorithm: "EdDSA",
} as const;

const REVOKE_KEY_BODY = {
  kid: "c4d5e6f7-8a9b-4c0d-9e1f-2a3b4c5d6e7f",
} as const;

function installationActionPath(action: string, id = I0): string {
  return `/control/installations/${id}/${action}`;
}

async function assertNoLifecycleWrites(): Promise<void> {
  expect(await count("installation")).toBe(0);
  expect(await count("issuer_key")).toBe(0);
  expect(await count("tenant_binding")).toBe(0);
  expect(await count("control_audit")).toBe(0);
  expect(await queryAll("SELECT action FROM control_audit")).toEqual([]);
}

function assertEnrollRotateRevokeRemoved(result: HttpResult): void {
  expect(result.status).toBe(404);
}

function assertUnauthorized(result: HttpResult): void {
  expect(result.status).toBe(401);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.json).toEqual({ error: "unauthorized" });
}

function assertControlError(
  result: HttpResult,
  status: number,
  error: string,
): void {
  expect(result.status).toBe(status);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.json).toEqual({ error });
}

function assertPlainNotFound(result: HttpResult): void {
  expect(result.status).toBe(404);
  expect(result.text).toBe("Not Found");
  expect(result.json).toBeNull();
  expect(result.headers.get("content-type") ?? "").not.toContain(
    "application/json",
  );
}

describe("Stage 03 — installation enrollment auth and routing (S03-001…S03-020)", () => {






  it("S03-007 — Suspend rejects a missing bearer token", async () => {
    const result = await controlFetch(installationActionPath("suspend"), {
      auth: "none",
      body: {},
    });

    assertUnauthorized(result);
    await assertNoLifecycleWrites();
  });

  it("S03-008 — Suspend rejects a wrong bearer token", async () => {
    const result = await controlFetch(installationActionPath("suspend"), {
      auth: "wrong",
      body: {},
    });

    assertUnauthorized(result);
    await assertNoLifecycleWrites();
  });

  it("S03-009 — Resume rejects a missing bearer token", async () => {
    const result = await controlFetch(installationActionPath("resume"), {
      auth: "none",
      body: {},
    });

    assertUnauthorized(result);
    await assertNoLifecycleWrites();
  });

  it("S03-010 — Resume rejects a wrong bearer token", async () => {
    const result = await controlFetch(installationActionPath("resume"), {
      auth: "wrong",
      body: {},
    });

    assertUnauthorized(result);
    await assertNoLifecycleWrites();
  });

  it("S03-011 — Delete rejects a missing bearer token", async () => {
    const result = await controlFetch(installationActionPath("delete"), {
      auth: "none",
      body: {},
    });

    assertUnauthorized(result);
    await assertNoLifecycleWrites();
  });

  it("S03-012 — Delete rejects a wrong bearer token", async () => {
    const result = await controlFetch(installationActionPath("delete"), {
      auth: "wrong",
      body: {},
    });

    assertUnauthorized(result);
    await assertNoLifecycleWrites();
  });








});
