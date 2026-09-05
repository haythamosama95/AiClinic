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
  expect(await count("installation_key")).toBe(0);
  expect(await count("entitlement")).toBe(0);
  expect(await count("control_audit")).toBe(0);
  expect(await queryAll("SELECT action FROM control_audit")).toEqual([]);
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
  it("S03-001 — Enroll rejects a request with no Authorization header", async () => {
    const result = await controlFetch(installationActionPath("enroll"), {
      auth: "none",
      body: CANONICAL_ENROLL_BODY,
    });

    assertUnauthorized(result);
    await assertNoLifecycleWrites();
  });

  it("S03-002 — Enroll rejects a wrong bearer token", async () => {
    const result = await controlFetch(installationActionPath("enroll"), {
      auth: "wrong",
      body: CANONICAL_ENROLL_BODY,
    });

    assertUnauthorized(result);
    await assertNoLifecycleWrites();
  });

  it("S03-003 — Rotate rejects a missing bearer token", async () => {
    const result = await controlFetch(installationActionPath("rotate"), {
      auth: "none",
      body: ROTATE_BODY,
    });

    assertUnauthorized(result);
    await assertNoLifecycleWrites();
  });

  it("S03-004 — Rotate rejects a wrong bearer token", async () => {
    const result = await controlFetch(installationActionPath("rotate"), {
      auth: "wrong",
      body: ROTATE_BODY,
    });

    assertUnauthorized(result);
    await assertNoLifecycleWrites();
  });

  it("S03-005 — Revoke-key rejects a missing bearer token", async () => {
    const result = await controlFetch(installationActionPath("revoke-key"), {
      auth: "none",
      body: REVOKE_KEY_BODY,
    });

    assertUnauthorized(result);
    await assertNoLifecycleWrites();
  });

  it("S03-006 — Revoke-key rejects a wrong bearer token", async () => {
    const result = await controlFetch(installationActionPath("revoke-key"), {
      auth: "wrong",
      body: REVOKE_KEY_BODY,
    });

    assertUnauthorized(result);
    await assertNoLifecycleWrites();
  });

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

  it("S03-013 — Purge rejects a missing bearer token", async () => {
    const result = await controlFetch(installationActionPath("purge"), {
      auth: "none",
      body: {},
    });

    assertUnauthorized(result);
    await assertNoLifecycleWrites();
    expect(
      await count("control_audit", "action = ?", ["purge_installation"]),
    ).toBe(0);
  });

  it("S03-014 — Purge rejects a wrong bearer token", async () => {
    const result = await controlFetch(installationActionPath("purge"), {
      auth: "wrong",
      body: {},
    });

    assertUnauthorized(result);
    await assertNoLifecycleWrites();
    expect(
      await count("control_audit", "action = ?", ["purge_installation"]),
    ).toBe(0);
  });

  it("S03-015 — Malformed Authorization schemes and empty tokens are rejected", async () => {
    const empty = await controlFetch(installationActionPath("enroll"), {
      auth: "empty",
      body: CANONICAL_ENROLL_BODY,
    });
    const basic = await controlFetch(installationActionPath("enroll"), {
      auth: "basic",
      body: CANONICAL_ENROLL_BODY,
    });
    const noScheme = await controlFetch(installationActionPath("enroll"), {
      auth: "no-scheme",
      body: CANONICAL_ENROLL_BODY,
    });

    for (const result of [empty, basic, noScheme]) {
      assertUnauthorized(result);
    }
    await assertNoLifecycleWrites();
  });

  it("S03-016 — Auth is checked before route-shape and payload validation", async () => {
    const result = await controlFetch(
      "/control/installations/not-a-uuid/enroll",
      {
        auth: "none",
        body: "not-json",
      },
    );

    assertUnauthorized(result);
    expect(result.status).not.toBe(400);
    await assertNoLifecycleWrites();
  });

  it("S03-017 — Unknown installation action falls through to a plain-text 404", async () => {
    const result = await controlFetch(
      `/control/installations/${I0}/obliterate`,
      { body: {} },
    );

    assertPlainNotFound(result);
    await assertNoLifecycleWrites();
  });

  it("S03-018 — Non-POST method on a lifecycle route falls through to a plain-text 404", async () => {
    const result = await controlFetch(installationActionPath("suspend"), {
      method: "GET",
    });

    assertPlainNotFound(result);
    await assertNoLifecycleWrites();
  });

  it("S03-019 — Trailing slash on a lifecycle route falls through to a plain-text 404", async () => {
    const result = await controlFetch(
      `/control/installations/${I0}/enroll/`,
      { body: CANONICAL_ENROLL_BODY },
    );

    assertPlainNotFound(result);
    await assertNoLifecycleWrites();
  });

  it("S03-020 — Enroll rejects a non-JSON body", async () => {
    const result = await controlFetch(installationActionPath("enroll"), {
      body: "not-json",
    });

    assertControlError(result, 400, "invalid_json");
    await assertNoLifecycleWrites();
  });
});
