import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  bootstrapE2e,
  controlFetch,
  count,
  newClinic,
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

const TOKEN_CONTRACT_V1 = {
  ver: "1",
  added_at: "2026-08-03T00:00:00.000Z",
  retired_at: "2026-10-03T13:00:00.000Z",
  changed_by: "seed",
} as const;

const TOKEN_CONTRACT_V2 = {
  ver: "2",
  added_at: "2026-10-03T13:00:00.000Z",
  retired_at: null,
  changed_by: "seed",
} as const;

const TOKEN_CONTRACT_SEED = [TOKEN_CONTRACT_V1, TOKEN_CONTRACT_V2] as const;

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
      "SELECT ver, added_at, retired_at, changed_by FROM token_contract ORDER BY ver",
    );
    expect(rows).toEqual([...TOKEN_CONTRACT_SEED]);

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
    await newClinic(scenario);
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
    expect(seed?.retired_at ?? null).toBe(TOKEN_CONTRACT_V1.retired_at);
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








  it("S01-014 — begin-rotation of the already-live seed ver", async () => {
    const before = await snapshotTokenContract();

    const result = await controlFetch("/control/token-contract/begin-rotation", {
      body: { ver: "2" },
    });

    expect(result.status).toBe(200);
    await assertTokenContractUnchanged(before);
    expect(await queryAll("SELECT * FROM token_contract")).toHaveLength(2);
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
    expect(seed).toEqual(TOKEN_CONTRACT_V1);
  });
});
