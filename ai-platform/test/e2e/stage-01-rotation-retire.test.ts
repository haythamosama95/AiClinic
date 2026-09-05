import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  assertRequestReferenceShape,
  assertTaxonomyBody,
  assertUlidShape,
  bootstrapE2e,
  CAPABILITY_VERSION,
  clearConfigCache,
  controlFetch,
  count,
  getAudits,
  invokeCron,
  mintAat,
  OPERATOR_ID,
  postRequest,
  provisionHappyPath,
  queryAll,
  queryOne,
  resetE2eState,
  visitSummaryInvokeBody,
  type InvokeResult,
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

const ISO_8601 = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CLOCK_SKEW_MS = 15_000;

// Catalog labels this “118 chars”; the quoted Action body is 132 chars.
// Follow the quoted value (row + audit target must equal this string).
const LONG_VER =
  "2026-09-05-emergency-rotation-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

type TokenContractRow = {
  ver: string;
  added_at: string;
  retired_at: string | null;
  changed_by: string;
};

type ControlAuditRow = {
  audit_id: string;
  operator_id: string;
  action: string;
  target: string;
  before_pointer: string | null;
  after_pointer: string | null;
  recorded_at: string;
};

type PlatformCounterRow = {
  dimension_set: string;
  count: number;
};

async function beginRotation(ver: string) {
  return controlFetch("/control/token-contract/begin-rotation", { body: { ver } });
}

async function retireVer(ver: string) {
  return controlFetch("/control/token-contract/retire", { body: { ver } });
}

function assertIsoApproxNow(value: unknown): string {
  expect(typeof value).toBe("string");
  const iso = String(value);
  expect(iso).toMatch(ISO_8601);
  const parsed = Date.parse(iso);
  expect(Number.isNaN(parsed)).toBe(false);
  expect(Math.abs(Date.now() - parsed)).toBeLessThan(CLOCK_SKEW_MS);
  return iso;
}

function expectControlError(
  result: { status: number; json: unknown },
  status: number,
  error: string,
): void {
  expect(result.status).toBe(status);
  expect(result.json).toEqual({ error });
}

async function tokenContractRows(): Promise<TokenContractRow[]> {
  return queryAll<TokenContractRow>(
    "SELECT ver, added_at, retired_at, changed_by FROM token_contract ORDER BY ver",
  );
}

async function assertTokenContractSeedOnly(): Promise<void> {
  const rows = await tokenContractRows();
  expect(rows).toHaveLength(1);
  expect(rows[0]).toEqual(TOKEN_CONTRACT_SEED);
}

async function liveVers(): Promise<string[]> {
  const rows = await queryAll<{ ver: string }>(
    "SELECT ver FROM token_contract WHERE retired_at IS NULL ORDER BY ver",
  );
  return rows.map((row) => row.ver);
}

async function tokenContractAudits(): Promise<ControlAuditRow[]> {
  return queryAll<ControlAuditRow>(
    `SELECT audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at
     FROM control_audit
     WHERE action IN ('token_contract_begin_rotation', 'token_contract_retire')
     ORDER BY recorded_at, action, target`,
  );
}

function isIdentityUnauthenticated(result: InvokeResult): boolean {
  return result.status === 401 && result.body?.code === "unauthenticated";
}

function dualAcceptClaims(
  ver: string,
  jti: string,
): Record<string, unknown> {
  return {
    ver,
    jti,
    role: "doctor",
    scopes: ["ai.visit_summary"],
    aud: "ai-platform",
  };
}

async function openVer2Rotation(): Promise<void> {
  const opened = await beginRotation("2");
  expect(opened.status).toBe(200);
  expect(opened.json).toEqual({ ver: "2" });
}

async function retireVer1AfterOpen(): Promise<string> {
  await openVer2Rotation();
  const retired = await retireVer("1");
  expect(retired.status).toBe(200);
  const body = retired.json as { ver: string; retired_at: string };
  expect(body.ver).toBe("1");
  return body.retired_at;
}

function assertUnauthenticatedTaxonomy(json: unknown): void {
  assertTaxonomyBody(json, { code: "unauthenticated", retry_safe: true });
  const body = json as { request_reference: string; trace_id: string };
  assertRequestReferenceShape(String(body.request_reference));
  assertUlidShape(String(body.trace_id));
}

