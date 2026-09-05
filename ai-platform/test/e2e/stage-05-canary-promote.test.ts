import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  bootstrapE2e,
  canaryPolicy,
  controlFetch,
  count,
  enrollInstallation,
  env,
  generateTestKeypair,
  getAudits,
  getR2Json,
  getRoutingPolicy,
  newScenario,
  OPERATOR_ID,
  POLICY_ID,
  POLICY_VERSION,
  promotePolicy,
  publishPolicy,
  queryAll,
  queryOne,
  r2Exists,
  resetE2eState,
  type HttpResult,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const INST_A = "018e4f2a-7c3b-7f1a-9d2e-5c6a8b0d1e2f";
const INST_B = "018e4f2a-9d4c-7a2b-8e3f-6d7b9c1e2f3a";
const UNKNOWN_INSTALLATION_ID = "9e9e9e9e-0000-4000-8000-000000000000";
const COHORT_NAME = "early-adopters";
const ISO_8601 = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?Z$/;
const CANONICAL_UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const DEEPSEEK_TARGET = {
  provider_id: "deepseek",
  model_id: "deepseek-v4-flash",
  features: {
    structured_output: true,
    min_context_window: 128000,
    languages: ["en"],
    latency_class: "standard",
    cost_class: "standard",
  },
  max_attempts: 2,
  timeout_ms: 30000,
} as const;

const GEMINI_TARGET = {
  provider_id: "gemini",
  model_id: "gemini-3.5-flash",
  features: {
    structured_output: true,
    min_context_window: 128000,
    languages: ["en"],
    latency_class: "standard",
    cost_class: "standard",
  },
  max_attempts: 2,
  timeout_ms: 30000,
} as const;

function platformDefaultDocument(
  policyVersion = 1,
): Record<string, unknown> {
  return {
    schema_version: 1,
    policy_id: POLICY_ID,
    policy_version: policyVersion,
    defaults: { cost_class: "standard", max_parallel_attempts: 1 },
    rules: [
      {
        rule_id: "platform-default-fallback",
        match: {},
        requires: {
          structured_output: false,
          min_context_window: 0,
          languages: [],
        },
        targets: [DEEPSEEK_TARGET, GEMINI_TARGET],
      },
    ],
    overrides: [],
  };
}

function extraKeysDocument(): Record<string, unknown> {
  return {
    schema_version: 1,
    policy_id: POLICY_ID,
    policy_version: 1,
    defaults: { cost_class: "standard", max_parallel_attempts: 1 },
    rules: [
      {
        rule_id: "platform-default-fallback",
        match: {},
        requires: {
          structured_output: false,
          min_context_window: 0,
          languages: [],
        },
        targets: [DEEPSEEK_TARGET, GEMINI_TARGET],
        note: "ops-only",
      },
    ],
    overrides: [],
    future_field: { experimental: true },
  };
}

function malformedDocument(): Record<string, unknown> {
  return {
    schema_version: 1,
    policy_id: POLICY_ID,
    policy_version: 9,
    defaults: { cost_class: "standard", max_parallel_attempts: 1 },
    rules: [
      {
        rule_id: "narrow",
        match: { capability_ids: ["clinic.nonexistent"] },
        requires: {
          structured_output: false,
          min_context_window: 0,
          languages: [],
        },
        targets: [
          {
            provider_id: "deepseek",
            model_id: "deepseek-v4-flash",
            features: {
              structured_output: "yes",
              min_context_window: "big",
              languages: "en",
              latency_class: "standard",
              cost_class: "cheap",
            },
            max_attempts: 2,
            timeout_ms: 30000,
          },
        ],
      },
    ],
    overrides: [],
  };
}

function policyPointer(version: string): string {
  return `control/routing-policy/${POLICY_ID}/${version}.json`;
}

function policyTarget(version: string): string {
  return `${POLICY_ID}@${version}`;
}

function canaryPath(version: string): string {
  return `/control/routing-policies/${POLICY_ID}/versions/${version}/canary`;
}

function promotePath(version: string): string {
  return `/control/routing-policies/${POLICY_ID}/versions/${version}/promote`;
}

function instACanaryList(): string {
  return JSON.stringify([INST_A]);
}

function instBCanaryList(): string {
  return JSON.stringify([INST_B]);
}

function bothCanaryList(): string {
  return JSON.stringify([INST_A, INST_B]);
}

