import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import publishedVisitSummary from "../../manifests/published/clinic.visit_summary@1.0.0.json";
import {
  bootstrapE2e,
  controlFetch,
  count,
  createCapabilityRegistry,
  enrollInstallation,
  enrollPayload,
  entitleInstallation,
  env,
  getAudits,
  getGrants,
  loadManifest,
  newScenario,
  OPERATOR_ID,
  queryAll,
  queryOne,
  resetE2eState,
  seedSql,
  setCapabilityRegistry,
  type EntitlePayload,
  type HttpResult,
  type Scenario,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const I0 = "0a1f4c2e-7b3d-4e5f-9a6b-1c2d3e4f5a6b";
const CATALOG_ACTIVATE_INSTALLATION_ID =
  "8f3c2a1e-4b5d-4e6f-9a0b-1c2d3e4f5a6b";
const WRONG_BEARER = "op_wrong-secret-9f8d7c6b5a";
const CAPABILITY_ID = "clinic.visit_summary";
const VERSION = "1.0.0";
const BARE_SUCCESSOR = "clinic.visit_summary";
const PINNED_SUCCESSOR = "clinic.visit_summary@2.0.0";
const DEPRECATE_TARGET = `${CAPABILITY_ID}@${VERSION}`;
const DEPRECATE_PATH = `/control/capabilities/${CAPABILITY_ID}/versions/${VERSION}/deprecate`;
const RETIRE_PATH = `/control/capabilities/${CAPABILITY_ID}/versions/${VERSION}/retire`;
const ACTIVATE_V2_PATH = `/control/capabilities/${CAPABILITY_ID}/versions/2.0.0/activate`;
const PROMOTE_V2_PATH = `/control/capabilities/${CAPABILITY_ID}/versions/2.0.0/promote`;
const OVERLAP_WINDOW_MS = 90 * 24 * 60 * 60 * 1000;
const PAST_RETIRE_AFTER = "2020-01-01T00:00:00.000Z";
const ISO_8601 = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const CLOCK_SKEW_MS = 15_000;
const CANONICAL_UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const REF_BODY: EntitlePayload = {
  period_start: "2026-08-01T00:00:00.000Z",
  period_end: "2026-09-01T00:00:00.000Z",
  request_quota: 1000,
  token_budget: 500000,
  cost_budget: 50.0,
  soft_threshold: 0.8,
  allowed_capabilities: ["clinic.visit_summary"],
  grants: [
    {
      capability_id: "clinic.visit_summary",
      capability_version: "1.0.0",
      scope: "installation",
    },
  ],
};

type OverlayRow = {
  grant_id: string;
  scope: string;
  capability_id: string;
  capability_version: string;
  granted_at: string;
  revoked_at: string | null;
  changed_at: string;
  changed_by: string;
  lifecycle_state: string | null;
  successor_id: string | null;
  deprecated_at: string | null;
  retire_after: string | null;
};

type AuditRow = {
  audit_id: string;
  operator_id: string;
  action: string;
  target: string;
  before_pointer: string | null;
  after_pointer: string | null;
  recorded_at: string;
};

function cloneJson(value: unknown): Record<string, unknown> {
  return JSON.parse(JSON.stringify(value)) as Record<string, unknown>;
}

function assertOkEmpty(result: HttpResult): void {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.json).toEqual({});
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

function assertUnauthorized(result: HttpResult): void {
  assertControlError(result, 401, "unauthorized");
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

function expectCanonicalUuid(value: unknown): void {
  expect(typeof value).toBe("string");
  expect(String(value)).toMatch(CANONICAL_UUID_RE);
}

async function withVisitSummaryV2(run: () => Promise<void>): Promise<void> {
  const v1 = loadManifest(cloneJson(publishedVisitSummary));
  const v2Wire = cloneJson(publishedVisitSummary);
  (v2Wire.Identity as Record<string, unknown>).version = "2.0.0";
  const v2 = loadManifest(v2Wire);
  setCapabilityRegistry(createCapabilityRegistry([v1, v2]), { replace: true });
  try {
    await run();
  } finally {
    setCapabilityRegistry(createCapabilityRegistry([v1]), { replace: true });
  }
}

async function deprecateSuccessor(
  successorId: string,
): Promise<HttpResult> {
  return controlFetch(DEPRECATE_PATH, { body: { successor_id: successorId } });
}

async function completeS04_086(): Promise<HttpResult> {
  const result = await deprecateSuccessor(BARE_SUCCESSOR);
  assertOkEmpty(result);
  return result;
}

async function seedRetireAfterSql(sql: string): Promise<void> {
  await seedSql([{ sql }]);
}

async function completeS04_098(): Promise<void> {
  await completeS04_086();
  await seedRetireAfterSql(
    `UPDATE capability_grant SET retire_after = '${PAST_RETIRE_AFTER}' WHERE scope = 'global' AND capability_id = '${CAPABILITY_ID}' AND lifecycle_state = 'deprecated'`,
  );
  const result = await controlFetch(RETIRE_PATH, { body: {} });
  assertOkEmpty(result);
}

async function enrollAndEntitleI0(): Promise<Scenario> {
  const scenario = await newScenario();
  const i0: Scenario = { ...scenario, installationId: I0 };
  const enrolled = await enrollInstallation(i0, {
    payload: enrollPayload(i0, { plan: "professional" }),
  });
  expect(enrolled.status).toBe(200);
  const entitled = await entitleInstallation(i0, REF_BODY);
  expect(entitled.status).toBe(200);
  return i0;
}

async function globalOverlays(): Promise<OverlayRow[]> {
  return queryAll<OverlayRow>(
    `SELECT * FROM capability_grant
     WHERE scope = 'global' AND capability_id = ? AND capability_version = ?
     ORDER BY changed_at`,
    [CAPABILITY_ID, VERSION],
  );
}

async function latestGlobalOverlay(): Promise<OverlayRow | null> {
  const rows = await globalOverlays();
  return rows[rows.length - 1] ?? null;
}

async function allGrants(): Promise<Record<string, unknown>[]> {
  return queryAll("SELECT * FROM capability_grant ORDER BY grant_id");
}

async function countR2Objects(): Promise<number> {
  const listed = await env.R2.list();
  return listed.objects.length;
}

function assertDeprecatedOverlay(
  overlay: OverlayRow | null,
  successorId: string,
): OverlayRow {
  expect(overlay).not.toBeNull();
  const row = overlay as OverlayRow;
  expectCanonicalUuid(row.grant_id);
  expect(row.scope).toBe("global");
  expect(row.capability_id).toBe(CAPABILITY_ID);
  expect(row.capability_version).toBe(VERSION);
  expect(row.lifecycle_state).toBe("deprecated");
  expect(row.successor_id).toBe(successorId);
  expect(row.changed_by).toBe(OPERATOR_ID);
  const stamp = assertIsoApproxNow(row.deprecated_at);
  expect(row.granted_at).toBe(stamp);
  expect(row.revoked_at).toBe(stamp);
  expect(row.changed_at).toBe(stamp);
  expect(row.retire_after).toBe(
    new Date(Date.parse(stamp) + OVERLAP_WINDOW_MS).toISOString(),
  );
  return row;
}

function assertDeprecateAudit(row: AuditRow | undefined, afterPointer: string): void {
  expect(row).toBeDefined();
  expectCanonicalUuid(row?.audit_id);
  expect(row?.operator_id).toBe(OPERATOR_ID);
  expect(row?.action).toBe("deprecate");
  expect(row?.target).toBe(DEPRECATE_TARGET);
  expect(row?.before_pointer).toBeNull();
  expect(row?.after_pointer).toBe(afterPointer);
  assertIsoApproxNow(row?.recorded_at);
}

function assertRetireAudit(row: AuditRow | undefined, afterPointer: string): void {
  expect(row).toBeDefined();
  expectCanonicalUuid(row?.audit_id);
  expect(row?.operator_id).toBe(OPERATOR_ID);
  expect(row?.action).toBe("retire");
  expect(row?.target).toBe(DEPRECATE_TARGET);
  expect(row?.before_pointer).toBeNull();
  expect(row?.after_pointer).toBe(afterPointer);
  assertIsoApproxNow(row?.recorded_at);
}

async function assertNoInstallationOrPlanGrants(): Promise<void> {
  expect(await count("capability_grant", "scope != ?", ["global"])).toBe(0);
}

async function assertRetiredOverlayWrites(
  deprecatedBefore: OverlayRow,
): Promise<void> {
  const overlays = await globalOverlays();
  expect(overlays).toHaveLength(2);
  const deprecated = overlays.find((row) => row.lifecycle_state === "deprecated");
  const retired = overlays.find((row) => row.lifecycle_state === "retired");
  expect(deprecated).toEqual(deprecatedBefore);
  expect(retired).toBeDefined();
  expectCanonicalUuid(retired?.grant_id);
  expect(retired?.grant_id).not.toBe(deprecatedBefore.grant_id);
  expect(retired?.scope).toBe("global");
  expect(retired?.capability_id).toBe(CAPABILITY_ID);
  expect(retired?.capability_version).toBe(VERSION);
  expect(retired?.lifecycle_state).toBe("retired");
  expect(retired?.successor_id).toBe(deprecatedBefore.successor_id);
  expect(retired?.deprecated_at).toBe(deprecatedBefore.deprecated_at);
  expect(retired?.retire_after).toBe(deprecatedBefore.retire_after);
  expect(retired?.changed_by).toBe(OPERATOR_ID);
  const stamp = assertIsoApproxNow(retired?.changed_at);
  expect(retired?.granted_at).toBe(stamp);
  expect(retired?.revoked_at).toBe(stamp);
  await assertNoInstallationOrPlanGrants();
  const audits = await getAudits("retire", DEPRECATE_TARGET);
  expect(audits).toHaveLength(1);
  assertRetireAudit(audits[0] as AuditRow, String(deprecatedBefore.successor_id));
}

describe("Stage 04 — deprecate, retire, and wrong-bearer auth (S04-086…S04-104)", () => {
  it("S04-086 — Deprecate happy path successor clinic.visit_summary", async () => {
    const result = await completeS04_086();
    assertOkEmpty(result);

    const overlays = await globalOverlays();
    expect(overlays).toHaveLength(1);
    assertDeprecatedOverlay(overlays[0] ?? null, BARE_SUCCESSOR);
    await assertNoInstallationOrPlanGrants();

    const audits = await getAudits("deprecate", DEPRECATE_TARGET);
    expect(audits).toHaveLength(1);
    assertDeprecateAudit(audits[0] as AuditRow, BARE_SUCCESSOR);
  });

  it("S04-087 — Deprecate successor pin clinic.visit_summary@2.0.0", async () => {
    await withVisitSummaryV2(async () => {
      const result = await deprecateSuccessor(PINNED_SUCCESSOR);
      assertOkEmpty(result);

      const overlays = await globalOverlays();
      expect(overlays).toHaveLength(1);
      assertDeprecatedOverlay(overlays[0] ?? null, PINNED_SUCCESSOR);
      await assertNoInstallationOrPlanGrants();

      const audits = await getAudits("deprecate", DEPRECATE_TARGET);
      expect(audits).toHaveLength(1);
      assertDeprecateAudit(audits[0] as AuditRow, PINNED_SUCCESSOR);
    });
  });

  it("S04-088 — Deprecate same successor is idempotent", async () => {
    await completeS04_086();
    const overlayBefore = await latestGlobalOverlay();
    const auditsBefore = await getAudits("deprecate", DEPRECATE_TARGET);
    expect(auditsBefore).toHaveLength(1);

    const result = await deprecateSuccessor(BARE_SUCCESSOR);
    assertOkEmpty(result);

    const overlays = await globalOverlays();
    expect(overlays).toHaveLength(1);
    expect(overlays[0]).toEqual(overlayBefore);
    expect(overlays[0]?.deprecated_at).toBe(overlayBefore?.deprecated_at);
    expect(overlays[0]?.retire_after).toBe(overlayBefore?.retire_after);

    const auditsAfter = await getAudits("deprecate", DEPRECATE_TARGET);
    expect(auditsAfter).toHaveLength(1);
    expect(auditsAfter).toEqual(auditsBefore);
  });

  it("S04-089 — Deprecate different successor after deprecation", async () => {
    await withVisitSummaryV2(async () => {
      await completeS04_086();
      const overlayBefore = await latestGlobalOverlay();
      const auditsBefore = await getAudits("deprecate", DEPRECATE_TARGET);
      expect(auditsBefore).toHaveLength(1);

      const result = await deprecateSuccessor(PINNED_SUCCESSOR);
      assertControlError(result, 409, "already_deprecated");

      const overlays = await globalOverlays();
      expect(overlays).toHaveLength(1);
      expect(overlays[0]).toEqual(overlayBefore);
      expect(overlays[0]?.successor_id).toBe(BARE_SUCCESSOR);

      const auditsAfter = await getAudits("deprecate", DEPRECATE_TARGET);
      expect(auditsAfter).toHaveLength(1);
      expect(auditsAfter).toEqual(auditsBefore);
    });
  });

  it("S04-090 — Deprecate after retire is already_retired", async () => {
    await completeS04_098();
    const overlaysBefore = await globalOverlays();
    expect(overlaysBefore).toHaveLength(2);
    expect(overlaysBefore[overlaysBefore.length - 1]?.lifecycle_state).toBe(
      "retired",
    );
    const grantsBefore = await allGrants();
    const deprecateAuditsBefore = await getAudits("deprecate", DEPRECATE_TARGET);
    const retireAuditsBefore = await getAudits("retire", DEPRECATE_TARGET);

    const result = await deprecateSuccessor(BARE_SUCCESSOR);
    assertControlError(result, 409, "already_retired");

    expect(await globalOverlays()).toEqual(overlaysBefore);
    expect(await allGrants()).toEqual(grantsBefore);
    expect(await getAudits("deprecate", DEPRECATE_TARGET)).toEqual(
      deprecateAuditsBefore,
    );
    expect(await getAudits("retire", DEPRECATE_TARGET)).toEqual(
      retireAuditsBefore,
    );
  });

  it("S04-091 — Deprecate truthy non-string successor_id", async () => {
    // Register 5 #8 (uncaught TypeError) does not apply: requireNonEmptyString
    // returns 400 invalid_payload for a truthy non-string successor_id.
    const result = await controlFetch(DEPRECATE_PATH, {
      body: { successor_id: 123 },
    });
    assertControlError(result, 400, "invalid_payload");

    expect(await count("capability_grant")).toBe(0);
    expect(await count("control_audit")).toBe(0);
  });

  it("S04-092 — Retire rejects missing operator bearer", async () => {
    await completeS04_086();
    const overlayBefore = await latestGlobalOverlay();
    const grantsBefore = await allGrants();

    const result = await controlFetch(RETIRE_PATH, { auth: "none", body: {} });
    assertUnauthorized(result);

    expect(await latestGlobalOverlay()).toEqual(overlayBefore);
    expect(await allGrants()).toEqual(grantsBefore);
    expect(await getAudits("retire", DEPRECATE_TARGET)).toHaveLength(0);
  });

  it("S04-093 — Retire rejects unregistered version 9.9.9", async () => {
    const result = await controlFetch(
      `/control/capabilities/${CAPABILITY_ID}/versions/9.9.9/retire`,
      { body: {} },
    );
    assertControlError(result, 404, "capability_not_found");

    expect(await count("capability_grant")).toBe(0);
    expect(await count("control_audit")).toBe(0);
  });

  it("S04-094 — Retire without prior deprecate is not_deprecated", async () => {
    const result = await controlFetch(RETIRE_PATH, { body: {} });
    assertControlError(result, 400, "not_deprecated");

    expect(await count("capability_grant")).toBe(0);
    expect(await count("control_audit")).toBe(0);
  });

  it("S04-095 — Retire inside overlap window is overlap_window_active", async () => {
    await completeS04_086();
    const overlayBefore = await latestGlobalOverlay();
    expect(overlayBefore?.lifecycle_state).toBe("deprecated");

    const result = await controlFetch(RETIRE_PATH, { body: {} });
    assertControlError(result, 400, "overlap_window_active");

    const overlays = await globalOverlays();
    expect(overlays).toHaveLength(1);
    expect(overlays[0]).toEqual(overlayBefore);
    expect(overlays[0]?.lifecycle_state).toBe("deprecated");
    expect(await getAudits("retire", DEPRECATE_TARGET)).toHaveLength(0);
  });

  it("S04-096 — Retire unparseable retire_after is overlap_window_active", async () => {
    await completeS04_086();
    await seedRetireAfterSql(
      `UPDATE capability_grant SET retire_after = 'not-a-date' WHERE scope = 'global' AND capability_id = '${CAPABILITY_ID}' AND lifecycle_state = 'deprecated'`,
    );
    const overlayBefore = await latestGlobalOverlay();
    expect(overlayBefore?.retire_after).toBe("not-a-date");

    const result = await controlFetch(RETIRE_PATH, { body: {} });
    assertControlError(result, 400, "overlap_window_active");

    expect(await latestGlobalOverlay()).toEqual(overlayBefore);
    expect(await getAudits("retire", DEPRECATE_TARGET)).toHaveLength(0);
  });

  it("S04-097 — Retire missing retire_after is overlap_window_active", async () => {
    await completeS04_086();
    await seedRetireAfterSql(
      `UPDATE capability_grant SET retire_after = NULL WHERE scope = 'global' AND capability_id = '${CAPABILITY_ID}' AND lifecycle_state = 'deprecated'`,
    );
    const overlayBefore = await latestGlobalOverlay();
    expect(overlayBefore?.retire_after).toBeNull();

    const result = await controlFetch(RETIRE_PATH, { body: {} });
    assertControlError(result, 400, "overlap_window_active");

    expect(await latestGlobalOverlay()).toEqual(overlayBefore);
    expect(await getAudits("retire", DEPRECATE_TARGET)).toHaveLength(0);
  });

  it("S04-098 — Retire happy path after overlap window", async () => {
    await completeS04_086();
    await seedRetireAfterSql(
      `UPDATE capability_grant SET retire_after = '${PAST_RETIRE_AFTER}' WHERE scope = 'global' AND capability_id = '${CAPABILITY_ID}' AND lifecycle_state = 'deprecated'`,
    );
    const deprecatedBefore = await latestGlobalOverlay();
    expect(deprecatedBefore).not.toBeNull();
    expect(deprecatedBefore?.lifecycle_state).toBe("deprecated");
    expect(deprecatedBefore?.retire_after).toBe(PAST_RETIRE_AFTER);

    const result = await controlFetch(RETIRE_PATH, { body: {} });
    assertOkEmpty(result);

    await assertRetiredOverlayWrites(deprecatedBefore as OverlayRow);
  });

  it("S04-099 — Second retire after retirement is not_deprecated", async () => {
    await completeS04_098();
    const overlaysBefore = await globalOverlays();
    expect(overlaysBefore).toHaveLength(2);
    const grantsBefore = await allGrants();
    const retireAuditsBefore = await getAudits("retire", DEPRECATE_TARGET);
    expect(retireAuditsBefore).toHaveLength(1);

    const result = await controlFetch(RETIRE_PATH, { body: {} });
    assertControlError(result, 400, "not_deprecated");

    expect(await globalOverlays()).toHaveLength(2);
    expect(await globalOverlays()).toEqual(overlaysBefore);
    expect(await allGrants()).toEqual(grantsBefore);
    expect(await getAudits("retire", DEPRECATE_TARGET)).toHaveLength(1);
    expect(await getAudits("retire", DEPRECATE_TARGET)).toEqual(
      retireAuditsBefore,
    );
  });

  it("S04-100 — Retire ignores malformed body", async () => {
    await completeS04_086();
    await seedRetireAfterSql(
      `UPDATE capability_grant SET retire_after = '${PAST_RETIRE_AFTER}' WHERE scope = 'global' AND capability_id = '${CAPABILITY_ID}' AND lifecycle_state = 'deprecated'`,
    );
    const deprecatedBefore = await latestGlobalOverlay();
    expect(deprecatedBefore).not.toBeNull();

    const result = await controlFetch(RETIRE_PATH, { body: "not json{" });
    assertOkEmpty(result);

    await assertRetiredOverlayWrites(deprecatedBefore as OverlayRow);
  });

  it("S04-101 — Deprecate wrong operator bearer", async () => {
    const result = await controlFetch(DEPRECATE_PATH, {
      auth: { bearer: WRONG_BEARER },
      body: { successor_id: BARE_SUCCESSOR },
    });
    assertUnauthorized(result);

    expect(await count("capability_grant")).toBe(0);
    expect(await count("control_audit")).toBe(0);
    expect(await countR2Objects()).toBe(0);
  });

  it("S04-102 — Retire wrong operator bearer", async () => {
    await completeS04_086();
    const overlayBefore = await latestGlobalOverlay();
    const grantsBefore = await allGrants();
    const auditsBefore = await queryAll<AuditRow>(
      "SELECT * FROM control_audit ORDER BY recorded_at",
    );

    const result = await controlFetch(RETIRE_PATH, {
      auth: { bearer: WRONG_BEARER },
      body: {},
    });
    assertUnauthorized(result);

    expect(await latestGlobalOverlay()).toEqual(overlayBefore);
    expect(await allGrants()).toEqual(grantsBefore);
    expect(await getAudits("retire", DEPRECATE_TARGET)).toHaveLength(0);
    expect(
      await queryAll("SELECT * FROM control_audit ORDER BY recorded_at"),
    ).toEqual(auditsBefore);
  });

  it("S04-103 — Cohort activate wrong operator bearer", async () => {
    await withVisitSummaryV2(async () => {
      await enrollAndEntitleI0();
      const grantsBefore = await getGrants(`installation:${I0}`);
      expect(grantsBefore).toHaveLength(1);
      expect(grantsBefore[0]?.capability_version).toBe("1.0.0");
      const allBefore = await allGrants();

      const result = await controlFetch(ACTIVATE_V2_PATH, {
        auth: { bearer: WRONG_BEARER },
        body: {
          installation_ids: [CATALOG_ACTIVATE_INSTALLATION_ID],
          cohort_name: "beta-ring-1",
        },
      });
      assertUnauthorized(result);

      const grantsAfter = await getGrants(`installation:${I0}`);
      expect(grantsAfter).toHaveLength(1);
      expect(grantsAfter[0]?.capability_version).toBe("1.0.0");
      expect(grantsAfter).toEqual(grantsBefore);
      expect(await allGrants()).toEqual(allBefore);
      expect(await count("control_audit", "action = ?", ["cohort_activate"])).toBe(
        0,
      );
    });
  });

  it("S04-104 — Cohort promote wrong operator bearer", async () => {
    await withVisitSummaryV2(async () => {
      await enrollAndEntitleI0();
      const grantsBefore = await allGrants();
      expect(
        (await getGrants(`installation:${I0}`))[0]?.capability_version,
      ).toBe("1.0.0");

      const result = await controlFetch(PROMOTE_V2_PATH, {
        auth: { bearer: WRONG_BEARER },
        body: {},
      });
      assertUnauthorized(result);

      expect(await allGrants()).toEqual(grantsBefore);
      expect(await count("capability_grant", "scope LIKE ?", ["plan:%"])).toBe(
        0,
      );
      expect(await count("control_audit", "action = ?", ["cohort_promote"])).toBe(
        0,
      );
    });
  });
});
