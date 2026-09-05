import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  bootstrapE2e,
  controlFetch,
  count,
  enrollInstallation,
  mintAat,
  newScenario,
  OPERATOR_BEARER,
  queryAll,
  queryOne,
  resetE2eState,
  type HttpResult,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const TOKEN_CONTRACT_SEED = {
  ver: "1",
  added_at: "2026-08-03T00:00:00.000Z",
  retired_at: null,
  changed_by: "seed",
} as const;

type TokenContractRow = {
  ver: string;
  added_at: string;
  retired_at: string | null;
  changed_by: string;
};

async function snapshotTokenContract(): Promise<{
  rows: Record<string, unknown>[];
  audits: number;
}> {
  return {
    rows: await queryAll("SELECT * FROM token_contract"),
    audits: await count("control_audit", "action LIKE ?", ["token_contract_%"]),
  };
}

async function assertTokenContractUnchanged(before: {
  rows: Record<string, unknown>[];
  audits: number;
}): Promise<void> {
  expect(await queryAll("SELECT * FROM token_contract")).toEqual(before.rows);
  expect(
    await count("control_audit", "action LIKE ?", ["token_contract_%"]),
  ).toBe(before.audits);
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

describe("Stage 01 — token-contract auth and validation (S01-001…S01-016)", () => {
  it("S01-001 — Migration seed establishes the ver=1 baseline", async () => {
    const rows = await queryAll<TokenContractRow>(
      "SELECT ver, added_at, retired_at, changed_by FROM token_contract",
    );
    expect(rows).toHaveLength(1);
    expect(rows[0]).toEqual(TOKEN_CONTRACT_SEED);

    expect(
      await count("control_audit", "action LIKE ?", ["token_contract_%"]),
    ).toBe(0);
  });

  it("S01-002 — begin-rotation without Authorization header is rejected", async () => {
    const before = await snapshotTokenContract();

    const result = await controlFetch("/control/token-contract/begin-rotation", {
      auth: "none",
      body: { ver: "2" },
    });

    assertUnauthorized(result);
    await assertTokenContractUnchanged(before);
  });

  it("S01-003 — begin-rotation with wrong bearer secret is rejected", async () => {
    const before = await snapshotTokenContract();

    const result = await controlFetch("/control/token-contract/begin-rotation", {
      auth: "wrong",
      body: { ver: "2" },
    });

    assertUnauthorized(result);
    await assertTokenContractUnchanged(before);
  });

  it("S01-004 — A clinic AAT is not an operator credential", async () => {
    const scenario = await newScenario();
    const enrolled = await enrollInstallation(scenario);
    expect(enrolled.status).toBe(200);

    const aat = await mintAat(scenario, {
      claims: {
        aud: "ai-platform",
        sub: "staff-0001",
        org: scenario.orgId,
        branch: scenario.branchId,
        role: "doctor",
        scopes: ["ai.visit_summary"],
        jti: "s01-004-jti",
        ver: "1",
      },
    });

    const before = await snapshotTokenContract();

    const begin = await controlFetch("/control/token-contract/begin-rotation", {
      auth: { bearer: aat },
      body: { ver: "2" },
    });
    const retire = await controlFetch("/control/token-contract/retire", {
      auth: { bearer: aat },
      body: { ver: "1" },
    });

    assertUnauthorized(begin);
    assertUnauthorized(retire);
    await assertTokenContractUnchanged(before);
  });

  it("S01-005 — retire without / with wrong bearer is rejected", async () => {
    const before = await snapshotTokenContract();

    const missing = await controlFetch("/control/token-contract/retire", {
      auth: "none",
      body: { ver: "1" },
    });
    const wrong = await controlFetch("/control/token-contract/retire", {
      auth: "wrong",
      body: { ver: "1" },
    });

    assertUnauthorized(missing);
    assertUnauthorized(wrong);
    await assertTokenContractUnchanged(before);

    const seed = await queryOne<{ retired_at: string | null }>(
      "SELECT retired_at FROM token_contract WHERE ver = ?",
      ["1"],
    );
    expect(seed?.retired_at ?? null).toBeNull();
  });

  it("S01-006 — Malformed Authorization schemes are rejected", async () => {
    const before = await snapshotTokenContract();

    const lowercaseScheme = await controlFetch(
      "/control/token-contract/begin-rotation",
      {
        auth: { authorization: `bearer ${OPERATOR_BEARER}` },
        body: { ver: "2" },
      },
    );
    const schemeOnly = await controlFetch(
      "/control/token-contract/begin-rotation",
      {
        auth: { authorization: "Bearer" },
        body: { ver: "2" },
      },
    );
    const schemeWhitespace = await controlFetch(
      "/control/token-contract/begin-rotation",
      {
        auth: { authorization: "Bearer    " },
        body: { ver: "2" },
      },
    );

    for (const result of [lowercaseScheme, schemeOnly, schemeWhitespace]) {
      assertUnauthorized(result);
    }
    await assertTokenContractUnchanged(before);
  });

  it("S01-007 — Wrong HTTP method on token-contract routes falls through to 404", async () => {
    const before = await snapshotTokenContract();

    const getBegin = await controlFetch(
      "/control/token-contract/begin-rotation",
      { method: "GET", auth: "operator" },
    );
    const deleteRetire = await controlFetch("/control/token-contract/retire", {
      method: "DELETE",
      auth: "operator",
    });

    assertPlainNotFound(getBegin);
    assertPlainNotFound(deleteRetire);
    await assertTokenContractUnchanged(before);
  });

  it("S01-008 — Unknown token-contract action and trailing slash are 404", async () => {
    const before = await snapshotTokenContract();

    const unknownAction = await controlFetch(
      "/control/token-contract/rotate",
      { body: { ver: "2" } },
    );
    const trailingSlash = await controlFetch(
      "/control/token-contract/retire/",
      { body: { ver: "1" } },
    );

    assertPlainNotFound(unknownAction);
    assertPlainNotFound(trailingSlash);
    await assertTokenContractUnchanged(before);
  });

  it("S01-009 — begin-rotation with malformed JSON body", async () => {
    const before = await snapshotTokenContract();

    const result = await controlFetch("/control/token-contract/begin-rotation", {
      body: '{"ver": ',
    });

    assertControlError(result, 400, "invalid_json");
    await assertTokenContractUnchanged(before);
  });

  it("S01-010 — begin-rotation with missing ver key", async () => {
    const before = await snapshotTokenContract();

    const result = await controlFetch("/control/token-contract/begin-rotation", {
      body: {},
    });

    assertControlError(result, 400, "invalid_ver");
    await assertTokenContractUnchanged(before);
  });

  it("S01-011 — begin-rotation with empty ver string", async () => {
    const before = await snapshotTokenContract();

    const result = await controlFetch("/control/token-contract/begin-rotation", {
      body: { ver: "" },
    });

    assertControlError(result, 400, "invalid_ver");
    await assertTokenContractUnchanged(before);

    const seed = await queryAll<TokenContractRow>(
      "SELECT ver, added_at, retired_at, changed_by FROM token_contract",
    );
    expect(seed).toEqual([TOKEN_CONTRACT_SEED]);
  });

  it("S01-012 — begin-rotation with whitespace-only ver", async () => {
    const before = await snapshotTokenContract();

    const result = await controlFetch("/control/token-contract/begin-rotation", {
      body: { ver: "   " },
    });

    assertControlError(result, 400, "invalid_ver");
    await assertTokenContractUnchanged(before);
  });

  it("S01-013 — begin-rotation with non-string ver returns invalid_ver", async () => {
    // Catalog chapter (C-05): HTTP 400 {"error":"invalid_ver"}; no D1/audit
    // write. Register 5 #8 previously called this uncaught TypeError — do not
    // skip. If the pool fetch rejects with TypeError, the fixer follows code.
    const before = await snapshotTokenContract();

    const result = await controlFetch("/control/token-contract/begin-rotation", {
      body: { ver: 2 },
    });

    assertControlError(result, 400, "invalid_ver");
    await assertTokenContractUnchanged(before);
  });

  it("S01-014 — begin-rotation of the already-live seed ver", async () => {
    const before = await snapshotTokenContract();

    const result = await controlFetch("/control/token-contract/begin-rotation", {
      body: { ver: "1" },
    });

    assertControlError(result, 409, "ver_already_exists");
    await assertTokenContractUnchanged(before);
    expect(await queryAll("SELECT * FROM token_contract")).toHaveLength(1);
    expect(
      await count("control_audit", "action LIKE ?", ["token_contract_%"]),
    ).toBe(0);
  });

  it("S01-015 — retire with malformed JSON body", async () => {
    const before = await snapshotTokenContract();

    const result = await controlFetch("/control/token-contract/retire", {
      body: "not-json",
    });

    assertControlError(result, 400, "invalid_json");
    await assertTokenContractUnchanged(before);
  });

  it("S01-016 — retire with missing / whitespace-only ver", async () => {
    const before = await snapshotTokenContract();

    const missing = await controlFetch("/control/token-contract/retire", {
      body: {},
    });
    const whitespace = await controlFetch("/control/token-contract/retire", {
      body: { ver: "  " },
    });

    assertControlError(missing, 400, "invalid_ver");
    assertControlError(whitespace, 400, "invalid_ver");
    await assertTokenContractUnchanged(before);

    const seed = await queryOne<TokenContractRow>(
      "SELECT ver, added_at, retired_at, changed_by FROM token_contract WHERE ver = ?",
      ["1"],
    );
    expect(seed).toEqual(TOKEN_CONTRACT_SEED);
  });
});