function cohortAfterPointer(): string {
  return JSON.stringify({
    installation_ids: [INST_A],
    details: { cohort_name: COHORT_NAME },
  });
}

function assertControlError(
  result: HttpResult,
  status: number,
  error: string,
): void {
  expect(result.status).toBe(status);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.json).toEqual({ error });
  expect(result.text).toBe(JSON.stringify({ error }));
}

function assertEmptySuccess(result: HttpResult): void {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.json).toEqual({});
  expect(result.text).toBe("{}");
}

function expectIsoTimestamp(value: unknown): string {
  expect(typeof value).toBe("string");
  const iso = String(value);
  expect(iso).toMatch(ISO_8601);
  expect(Number.isNaN(Date.parse(iso))).toBe(false);
  return iso;
}

function expectCanonicalUuid(value: unknown): string {
  expect(typeof value).toBe("string");
  const id = String(value);
  expect(id).toMatch(CANONICAL_UUID_RE);
  return id;
}

async function enrollAt(installationId: string): Promise<void> {
  const scenario = await newScenario();
  const keypair = await generateTestKeypair();
  const result = await enrollInstallation({
    ...scenario,
    installationId,
    kid: keypair.kid,
    keypair,
  });
  expect(result.status).toBe(200);
}

async function publishVersion(
  version: number,
  document: Record<string, unknown> = platformDefaultDocument(version),
): Promise<Record<string, unknown>> {
  const result = await publishPolicy(POLICY_ID, String(version), document);
  assertEmptySuccess(result);
  return document;
}

async function publishStandardV1(): Promise<Record<string, unknown>> {
  return publishVersion(1);
}

async function snapshotPolicy(version: string): Promise<Record<string, unknown>> {
  const row = await getRoutingPolicy(POLICY_ID, version);
  expect(row).not.toBeNull();
  return { ...row! };
}

async function assertR2Document(
  version: string,
  document: Record<string, unknown>,
): Promise<void> {
  const key = policyPointer(version);
  expect(await r2Exists(key)).toBe(true);
  expect(await getR2Json(key)).toEqual(document);
  const object = await env.R2.get(key);
  expect(object).not.toBeNull();
  expect(object!.httpMetadata?.contentType).toBe("application/json");
  expect(await object!.text()).toBe(JSON.stringify(document));
}

async function assertPublishedRow(
  version: string,
  document: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const row = await getRoutingPolicy(POLICY_ID, version);
  expect(row).not.toBeNull();
  expect(row?.policy_id).toBe(POLICY_ID);
  expect(row?.version).toBe(version);
  expect(row?.content_pointer).toBe(policyPointer(version));
  expectIsoTimestamp(row?.active_from);
  expect(row?.activated_by).toBe(OPERATOR_ID);
  expect(row?.canary_installation_ids).toBeNull();
  expect(row?.status).toBe("published");
  await assertR2Document(version, document);

  const audits = await getAudits(
    "routing_policy_publish",
    policyTarget(version),
  );
  expect(audits).toHaveLength(1);
  expectCanonicalUuid(audits[0]?.audit_id);
  expect(audits[0]?.operator_id).toBe(OPERATOR_ID);
  expect(audits[0]?.target).toBe(policyTarget(version));
  expect(audits[0]?.before_pointer).toBeNull();
  expect(audits[0]?.after_pointer).toBe(policyPointer(version));
  expectIsoTimestamp(audits[0]?.recorded_at);
  return row!;
}

async function canaryInstAWithCohort(): Promise<HttpResult> {
  // HARNESS-GAP: canaryPolicy(policyId, version, installationIds) has no
  // cohort_name argument; catalog S05-023 persists it on after_pointer.
  return controlFetch(canaryPath(POLICY_VERSION), {
    body: { installation_ids: [INST_A], cohort_name: COHORT_NAME },
  });
}

async function setupPublishedV1(): Promise<Record<string, unknown>> {
  return publishStandardV1();
}

async function setupCanaryV1(): Promise<void> {
  await publishStandardV1();
  await enrollAt(INST_A);
  const result = await canaryInstAWithCohort();
  assertEmptySuccess(result);
}

async function setupTwoLiveCanaries(): Promise<void> {
  await setupCanaryV1();
  await publishVersion(2);
  await enrollAt(INST_B);
  const result = await canaryPolicy(POLICY_ID, "2", [INST_B]);
  assertEmptySuccess(result);
}