async function flushedUnauthenticatedMetrics(
  installationId: string,
): Promise<PlatformCounterRow[]> {
  // recordGuardRejection is isolate-local until cron flush (Stage 00 S00-024).
  await invokeCron("* * * * *");
  const rows = await queryAll<PlatformCounterRow>(
    "SELECT dimension_set, count FROM platform_counter",
  );
  return rows.filter((row) => {
    let dims: { error_code?: string; installation_id?: string };
    try {
      dims = JSON.parse(row.dimension_set) as {
        error_code?: string;
        installation_id?: string;
      };
    } catch {
      return false;
    }
    return (
      dims.error_code === "unauthenticated" &&
      dims.installation_id === installationId
    );
  });
}

describe("Stage 01 — rotation and retire (S01-017…S01-031)", () => {
  it("S01-017 — retire with non-string ver returns invalid_ver", async () => {
    // Catalog chapter C-05: HTTP 400 {"error":"invalid_ver"}. Register 5 #8 /
    // Register 4 #10 still describe an uncaught TypeError; follow the chapter.
    const before = await tokenContractRows();
    const result = await controlFetch("/control/token-contract/retire", {
      body: { ver: 1 },
    });

    expectControlError(result, 400, "invalid_ver");
    expect(await tokenContractRows()).toEqual(before);
    expect(await tokenContractAudits()).toHaveLength(0);
  });

  it("S01-018 — retire of a ver that was never inserted", async () => {
    const result = await retireVer("never-existed");

    expectControlError(result, 404, "ver_not_found");
    await assertTokenContractSeedOnly();
    expect(await tokenContractAudits()).toHaveLength(0);
  });

  it("S01-019 — retire of the sole live version is refused", async () => {
    const result = await retireVer("1");

    expectControlError(result, 409, "no_rotation_open");
    const seed = await queryOne<TokenContractRow>(
      "SELECT ver, added_at, retired_at, changed_by FROM token_contract WHERE ver = ?",
      ["1"],
    );
    expect(seed).toEqual(TOKEN_CONTRACT_SEED);
    expect(seed?.retired_at).toBeNull();
    expect(seed?.changed_by).toBe("seed");
    expect(await tokenContractAudits()).toHaveLength(0);
  });

  it("S01-020 — begin-rotation happy path opens the ver=2 rotation", async () => {
    const result = await beginRotation("2");

    expect(result.status).toBe(200);
    expect(result.json).toEqual({ ver: "2" });
    expect(Object.keys(result.json as object)).toEqual(["ver"]);

    const rows = await tokenContractRows();
    expect(rows).toHaveLength(2);
    expect(rows[0]).toEqual(TOKEN_CONTRACT_SEED);

    const ver2 = rows[1];
    expect(ver2?.ver).toBe("2");
    expect(ver2?.retired_at).toBeNull();
    expect(ver2?.changed_by).toBe(OPERATOR_ID);
    const addedAt = assertIsoApproxNow(ver2?.added_at);

    const audits = await getAudits("token_contract_begin_rotation", "2");
    expect(audits).toHaveLength(1);
    const audit = audits[0] as ControlAuditRow;
    expect(audit.operator_id).toBe(OPERATOR_ID);
    expect(audit.action).toBe("token_contract_begin_rotation");
    expect(audit.target).toBe("2");
    expect(audit.before_pointer).toBeNull();
    expect(audit.after_pointer).toBeNull();
    expect(String(audit.audit_id)).toMatch(UUID);
    const recordedAt = assertIsoApproxNow(audit.recorded_at);
    expect(Math.abs(Date.parse(recordedAt) - Date.parse(addedAt))).toBeLessThan(
      CLOCK_SKEW_MS,
    );
    expect(await tokenContractAudits()).toHaveLength(1);
  });

  it("S01-021 — begin-rotation while a rotation is already open", async () => {
    await openVer2Rotation();
    expect(await tokenContractAudits()).toHaveLength(1);

    const result = await beginRotation("3");

    expectControlError(result, 409, "rotation_already_open");
    expect(
      await queryOne<{ ver: string }>(
        "SELECT ver FROM token_contract WHERE ver = ?",
        ["3"],
      ),
    ).toBeNull();
    expect(await liveVers()).toEqual(["1", "2"]);
    expect(await getAudits("token_contract_begin_rotation", "2")).toHaveLength(1);
    expect(await getAudits("token_contract_begin_rotation", "3")).toHaveLength(0);
    expect(await tokenContractAudits()).toHaveLength(1);
  });

  it("S01-022 — duplicate ver takes precedence over the open-rotation guard", async () => {
    await openVer2Rotation();
    expect(await tokenContractAudits()).toHaveLength(1);

    const result = await beginRotation("2");

    expectControlError(result, 409, "ver_already_exists");
    expect(result.json).not.toEqual({ error: "rotation_already_open" });
    expect(await liveVers()).toEqual(["1", "2"]);
    expect(await tokenContractAudits()).toHaveLength(1);
  });

  it("S01-023 — begin-rotation trims surrounding whitespace from ver", async () => {
    const result = await beginRotation(" 2 ");

    expect(result.status).toBe(200);
    expect(result.json).toEqual({ ver: "2" });

    const ver2 = await queryOne<TokenContractRow>(
      "SELECT ver, added_at, retired_at, changed_by FROM token_contract WHERE ver = ?",
      ["2"],
    );
    expect(ver2?.ver).toBe("2");
    expect(ver2?.ver).not.toMatch(/\s/);
    expect(ver2?.retired_at).toBeNull();
    expect(ver2?.changed_by).toBe(OPERATOR_ID);

    const audits = await getAudits("token_contract_begin_rotation", "2");
    expect(audits).toHaveLength(1);
    expect(audits[0]?.target).toBe("2");

    const duplicate = await beginRotation("2");
    expectControlError(duplicate, 409, "ver_already_exists");

    const duplicatePadded = await beginRotation(" 2 ");
    expectControlError(duplicatePadded, 409, "ver_already_exists");

    expect(await tokenContractAudits()).toHaveLength(1);
    expect(await count("token_contract")).toBe(2);
  });

  it("S01-024 — begin-rotation accepts a long ver string (no length guard)", async () => {
    const result = await beginRotation(LONG_VER);

    expect(result.status).toBe(200);
    expect(result.json).toEqual({ ver: LONG_VER });

    const row = await queryOne<TokenContractRow>(
      "SELECT ver, added_at, retired_at, changed_by FROM token_contract WHERE ver = ?",
      [LONG_VER],
    );
    expect(row?.ver).toBe(LONG_VER);
    expect(row?.retired_at).toBeNull();
    expect(row?.changed_by).toBe(OPERATOR_ID);
    assertIsoApproxNow(row?.added_at);

    const audits = await getAudits("token_contract_begin_rotation", LONG_VER);
    expect(audits).toHaveLength(1);
    expect(audits[0]?.target).toBe(LONG_VER);
    expect(audits[0]?.operator_id).toBe(OPERATOR_ID);
    expect(String(audits[0]?.audit_id)).toMatch(UUID);
    assertIsoApproxNow(audits[0]?.recorded_at);
  });

  it("S01-025 — Dual-accept window: AATs with ver=1 and ver=2 both pass identity", async () => {
    const scenario = await provisionHappyPath();
    await openVer2Rotation();
    clearConfigCache();

    const before = await tokenContractRows();

    const aatV1 = await mintAat(scenario, {
      claims: dualAcceptClaims("1", "s01-025-v1"),
    });
    const aatV2 = await mintAat(scenario, {
      claims: dualAcceptClaims("2", "s01-025-v2"),
    });

    const first = await postRequest(scenario, {
      token: aatV1,
      idempotencyKey: "s01-025-v1",
      capabilityVersion: CAPABILITY_VERSION,
      body: visitSummaryInvokeBody(scenario, {
        user_intent: "token-contract dual-accept probe",
      }),
    });
    const second = await postRequest(scenario, {
      token: aatV2,
      idempotencyKey: "s01-025-v2",
      capabilityVersion: CAPABILITY_VERSION,
      body: visitSummaryInvokeBody(scenario, {
        user_intent: "token-contract dual-accept probe",
      }),
    });

    expect(isIdentityUnauthenticated(first)).toBe(false);
    expect(isIdentityUnauthenticated(second)).toBe(false);

    expect(await tokenContractRows()).toEqual(before);
  });

  it("S01-026 — AAT carrying an unknown ver is rejected as unauthenticated", async () => {
    const scenario = await provisionHappyPath();
    await openVer2Rotation();
    clearConfigCache();

    const before = await tokenContractRows();
    const aatMissing = await mintAat(scenario, {
      claims: dualAcceptClaims("99", "s01-026-missing"),
    });

    const result = await postRequest(scenario, {
      token: aatMissing,
      idempotencyKey: "s01-026-missing",
      capabilityVersion: CAPABILITY_VERSION,
      body: visitSummaryInvokeBody(scenario, {
        user_intent: "token-contract missing-ver probe",
      }),
    });

    expect(result.status).toBe(401);
    assertUnauthenticatedTaxonomy(result.body);
    expect(await tokenContractRows()).toEqual(before);

    const metrics = await flushedUnauthenticatedMetrics(scenario.installationId);
    expect(metrics.length).toBeGreaterThan(0);
    expect(metrics.some((row) => row.count >= 1)).toBe(true);
  });

  it("S01-027 — retire happy path stamps ver=1", async () => {
    await openVer2Rotation();
    const ver2Before = await queryOne<TokenContractRow>(
      "SELECT ver, added_at, retired_at, changed_by FROM token_contract WHERE ver = ?",
      ["2"],
    );

    const result = await retireVer("1");

    expect(result.status).toBe(200);
    const body = result.json as { ver: string; retired_at: string };
    expect(Object.keys(body).sort()).toEqual(["retired_at", "ver"]);
    expect(body.ver).toBe("1");
    const retiredAt = assertIsoApproxNow(body.retired_at);

    const ver1 = await queryOne<TokenContractRow>(
      "SELECT ver, added_at, retired_at, changed_by FROM token_contract WHERE ver = ?",
      ["1"],
    );
    expect(ver1?.retired_at).toBe(retiredAt);
    expect(ver1?.changed_by).toBe(OPERATOR_ID);

    const ver2After = await queryOne<TokenContractRow>(
      "SELECT ver, added_at, retired_at, changed_by FROM token_contract WHERE ver = ?",
      ["2"],
    );
    expect(ver2After).toEqual(ver2Before);
    expect(ver2After?.retired_at).toBeNull();

    const audits = await getAudits("token_contract_retire", "1");
    expect(audits).toHaveLength(1);
    const audit = audits[0] as ControlAuditRow;
    expect(audit.operator_id).toBe(OPERATOR_ID);
    expect(audit.action).toBe("token_contract_retire");
    expect(audit.target).toBe("1");
    expect(audit.before_pointer).toBeNull();
    expect(audit.after_pointer).toBeNull();
    expect(String(audit.audit_id)).toMatch(UUID);
    assertIsoApproxNow(audit.recorded_at);

    expect(await count("token_contract", "retired_at IS NULL")).toBe(1);
    expect(await liveVers()).toEqual(["2"]);
  });

  it("S01-028 — retire of an already-retired ver is a no-op conflict", async () => {
    const firstRetiredAt = await retireVer1AfterOpen();
    expect(await getAudits("token_contract_retire", "1")).toHaveLength(1);

    const result = await retireVer("1");

    expectControlError(result, 409, "ver_already_retired");

    const ver1 = await queryOne<TokenContractRow>(
      "SELECT ver, retired_at, changed_by FROM token_contract WHERE ver = ?",
      ["1"],
    );
    expect(ver1?.retired_at).toBe(firstRetiredAt);
    expect(await getAudits("token_contract_retire", "1")).toHaveLength(1);
  });

  it("S01-029 — Full path: retiring ver=1 breaks previously valid AATs at identity", async () => {
    const scenario = await provisionHappyPath();
    const aatV1 = await mintAat(scenario, {
      claims: dualAcceptClaims("1", "s01-029-v1"),
    });

    const beforeRetire = await postRequest(scenario, {
      token: aatV1,
      idempotencyKey: "s01-029-v1",
      capabilityVersion: CAPABILITY_VERSION,
      body: visitSummaryInvokeBody(scenario, {
        user_intent: "token-contract post-retire probe",
      }),
    });
    expect(isIdentityUnauthenticated(beforeRetire)).toBe(false);

    await openVer2Rotation();
    await retireVer("1");
    clearConfigCache();

    const contractAfterRetire = await tokenContractRows();

    const afterRetire = await postRequest(scenario, {
      token: aatV1,
      idempotencyKey: "s01-029-after-retire",
      capabilityVersion: CAPABILITY_VERSION,
      body: visitSummaryInvokeBody(scenario, {
        user_intent: "token-contract post-retire probe",
      }),
    });
    expect(afterRetire.status).toBe(401);
    assertUnauthenticatedTaxonomy(afterRetire.body);

    const aatV2 = await mintAat(scenario, {
      claims: dualAcceptClaims("2", "s01-029-v2"),
    });
    const followUp = await postRequest(scenario, {
      token: aatV2,
      idempotencyKey: "s01-029-v2",
      capabilityVersion: CAPABILITY_VERSION,
      body: visitSummaryInvokeBody(scenario, {
        user_intent: "token-contract post-retire probe",
      }),
    });
    expect(isIdentityUnauthenticated(followUp)).toBe(false);

    expect(await tokenContractRows()).toEqual(contractAfterRetire);

    const metrics = await flushedUnauthenticatedMetrics(scenario.installationId);
    expect(metrics.length).toBeGreaterThan(0);
    expect(metrics.some((row) => row.count >= 1)).toBe(true);
  });

  it("S01-030 — begin-rotation does not revive a retired ver", async () => {
    const firstRetiredAt = await retireVer1AfterOpen();
    const auditsBefore = await tokenContractAudits();

    const result = await beginRotation("1");

    expectControlError(result, 409, "ver_already_exists");

    const ver1 = await queryOne<TokenContractRow>(
      "SELECT ver, retired_at, changed_by FROM token_contract WHERE ver = ?",
      ["1"],
    );
    expect(ver1?.retired_at).toBe(firstRetiredAt);
    expect(ver1?.changed_by).toBe(OPERATOR_ID);
    expect(await getAudits("token_contract_begin_rotation", "1")).toHaveLength(0);
    expect(await tokenContractAudits()).toEqual(auditsBefore);
  });

  it("S01-031 — Full rotation-reuse cycle ends at no_rotation_open again", async () => {
    await retireVer1AfterOpen();

    const step1 = await beginRotation("3");
    expect(step1.status).toBe(200);
    expect(step1.json).toEqual({ ver: "3" });

    const ver3 = await queryOne<TokenContractRow>(
      "SELECT ver, added_at, retired_at, changed_by FROM token_contract WHERE ver = ?",
      ["3"],
    );
    expect(ver3?.ver).toBe("3");
    expect(ver3?.retired_at).toBeNull();
    expect(ver3?.changed_by).toBe(OPERATOR_ID);
    assertIsoApproxNow(ver3?.added_at);
    const begin3 = await getAudits("token_contract_begin_rotation", "3");
    expect(begin3).toHaveLength(1);
    expect(begin3[0]?.target).toBe("3");
    expect(begin3[0]?.operator_id).toBe(OPERATOR_ID);
    expect(String(begin3[0]?.audit_id)).toMatch(UUID);
    assertIsoApproxNow(begin3[0]?.recorded_at);

    const step2 = await retireVer("2");
    expect(step2.status).toBe(200);
    const step2Body = step2.json as { ver: string; retired_at: string };
    expect(step2Body.ver).toBe("2");
    const retired2 = assertIsoApproxNow(step2Body.retired_at);
    const ver2 = await queryOne<TokenContractRow>(
      "SELECT ver, retired_at, changed_by FROM token_contract WHERE ver = ?",
      ["2"],
    );
    expect(ver2?.retired_at).toBe(retired2);
    expect(ver2?.changed_by).toBe(OPERATOR_ID);
    expect(await getAudits("token_contract_retire", "2")).toHaveLength(1);
    expect(await liveVers()).toEqual(["3"]);

    const step3 = await retireVer("3");
    expectControlError(step3, 409, "no_rotation_open");

    const ver3After = await queryOne<TokenContractRow>(
      "SELECT ver, retired_at, changed_by FROM token_contract WHERE ver = ?",
      ["3"],
    );
    expect(ver3After?.retired_at).toBeNull();
    expect(await getAudits("token_contract_retire", "3")).toHaveLength(0);

    const finalRows = await tokenContractRows();
    expect(finalRows.map((row) => row.ver)).toEqual(["1", "2", "3"]);
    expect(finalRows[0]?.retired_at).not.toBeNull();
    expect(finalRows[1]?.retired_at).not.toBeNull();
    expect(finalRows[2]?.retired_at).toBeNull();
    expect(await count("token_contract", "retired_at IS NULL")).toBe(1);
  });
});