async function setupActiveV1(): Promise<void> {
  await publishStandardV1();
  const result = await promotePolicy(POLICY_ID, POLICY_VERSION);
  assertEmptySuccess(result);
}

async function setupV1SupersededV2Active(): Promise<void> {
  await setupActiveV1();
  await publishVersion(2);
  const result = await promotePolicy(POLICY_ID, "2");
  assertEmptySuccess(result);
}

async function assertNoCanaryMutation(
  version: string,
  before: Record<string, unknown>,
  canaryAuditsBefore: number,
): Promise<void> {
  expect(await getRoutingPolicy(POLICY_ID, version)).toEqual(before);
  expect(
    await getAudits("routing_policy_canary", policyTarget(version)),
  ).toHaveLength(canaryAuditsBefore);
}

async function assertNoPromoteMutation(
  version: string,
  before: Record<string, unknown>,
  promoteAuditsBefore: number,
): Promise<void> {
  expect(await getRoutingPolicy(POLICY_ID, version)).toEqual(before);
  expect(
    await getAudits("routing_policy_promote", policyTarget(version)),
  ).toHaveLength(promoteAuditsBefore);
}

describe("Stage 05 — canary and promote (S05-021…S05-041)", () => {
  it("S05-021 — Extra keys stored verbatim", async () => {
    const document = extraKeysDocument();
    const result = await publishPolicy(POLICY_ID, POLICY_VERSION, document);

    assertEmptySuccess(result);
    await assertPublishedRow(POLICY_VERSION, document);

    const stored = await getR2Json(policyPointer(POLICY_VERSION));
    expect(stored.future_field).toEqual({ experimental: true });
    const rules = stored.rules as Record<string, unknown>[];
    expect(rules[0]?.note).toBe("ops-only");

    expect(await count("routing_policy")).toBe(1);
    expect(await count("control_audit")).toBe(1);
    expect(await count("kill_switch")).toBe(0);
  });

  it("S05-022 — Shape-malformed document still publishes", async () => {
    const document = malformedDocument();
    const result = await publishPolicy(POLICY_ID, "9", document);

    assertEmptySuccess(result);
    await assertPublishedRow("9", document);
    expect(await count("routing_policy")).toBe(1);
    expect(await count("control_audit")).toBe(1);
  });

  it("S05-023 — Canary happy path from published", async () => {
    await publishStandardV1();
    await enrollAt(INST_A);

    const result = await canaryInstAWithCohort();

    assertEmptySuccess(result);

    const row = await getRoutingPolicy(POLICY_ID, POLICY_VERSION);
    expect(row?.status).toBe("canary");
    expect(row?.canary_installation_ids).toBe(instACanaryList());
    expect(row?.content_pointer).toBe(policyPointer(POLICY_VERSION));

    const audits = await getAudits(
      "routing_policy_canary",
      policyTarget(POLICY_VERSION),
    );
    expect(audits).toHaveLength(1);
    expectCanonicalUuid(audits[0]?.audit_id);
    expect(audits[0]?.operator_id).toBe(OPERATOR_ID);
    expect(audits[0]?.target).toBe(policyTarget(POLICY_VERSION));
    expect(audits[0]?.before_pointer).toBeNull();
    expect(audits[0]?.after_pointer).toBe(cohortAfterPointer());
    expectIsoTimestamp(audits[0]?.recorded_at);

    const parsedAfter = JSON.parse(String(audits[0]?.after_pointer)) as {
      installation_ids: string[];
      details: { cohort_name: string };
    };
    expect(parsedAfter.installation_ids).toEqual([INST_A]);
    expect(parsedAfter.details.cohort_name).toBe(COHORT_NAME);

    expect(await r2Exists(policyPointer(POLICY_VERSION))).toBe(true);
    expect(await count("routing_policy")).toBe(1);
  });

  it("S05-024 — Re-canary replaces cohort", async () => {
    await setupCanaryV1();
    await enrollAt(INST_B);

    const result = await canaryPolicy(POLICY_ID, POLICY_VERSION, [INST_A, INST_B]);

    assertEmptySuccess(result);

    const row = await getRoutingPolicy(POLICY_ID, POLICY_VERSION);
    expect(row?.status).toBe("canary");
    expect(row?.canary_installation_ids).toBe(bothCanaryList());

    const audits = await getAudits(
      "routing_policy_canary",
      policyTarget(POLICY_VERSION),
    );
    expect(audits).toHaveLength(2);
    expect(audits[1]?.operator_id).toBe(OPERATOR_ID);
    expect(audits[1]?.before_pointer).toBe(instACanaryList());
    expect(audits[1]?.after_pointer).toBe(bothCanaryList());
    expectIsoTimestamp(audits[1]?.recorded_at);
  });

  it("S05-025 — Two live canary rows", async () => {
    await setupCanaryV1();
    const v1Before = await snapshotPolicy(POLICY_VERSION);
    await publishVersion(2);
    await enrollAt(INST_B);

    const result = await canaryPolicy(POLICY_ID, "2", [INST_B]);

    assertEmptySuccess(result);

    const v1After = await getRoutingPolicy(POLICY_ID, POLICY_VERSION);
    expect(v1After).toEqual(v1Before);
    expect(v1After?.status).toBe("canary");
    expect(v1After?.canary_installation_ids).toBe(instACanaryList());

    const v2 = await getRoutingPolicy(POLICY_ID, "2");
    expect(v2?.status).toBe("canary");
    expect(v2?.canary_installation_ids).toBe(instBCanaryList());

    const rows = await queryAll(
      `SELECT version, status, canary_installation_ids
       FROM routing_policy WHERE policy_id = ? ORDER BY version`,
      [POLICY_ID],
    );
    expect(rows).toHaveLength(2);
    expect(rows.filter((row) => row.status === "canary")).toHaveLength(2);

    const audits = await getAudits("routing_policy_canary", policyTarget("2"));
    expect(audits).toHaveLength(1);
    expect(audits[0]?.operator_id).toBe(OPERATOR_ID);
    expect(audits[0]?.before_pointer).toBe(instACanaryList());
    expect(audits[0]?.after_pointer).toBe(instBCanaryList());
  });

  it("S05-026 — Unknown version is policy_version_not_found", async () => {
    await publishStandardV1();
    await enrollAt(INST_A);
    const before = await snapshotPolicy(POLICY_VERSION);
    const publishAudits = await count(
      "control_audit",
      "action = ?",
      ["routing_policy_publish"],
    );

    const result = await canaryPolicy(POLICY_ID, "99", [INST_A]);

    assertControlError(result, 404, "policy_version_not_found");
    await assertNoCanaryMutation(POLICY_VERSION, before, 0);
    expect(await getRoutingPolicy(POLICY_ID, "99")).toBeNull();
    expect(
      await getAudits("routing_policy_canary", policyTarget("99")),
    ).toHaveLength(0);
    expect(await count("control_audit", "action = ?", ["routing_policy_publish"])).toBe(
      publishAudits,
    );
  });

  it("S05-027 — Canary active is illegal_policy_transition", async () => {
    await setupActiveV1();
    await enrollAt(INST_A);
    const before = await snapshotPolicy(POLICY_VERSION);

    const result = await canaryPolicy(POLICY_ID, POLICY_VERSION, [INST_A]);

    assertControlError(result, 409, "illegal_policy_transition");
    await assertNoCanaryMutation(POLICY_VERSION, before, 0);
    expect(before.status).toBe("active");
  });

  it("S05-028 — Canary superseded is illegal_policy_transition", async () => {
    await setupV1SupersededV2Active();
    await enrollAt(INST_A);
    const v1Before = await snapshotPolicy(POLICY_VERSION);
    const v2Before = await snapshotPolicy("2");

    const result = await canaryPolicy(POLICY_ID, POLICY_VERSION, [INST_A]);

    assertControlError(result, 409, "illegal_policy_transition");
    await assertNoCanaryMutation(POLICY_VERSION, v1Before, 0);
    expect(v1Before.status).toBe("superseded");
    expect(await getRoutingPolicy(POLICY_ID, "2")).toEqual(v2Before);
  });

  it("S05-029 — Canary unparseable JSON is invalid_json", async () => {
    await publishStandardV1();
    const before = await snapshotPolicy(POLICY_VERSION);

    const result = await controlFetch(canaryPath(POLICY_VERSION), {
      body: '{"installation_ids": [',
    });

    assertControlError(result, 400, "invalid_json");
    await assertNoCanaryMutation(POLICY_VERSION, before, 0);
  });

  it("S05-030 — Canary without installation_ids", async () => {
    await publishStandardV1();
    const before = await snapshotPolicy(POLICY_VERSION);

    const result = await controlFetch(canaryPath(POLICY_VERSION), {
      body: { cohort_name: COHORT_NAME },
    });

    assertControlError(result, 400, "missing_installation_ids");
    await assertNoCanaryMutation(POLICY_VERSION, before, 0);
  });

  it("S05-031 — Canary empty installation_ids", async () => {
    await publishStandardV1();
    const before = await snapshotPolicy(POLICY_VERSION);

    const result = await canaryPolicy(POLICY_ID, POLICY_VERSION, []);

    assertControlError(result, 400, "missing_installation_ids");
    await assertNoCanaryMutation(POLICY_VERSION, before, 0);
  });

  it("S05-032 — Canary non-array installation_ids", async () => {
    await publishStandardV1();
    const before = await snapshotPolicy(POLICY_VERSION);

    const result = await controlFetch(canaryPath(POLICY_VERSION), {
      body: { installation_ids: INST_A },
    });

    assertControlError(result, 400, "missing_installation_ids");
    await assertNoCanaryMutation(POLICY_VERSION, before, 0);
  });

  it("S05-033 — Unknown installation id is installation_not_found", async () => {
    await publishStandardV1();
    await enrollAt(INST_A);
    const before = await snapshotPolicy(POLICY_VERSION);

    const unknownId = await controlFetch(canaryPath(POLICY_VERSION), {
      body: { installation_ids: [INST_A, UNKNOWN_INSTALLATION_ID] },
    });
    assertControlError(unknownId, 404, "installation_not_found");
    await assertNoCanaryMutation(POLICY_VERSION, before, 0);

    const nonString = await controlFetch(canaryPath(POLICY_VERSION), {
      body: { installation_ids: [INST_A, 42] },
    });
    assertControlError(nonString, 404, "installation_not_found");
    await assertNoCanaryMutation(POLICY_VERSION, before, 0);

    const row = await queryOne<{
      status: string;
      canary_installation_ids: string | null;
    }>(
      `SELECT status, canary_installation_ids
       FROM routing_policy WHERE policy_id = ? AND version = ?`,
      [POLICY_ID, POLICY_VERSION],
    );
    expect(row?.status).toBe("published");
    expect(row?.canary_installation_ids).toBeNull();
  });

  it("S05-034 — Canary without operator auth", async () => {
    await publishStandardV1();
    const before = await snapshotPolicy(POLICY_VERSION);

    const result = await controlFetch(canaryPath(POLICY_VERSION), {
      auth: "none",
      body: { installation_ids: [INST_A] },
    });

    assertControlError(result, 401, "unauthorized");
    await assertNoCanaryMutation(POLICY_VERSION, before, 0);
  });

  it("S05-035 — Promote first version", async () => {
    const document = await publishStandardV1();
    const r2Before = await getR2Json(policyPointer(POLICY_VERSION));

    const result = await promotePolicy(POLICY_ID, POLICY_VERSION);

    assertEmptySuccess(result);

    const row = await getRoutingPolicy(POLICY_ID, POLICY_VERSION);
    expect(row?.status).toBe("active");
    expect(row?.canary_installation_ids).toBeNull();
    expect(row?.content_pointer).toBe(policyPointer(POLICY_VERSION));

    const audits = await getAudits(
      "routing_policy_promote",
      policyTarget(POLICY_VERSION),
    );
    expect(audits).toHaveLength(1);
    expectCanonicalUuid(audits[0]?.audit_id);
    expect(audits[0]?.operator_id).toBe(OPERATOR_ID);
    expect(audits[0]?.target).toBe(policyTarget(POLICY_VERSION));
    expect(audits[0]?.before_pointer).toBeNull();
    expect(audits[0]?.after_pointer).toBe(policyTarget(POLICY_VERSION));
    expectIsoTimestamp(audits[0]?.recorded_at);

    expect(await getR2Json(policyPointer(POLICY_VERSION))).toEqual(r2Before);
    expect(await getR2Json(policyPointer(POLICY_VERSION))).toEqual(document);
    expect(await count("routing_policy")).toBe(1);
  });

  it("S05-036 — Promote v2 supersedes active v1", async () => {
    await setupActiveV1();
    await publishVersion(2);

    const result = await promotePolicy(POLICY_ID, "2");

    assertEmptySuccess(result);

    const v1 = await getRoutingPolicy(POLICY_ID, POLICY_VERSION);
    expect(v1?.status).toBe("superseded");
    expect(v1?.canary_installation_ids).toBeNull();

    const v2 = await getRoutingPolicy(POLICY_ID, "2");
    expect(v2?.status).toBe("active");
    expect(v2?.canary_installation_ids).toBeNull();

    const audits = await getAudits("routing_policy_promote", policyTarget("2"));
    expect(audits).toHaveLength(1);
    expect(audits[0]?.operator_id).toBe(OPERATOR_ID);
    expect(audits[0]?.before_pointer).toBe(policyTarget(POLICY_VERSION));
    expect(audits[0]?.after_pointer).toBe(policyTarget("2"));
  });

  it("S05-037 — Promote canary clears cohort", async () => {
    await setupTwoLiveCanaries();

    const result = await promotePolicy(POLICY_ID, "2");

    assertEmptySuccess(result);

    const v2 = await getRoutingPolicy(POLICY_ID, "2");
    expect(v2?.status).toBe("active");
    expect(v2?.canary_installation_ids).toBeNull();

    const v1 = await getRoutingPolicy(POLICY_ID, POLICY_VERSION);
    expect(v1?.status).toBe("superseded");
    expect(v1?.canary_installation_ids).toBeNull();

    const rows = await queryAll(
      `SELECT version, status, canary_installation_ids
       FROM routing_policy WHERE policy_id = ? ORDER BY version`,
      [POLICY_ID],
    );
    expect(rows).toHaveLength(2);
    expect(rows.every((row) => row.canary_installation_ids === null)).toBe(
      true,
    );

    const audits = await getAudits("routing_policy_promote", policyTarget("2"));
    expect(audits).toHaveLength(1);
    expect(audits[0]?.operator_id).toBe(OPERATOR_ID);
    expect(audits[0]?.before_pointer).toBeNull();
    expect(audits[0]?.after_pointer).toBe(policyTarget("2"));
  });

  it("S05-038 — Unknown promote is policy_version_not_found", async () => {
    await publishStandardV1();
    const before = await snapshotPolicy(POLICY_VERSION);

    const result = await promotePolicy(POLICY_ID, "42");

    assertControlError(result, 404, "policy_version_not_found");
    await assertNoPromoteMutation(POLICY_VERSION, before, 0);
    expect(await getRoutingPolicy(POLICY_ID, "42")).toBeNull();
    expect(
      await getAudits("routing_policy_promote", policyTarget("42")),
    ).toHaveLength(0);
  });

  it("S05-039 — Promote already-active is illegal_policy_transition", async () => {
    await setupActiveV1();
    const before = await snapshotPolicy(POLICY_VERSION);
    expect(before.status).toBe("active");

    const result = await promotePolicy(POLICY_ID, POLICY_VERSION);

    assertControlError(result, 409, "illegal_policy_transition");
    await assertNoPromoteMutation(POLICY_VERSION, before, 1);
  });

  it("S05-040 — Promote superseded is illegal_policy_transition", async () => {
    await setupV1SupersededV2Active();
    const v1Before = await snapshotPolicy(POLICY_VERSION);
    const v2Before = await snapshotPolicy("2");
    expect(v1Before.status).toBe("superseded");
    expect(v2Before.status).toBe("active");

    const result = await promotePolicy(POLICY_ID, POLICY_VERSION);

    assertControlError(result, 409, "illegal_policy_transition");
    await assertNoPromoteMutation(POLICY_VERSION, v1Before, 1);
    expect(await getRoutingPolicy(POLICY_ID, "2")).toEqual(v2Before);
    expect(
      await getAudits("routing_policy_promote", policyTarget("2")),
    ).toHaveLength(1);
  });

  it("S05-041 — Promote without operator auth", async () => {
    await publishStandardV1();
    const before = await snapshotPolicy(POLICY_VERSION);

    const result = await controlFetch(promotePath(POLICY_VERSION), {
      auth: "wrong",
    });

    assertControlError(result, 401, "unauthorized");
    await assertNoPromoteMutation(POLICY_VERSION, before, 0);
  });
});
