/**
 * P3.6 — Complimentary grants, ceilings, adjustments, suspension (H-AP).
 */

import { env, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import {
  CHANNEL_VERSIONS,
  grantIdComp,
  sha256Hex,
} from "vendor-contracts";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { addDuration } from "../../src/coverage/calendar";
import {
  createCapabilityRegistry,
  setCapabilityRegistry,
  type Manifest,
} from "../../src/capability";
import {
  applyAllMigrations,
  clearCapturedVendorEmails,
  clearConfigCache,
  CAPABILITY_VERSION,
  coverClinic,
  coverClinicSigner,
  encodeVendorAssertion,
  getCapturedVendorEmails,
  getCapabilities,
  getVendorTestClockIso,
  invoke,
  mintAat,
  mintVendorAccessJwt,
  newClinic,
  newScenario,
  queryOne,
  visitSummaryManifest,
  resetPlatformState,
  runScheduled,
  setTestClock,
  setupPromotedFakePolicy,
  setupVendorHarness,
  vendorCall,
  vendorClassH,
  vendorTableCount,
  VENDOR_OPERATOR_EMAIL,
  type VendorResultEnvelope,
} from "./harness";

const CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;

function planChangedManifest(): Manifest {
  const base = visitSummaryManifest();
  return {
    ...base,
    Identity: {
      ...base.Identity,
      capabilityId: "clinic.plan_changed",
      title: "Plan changed",
    },
    Access: {
      ...base.Access,
      requiredCapabilityScope: "ai.plan_changed",
    },
  };
}

function registerP36Capabilities(): void {
  setCapabilityRegistry(
    createCapabilityRegistry([visitSummaryManifest(), planChangedManifest()]),
    { replace: true },
  );
}

function discoveryCapabilityIds(
  body: Record<string, unknown> | null,
): string[] {
  const manifests = body?.manifests;
  if (!Array.isArray(manifests)) {
    return [];
  }
  return manifests
    .map((entry) => {
      if (typeof entry !== "object" || entry === null) {
        return null;
      }
      const identity = (entry as { Identity?: { capabilityId?: string } })
        .Identity;
      return typeof identity?.capabilityId === "string"
        ? identity.capabilityId
        : null;
    })
    .filter((id): id is string => id !== null);
}

const PLAN_ID = "live-monthly";
const PLAN_VERSION = 1;
const PLAN_DISPLAY_NAME = "Live Monthly";
const PLAN_MAX_ALLOWANCE = 10_000;

type GrantResultEnvelope = VendorResultEnvelope & {
  result: string;
  receipt?: Record<string, unknown>;
};

type ExtendedVendorMethod =
  | Parameters<typeof vendorCall>[0]
  | "suspend"
  | "resume"
  | "inspectCoverage"
  | "setCeilingPolicy"
  | "listGrantsForVoid";

const extendedVendorCall = vendorCall as (
  method: ExtendedVendorMethod,
  args: Record<string, unknown>,
  opts?: {
    accessJwt?: string;
    assertion?: Record<string, unknown>;
  },
) => Promise<GrantResultEnvelope>;

type DoTermRow = {
  term_id: string;
  state: string;
  starts_at: string | null;
  ends_at: string | null;
  calendar_start: string | null;
};

function quotaDoStub(installationId: string) {
  return env.DO.get(env.DO.idFromName(installationId));
}

function sqlSelect<T extends Record<string, unknown>>(
  state: DurableObjectState,
  query: string,
): T[] {
  const storage = state.storage as DurableObjectStorage & {
    sql?: { exec: (q: string) => Iterable<T> };
  };
  if (!storage.sql) {
    return [];
  }
  return [...storage.sql.exec(query)];
}

async function readDoTerms(installationId: string): Promise<DoTermRow[]> {
  return runInDurableObject(quotaDoStub(installationId), async (_instance, state) =>
    sqlSelect<DoTermRow>(
      state,
      `SELECT term_id, state, starts_at, ends_at, calendar_start
       FROM term ORDER BY position ASC`,
    ),
  );
}

async function readActiveTermEndsAt(
  installationId: string,
): Promise<string | null> {
  const rows = await runInDurableObject(
    quotaDoStub(installationId),
    async (_instance, state) =>
      sqlSelect<{ ends_at: string | null }>(
        state,
        "SELECT ends_at FROM term WHERE state = 'active' LIMIT 1",
      ),
  );
  return rows[0]?.ends_at ?? null;
}

async function buildComplimentaryEnvelope(input: {
  orgId: string;
  grantId: string;
  unit?: "day" | "month";
  count?: number;
  operatorEmail?: string;
  reason?: string;
  allowanceCredits?: number;
  ceilingOverride?: Record<string, unknown>;
  kind?: "term" | "term_adjustment";
  adjustment?: Record<string, unknown>;
  planVersion?: number;
}): Promise<Record<string, unknown>> {
  const signerCredentialId = coverClinicSigner().signerCredentialId;
  const ref = crypto.randomUUID().replace(/-/g, "");
  const contentSha256 = await sha256Hex(new TextEncoder().encode(ref));
  const source: Record<string, unknown> = {
    kind: "complimentary",
    ref,
  };
  if (input.operatorEmail !== undefined) {
    source.operator_email = input.operatorEmail;
  }
  if (input.reason !== undefined) {
    source.reason = input.reason;
  }

  const unit = input.unit ?? "day";
  const count = input.count ?? 14;

  const envelope: Record<string, unknown> = {
    contract_version: CONTRACT_VERSION,
    grant_id: input.grantId,
    org_id: input.orgId,
    kind: input.kind ?? "term",
    placement: "queue",
    source,
    plan: {
      plan_id: PLAN_ID,
      plan_version: input.planVersion ?? PLAN_VERSION,
    },
    duration: { unit, count },
    allowance_credits: input.allowanceCredits ?? PLAN_MAX_ALLOWANCE,
    grace: { days: 7, cap_rule: "proportional" },
    evidence: {
      content_sha256: contentSha256,
      approvals: [{ credential_id: signerCredentialId, assertion: "stub" }],
    },
  };

  if (input.ceilingOverride !== undefined) {
    envelope.ceiling_override = input.ceilingOverride;
    envelope.evidence = {
      content_sha256: contentSha256,
      approvals: [
        { credential_id: signerCredentialId, assertion: "stub" },
        { credential_id: "cred-002", assertion: "stub" },
      ],
    };
  }

  if (input.adjustment !== undefined) {
    envelope.adjustment = input.adjustment;
  }

  return envelope;
}

async function operationForHpGrant(input: {
  accessJwt: string;
  envelope: Record<string, unknown>;
}): Promise<Record<string, unknown>> {
  return {
    op: "grant",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      envelope: input.envelope,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: getVendorTestClockIso() ?? new Date().toISOString(),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
}

async function operationForCeilingOverride(input: {
  accessJwt: string;
  envelope: Record<string, unknown>;
}): Promise<Record<string, unknown>> {
  return {
    op: "ceiling_override",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      envelope: input.envelope,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: getVendorTestClockIso() ?? new Date().toISOString(),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
}

async function hpComplimentaryGrant(input: {
  envelope: Record<string, unknown>;
  accessJwt?: string;
  ceilingOverrideOperation?: Record<string, unknown>;
}): Promise<GrantResultEnvelope> {
  const signer = coverClinicSigner();
  const accessJwt = input.accessJwt ?? (await mintVendorAccessJwt());
  const operation = await operationForHpGrant({
    accessJwt,
    envelope: input.envelope,
  });
  const assertion = encodeVendorAssertion(
    await signer.signerAuthenticator.assert({
      operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  const grantArgs: Record<string, unknown> = {
    contract_version: CONTRACT_VERSION,
    envelope: input.envelope,
    signer_credential_id: signer.signerCredentialId,
    operation,
    assertion,
  };
  if (input.ceilingOverrideOperation !== undefined) {
    grantArgs.ceiling_override_operation = input.ceilingOverrideOperation;
  }
  return extendedVendorCall("grant", grantArgs, { accessJwt });
}

async function encodeCeilingOverrideAssertion(input: {
  envelope: Record<string, unknown>;
  accessJwt: string;
}): Promise<{
  assertion: Record<string, string>;
  operation: Record<string, unknown>;
}> {
  const signer = coverClinicSigner();
  const operation = await operationForCeilingOverride({
    accessJwt: input.accessJwt,
    envelope: input.envelope,
  });
  const assertion = encodeVendorAssertion(
    await signer.signerAuthenticator.assert({
      operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  return { assertion, operation };
}

function parseAlertBodies(): Array<Record<string, unknown>> {
  return getCapturedVendorEmails().map(
    (email) => JSON.parse(email.text) as Record<string, unknown>,
  );
}

const LAUNCH_CEILING_POLICY = {
  per_grant_max_days: 31,
  per_grant_max_allowance_months: 1,
  window_days: 90,
  window_max_days: 62,
  window_max_allowance_months: 2,
  max_paid_grace_days: 7,
  paid_cap_rule: "proportional",
} as const;
type CeilingPolicyInput = {
  per_grant_max_days: number;
  per_grant_max_allowance_months: number;
  window_days: number;
  window_max_days: number;
  window_max_allowance_months: number;
  max_paid_grace_days: number;
  paid_cap_rule: string;
};

async function readDoLedger(installationId: string): Promise<{
  terms: Record<string, unknown>[];
  grants: Record<string, unknown>[];
  reservations: unknown;
}> {
  return runInDurableObject(quotaDoStub(installationId), async (_instance, state) => {
    const terms = sqlSelect<Record<string, unknown>>(
      state,
      "SELECT * FROM term ORDER BY position ASC",
    );
    const grants = sqlSelect<Record<string, unknown>>(
      state,
      "SELECT * FROM grant ORDER BY applied_at ASC",
    );
    const hotRows = sqlSelect<{ reservations: string }>(
      state,
      "SELECT reservations FROM hot LIMIT 1",
    );
    const reservations = JSON.parse(hotRows[0]?.reservations ?? "[]") as unknown;
    return { terms, grants, reservations };
  });
}

async function countCeilingPolicyRows(): Promise<number> {
  const row = await env.DB.prepare(
    "SELECT COUNT(*) AS count FROM ceiling_policy",
  ).first<{ count: number }>();
  return row?.count ?? 0;
}

async function countCeilingPolicyCommands(): Promise<number> {
  const row = await env.DB.prepare(
    "SELECT COUNT(*) AS count FROM ceiling_policy_command",
  ).first<{ count: number }>();
  return row?.count ?? 0;
}

async function countDoGrantRows(installationId: string): Promise<number> {
  const rows = await runInDurableObject(
    quotaDoStub(installationId),
    async (_instance, state) =>
      sqlSelect<{ count: number }>(state, "SELECT COUNT(*) AS count FROM grant"),
  );
  return rows[0]?.count ?? 0;
}

function termIntervalsOverlap(
  active: DoTermRow,
  queued: DoTermRow,
): boolean {
  if (
    !active.starts_at ||
    !active.ends_at ||
    !queued.starts_at ||
    !queued.ends_at
  ) {
    return false;
  }
  return (
    Date.parse(active.starts_at) < Date.parse(queued.ends_at) &&
    Date.parse(queued.starts_at) < Date.parse(active.ends_at)
  );
}

async function operationForSetCeilingPolicy(input: {
  accessJwt: string;
  policy?: Partial<CeilingPolicyInput>;
}): Promise<Record<string, unknown>> {
  const policy = { ...LAUNCH_CEILING_POLICY, ...input.policy };
  return {
    op: "setCeilingPolicy",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      ...policy,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: getVendorTestClockIso() ?? new Date().toISOString(),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
}

async function hpSetCeilingPolicy(input: {
  accessJwt?: string;
  operation?: Record<string, unknown>;
  assertion?: Record<string, string>;
  policy?: Partial<CeilingPolicyInput>;
}): Promise<VendorResultEnvelope> {
  const signer = coverClinicSigner();
  const accessJwt = input.accessJwt ?? (await mintVendorAccessJwt());
  const operation =
    input.operation ??
    (await operationForSetCeilingPolicy({ accessJwt, policy: input.policy }));
  const assertion =
    input.assertion ??
    encodeVendorAssertion(
      await signer.signerAuthenticator.assert({
        operation,
        rpId: env.WEBAUTHN_RP_ID,
        origin: env.WEBAUTHN_ORIGIN,
        up: true,
        uv: true,
      }),
    );
  return extendedVendorCall(
    "setCeilingPolicy",
    {
      contract_version: CONTRACT_VERSION,
      ...LAUNCH_CEILING_POLICY,
      ...input.policy,
      signer_credential_id: signer.signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt },
  );
}

async function publishPlanVersionTwo(
  capabilities: string[],
  maxAllowance = PLAN_MAX_ALLOWANCE,
): Promise<void> {
  const signer = coverClinicSigner();
  const accessJwt = await mintVendorAccessJwt();
  const operation = {
    op: "publishPlanVersion",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: accessJwt,
      plan_id: PLAN_ID,
      version: 2,
      display_name: PLAN_DISPLAY_NAME,
      capabilities,
      max_cost_class: 2,
      concurrency_limit: 4,
      max_allowance_per_month: maxAllowance,
    },
    actor_email: VENDOR_OPERATOR_EMAIL,
    issued_at: getVendorTestClockIso() ?? new Date().toISOString(),
    nonce: crypto.randomUUID(),
    contract_version: CONTRACT_VERSION,
  };
  const assertion = encodeVendorAssertion(
    await signer.signerAuthenticator.assert({
      operation,
      rpId: env.WEBAUTHN_RP_ID,
      origin: env.WEBAUTHN_ORIGIN,
      up: true,
      uv: true,
    }),
  );
  const published = await vendorCall(
    "publishPlanVersion",
    {
      contract_version: CONTRACT_VERSION,
      plan_id: PLAN_ID,
      version: 2,
      display_name: PLAN_DISPLAY_NAME,
      capabilities,
      max_cost_class: 2,
      concurrency_limit: 4,
      max_allowance_per_month: maxAllowance,
      signer_credential_id: signer.signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt },
  );
  expect(published.result).toBe("ok");
}

beforeAll(async () => {
  await applyAllMigrations(env.DB);
  registerP36Capabilities();
  await setupVendorHarness();
});

beforeEach(async () => {
  vi.restoreAllMocks();
  await resetPlatformState();
  registerP36Capabilities();
  await setupVendorHarness();
});

describe("complimentary grants, ceilings, adjustments, suspension", () => {
  it("R4-PG4 complimentary attribution uses the verified signer and mismatched evidence credential is rejected", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    const signerCredentialId = coverClinicSigner().signerCredentialId;
    const initialGrantCount = await countDoGrantRows(scenario.installationId);
    const accessJwt = await mintVendorAccessJwt();
    const before = await vendorTableCount("assertion_used");
    const badGrantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const mismatched = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId: badGrantId,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "mismatched attribution",
    });
    (mismatched.evidence as Record<string, unknown>).approvals = [
      { credential_id: "cred-elsewhere", assertion: "stub" },
    ];
    const rejected = await hpComplimentaryGrant({ envelope: mismatched, accessJwt });
    expect(rejected.result).toBe("rejected");
    expect(rejected.code).toBe("bad_assertion");
    expect(await vendorTableCount("assertion_used")).toBe(before);
    expect(await countDoGrantRows(scenario.installationId)).toBe(initialGrantCount);

    const grantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const envelope = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId,
      operatorEmail: "untrusted-source@example.test",
      reason: "verified attribution",
    });
    const applied = await hpComplimentaryGrant({ envelope, accessJwt });
    expect(applied.result).toBe("applied");
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));
    const ledger = await queryOne<{
      operator_credential_id: string;
      operator_email: string | null;
      applied_at: string;
    }>(
      `SELECT operator_credential_id, operator_email, applied_at
       FROM grant_ledger WHERE grant_id = ?`,
      [grantId],
    );
    expect(ledger).toEqual({
      operator_credential_id: signerCredentialId,
      operator_email: VENDOR_OPERATOR_EMAIL,
      applied_at: expect.any(String),
    });
    const ledgerObject = await env.R2.get(`grant-ledger/${grantId}.ndjson`);
    expect(ledgerObject).not.toBeNull();
    const ledgerR2 = JSON.parse((await ledgerObject!.text()).trim().split("\n")[0]!) as Record<string, unknown>;
    expect(ledgerR2).toMatchObject({
      operator_credential_id: signerCredentialId,
      operator_email: VENDOR_OPERATOR_EMAIL,
    });
    const listed = await extendedVendorCall("listGrantsForVoid", {
      contract_version: CONTRACT_VERSION,
      credential_id: signerCredentialId,
      window: {
        applied_from: ledger!.applied_at,
        applied_to: new Date(Date.parse(ledger!.applied_at) + 1).toISOString(),
      },
    }, { accessJwt });
    expect(listed.result).toBe("ok");
    expect(JSON.parse(listed.detail)).toEqual(expect.arrayContaining([
      expect.objectContaining({ grant_id: grantId, operator_credential_id: signerCredentialId }),
    ]));
  });

  it("R4-PG3 accepted complimentary command survives a lost dispatch and is resumed by the scheduled dispatcher", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    const signerCredentialId = coverClinicSigner().signerCredentialId;
    const initialGrantCount = await countDoGrantRows(scenario.installationId);
    const grantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const envelope = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId,
      count: 14,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "accepted command recovery",
    });
    const acceptedAt = getVendorTestClockIso() ?? new Date().toISOString();
    const realGet = env.DO.get.bind(env.DO);
    const getSpy = vi.spyOn(env.DO, "get").mockImplementation((id) => {
      const stub = realGet(id);
      return {
        fetch: async (input: RequestInfo | URL, init?: RequestInit) => {
          const body = typeof init?.body === "string" ? JSON.parse(init.body) as Record<string, unknown> : {};
          if (body.kind === "apply_grant") return new Response(null, { status: 503 });
          return stub.fetch(input, init);
        },
      } as DurableObjectStub;
    });
    let unavailable: GrantResultEnvelope;
    try {
      unavailable = await hpComplimentaryGrant({ envelope });
    } finally {
      getSpy.mockRestore();
    }
    expect(unavailable.result).toBe("transient");
    expect(await queryOne<{
      command_state: string;
      accepted_at: string;
      accepted_actor: string;
      signer_credential_id: string;
      accepted_command: string;
    }>(
      `SELECT command_state, accepted_at, accepted_actor, signer_credential_id, accepted_command
       FROM grant_claim WHERE grant_id = ?`,
      [grantId],
    )).toMatchObject({
      command_state: "accepted",
      accepted_at: acceptedAt,
      accepted_actor: VENDOR_OPERATOR_EMAIL,
      signer_credential_id: signerCredentialId,
    });
    expect(JSON.parse((await queryOne<{ accepted_command: string }>(
      "SELECT accepted_command FROM grant_claim WHERE grant_id = ?", [grantId],
    ))!.accepted_command).envelope).toEqual(envelope);

    await setTestClock(new Date(Date.parse(acceptedAt) + 2 * 60_000).toISOString());
    await runScheduled("*/5 * * * *");

    expect(await queryOne<{ state: string; command_state: string }>(
      "SELECT state, command_state FROM grant_claim WHERE grant_id = ?", [grantId],
    )).toEqual({ state: "completed", command_state: "completed" });
    expect(await countDoGrantRows(scenario.installationId)).toBe(initialGrantCount + 1);
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));
    expect(await queryOne<{ operator_credential_id: string; operator_email: string }>(
      "SELECT operator_credential_id, operator_email FROM grant_ledger WHERE grant_id = ?",
      [grantId],
    )).toEqual({
      operator_credential_id: signerCredentialId,
      operator_email: VENDOR_OPERATOR_EMAIL,
    });
  });

  it("R4-PG2 a complimentary DO outage stays pending and the same claim completes on retry", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    const grantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const envelope = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId,
      count: 14,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "RM14 retry",
    });
    const realGet = env.DO.get.bind(env.DO);
    const getSpy = vi.spyOn(env.DO, "get").mockImplementation((id) => {
      const stub = realGet(id);
      return {
        fetch: async (input: RequestInfo | URL, init?: RequestInit) => {
          const body = typeof init?.body === "string" ? JSON.parse(init.body) as Record<string, unknown> : {};
          if (body.kind === "apply_grant") return new Response(null, { status: 503 });
          return stub.fetch(input, init);
        },
      } as DurableObjectStub;
    });
    let unavailable: GrantResultEnvelope;
    try {
      unavailable = await hpComplimentaryGrant({ envelope });
    } finally {
      getSpy.mockRestore();
    }
    expect(unavailable.result).toBe("transient");
    expect(unavailable.detail).toBe("unavailable");
    expect(await queryOne<{ state: string }>("SELECT state FROM grant_claim WHERE grant_id = ?", [grantId])).toEqual({ state: "pending" });

    const retried = await hpComplimentaryGrant({ envelope });
    expect(retried.result).toBe("applied");
    expect(retried.receipt?.grant_id).toBe(grantId);
    expect(await queryOne<{ state: string }>("SELECT state FROM grant_claim WHERE grant_id = ?", [grantId])).toEqual({ state: "completed" });
  });

  it("E2E-P3.6-01 A20 14-day complimentary grant to a paying clinic queues after current coverage", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);

    const grantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const envelope = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId,
      count: 14,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "customer goodwill",
    });

    const applied = await hpComplimentaryGrant({ envelope });
    expect(applied.result).toBe("applied");
    expect(applied.code).toBe("");

    const terms = await readDoTerms(scenario.installationId);
    expect(terms.filter((row) => row.state === "active")).toHaveLength(1);
    expect(terms.filter((row) => row.state === "queued")).toHaveLength(1);

    clearCapturedVendorEmails();
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));
    const firstAlarmBodies = parseAlertBodies();
    const al11First = firstAlarmBodies.filter((body) => body.code === "AL-11");
    expect(al11First.length).toBeGreaterThanOrEqual(1);
    const attentionAl11 = al11First.find((body) => body.attention === true);
    expect(attentionAl11).toBeTruthy();
    const opParams = (attentionAl11!.operation as { params: Record<string, unknown> })
      .params;
    const source = (opParams.source as Record<string, unknown>) ?? {};
    expect(source.operator_email).toBe(VENDOR_OPERATOR_EMAIL);
    expect(source.reason).toBe("customer goodwill");

    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));
    const secondAlarmBodies = parseAlertBodies();
    const al11ForGrant = secondAlarmBodies.filter(
      (body) =>
        body.code === "AL-11" &&
        (body.operation as { params?: { grant_id?: string } })?.params
          ?.grant_id === grantId,
    );
    expect(al11ForGrant).toHaveLength(al11First.length);
  });

  it("E2E-P3.6-02 A27 365-day complimentary grant is exceeds_ceiling unless a second assertion overrides it", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);

    const grantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const baseEnvelope = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId,
      count: 365,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "long trial",
    });

    const assertionsBefore = await vendorTableCount("assertion_used");
    const rejected = await hpComplimentaryGrant({ envelope: baseEnvelope });
    expect(rejected.result).toBe("rejected");
    expect(rejected.code).toBe("exceeds_ceiling");
    expect(await vendorTableCount("assertion_used")).toBe(assertionsBefore);

    const accessJwt = await mintVendorAccessJwt();
    // R2-P2: the second approval is signed over the exact submitted envelope
    // minus ceiling_override (including the two-approval evidence).
    const overrideEnvelopeBase = {
      ...baseEnvelope,
      evidence: {
        ...(baseEnvelope.evidence as Record<string, unknown>),
        approvals: [
          { credential_id: coverClinicSigner().signerCredentialId, assertion: "stub" },
          { credential_id: "cred-002", assertion: "stub" },
        ],
      },
    };
    const overrideEncoded = await encodeCeilingOverrideAssertion({
      envelope: overrideEnvelopeBase,
      accessJwt,
    });
    const withOverride = {
      ...overrideEnvelopeBase,
      ceiling_override: overrideEncoded.assertion,
    };

    clearCapturedVendorEmails();
    const applied = await hpComplimentaryGrant({
      envelope: withOverride,
      accessJwt,
      ceilingOverrideOperation: overrideEncoded.operation,
    });
    expect(applied.result).toBe("applied");
    const replay = await hpComplimentaryGrant({
      envelope: withOverride,
      accessJwt,
      ceilingOverrideOperation: overrideEncoded.operation,
    });
    expect(replay.result).toBe("already_applied");
    expect(replay.receipt).toEqual(applied.receipt);

    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));
    const al12Bodies = parseAlertBodies().filter((body) => body.code === "AL-12");
    expect(al12Bodies).toHaveLength(1);

    const grantOperation = await operationForHpGrant({
      accessJwt,
      envelope: baseEnvelope,
    });
    const grantAssertion = encodeVendorAssertion(
      await coverClinicSigner().signerAuthenticator.assert({
        operation: grantOperation,
        rpId: env.WEBAUTHN_RP_ID,
        origin: env.WEBAUTHN_ORIGIN,
        up: true,
        uv: true,
      }),
    );
    const badOverrideEnvelope = {
      ...baseEnvelope,
      grant_id: await grantIdComp(crypto.randomUUID().replace(/-/g, "")),
      ceiling_override: grantAssertion,
      evidence: {
        ...(baseEnvelope.evidence as Record<string, unknown>),
        approvals: [
          { credential_id: coverClinicSigner().signerCredentialId, assertion: "stub" },
          { credential_id: "cred-002", assertion: "stub" },
        ],
      },
    };
    const badOverride = await hpComplimentaryGrant({
      envelope: badOverrideEnvelope,
      accessJwt,
    });
    expect(badOverride.result).toBe("rejected");
  });

  it("R2-P2 second ceiling approval is bound to the current operation: changed envelope, actor or version, or a stale approval never reaches coverage dispatch", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    const accessJwt = await mintVendorAccessJwt();

    const usedBefore = await vendorTableCount("assertion_used");
    const grantsBefore = await countDoGrantRows(scenario.installationId);

    // Submits a 365-day grant whose ceiling override is signed over a
    // purpose-mismatched operation; each attempt must be rejected before
    // coverage dispatch.
    const overrideAttempt = async (input: {
      reason: string;
      mutateOperation?: (operation: Record<string, unknown>) => void;
      mutateEnvelopeBase?: (
        envelopeBase: Record<string, unknown>,
      ) => void;
    }): Promise<GrantResultEnvelope> => {
      const grantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
      const signer = coverClinicSigner();
      const envelope = await buildComplimentaryEnvelope({
        orgId: scenario.orgId,
        grantId,
        count: 365,
        operatorEmail: VENDOR_OPERATOR_EMAIL,
        reason: input.reason,
        ceilingOverride: {},
      });
      // R2-P2: the bound form is the submitted envelope minus
      // ceiling_override (two-approval evidence kept). Deep copy so the
      // mismatch mutation cannot leak into the submitted envelope.
      delete envelope.ceiling_override;
      const envelopeBase = JSON.parse(
        JSON.stringify(envelope),
      ) as Record<string, unknown>;
      input.mutateEnvelopeBase?.(envelopeBase);

      const overrideOperation: Record<string, unknown> = {
        op: "ceiling_override",
        params: {
          contract_version: CONTRACT_VERSION,
          access_jwt: accessJwt,
          envelope: envelopeBase,
        },
        actor_email: VENDOR_OPERATOR_EMAIL,
        issued_at: getVendorTestClockIso() ?? new Date().toISOString(),
        nonce: crypto.randomUUID(),
        contract_version: CONTRACT_VERSION,
      };
      input.mutateOperation?.(overrideOperation);
      const overrideAssertion = encodeVendorAssertion(
        await signer.signerAuthenticator.assert({
          operation: overrideOperation,
          rpId: env.WEBAUTHN_RP_ID,
          origin: env.WEBAUTHN_ORIGIN,
          up: true,
          uv: true,
        }),
      );

      const submittedEnvelope = {
        ...envelope,
        ceiling_override: overrideAssertion,
      };
      const grantOperation = await operationForHpGrant({
        accessJwt,
        envelope: submittedEnvelope,
      });
      const grantAssertion = encodeVendorAssertion(
        await signer.signerAuthenticator.assert({
          operation: grantOperation,
          rpId: env.WEBAUTHN_RP_ID,
          origin: env.WEBAUTHN_ORIGIN,
          up: true,
          uv: true,
        }),
      );
      return extendedVendorCall(
        "grant",
        {
          contract_version: CONTRACT_VERSION,
          envelope: submittedEnvelope,
          signer_credential_id: signer.signerCredentialId,
          operation: grantOperation,
          assertion: grantAssertion,
          ceiling_override_operation: overrideOperation,
        },
        { accessJwt },
      );
    };

    // Changed envelope (org_id, grant_id and the rest are inside the
    // envelope, so any drift breaks the binding).
    const changedEnvelope = await overrideAttempt({
      reason: "changed envelope",
      mutateEnvelopeBase: (base) => {
        (base.duration as Record<string, unknown>).count = 30;
      },
    });
    expect(changedEnvelope.result).toBe("rejected");
    expect(changedEnvelope.code).toBe("assertion_invalid");

    // Wrong top-level negotiated version.
    const changedVersion = await overrideAttempt({
      reason: "changed version",
      mutateOperation: (operation) => {
        operation.contract_version = 2;
      },
    });
    expect(changedVersion.result).toBe("rejected");
    expect(changedVersion.code).toBe("assertion_invalid");

    // Wrong actor.
    const changedActor = await overrideAttempt({
      reason: "changed actor",
      mutateOperation: (operation) => {
        operation.actor_email = "other-operator@clinic.test";
      },
    });
    expect(changedActor.result).toBe("rejected");
    expect(changedActor.code).toBe("actor_email_mismatch");

    // Stale second approval (issued_at 6 minutes old).
    const clockIso = getVendorTestClockIso() ?? new Date().toISOString();
    const staleIssuedAt = new Date(
      Date.parse(clockIso) - 6 * 60 * 1000,
    ).toISOString();
    const staleApproval = await overrideAttempt({
      reason: "stale approval",
      mutateOperation: (operation) => {
        operation.issued_at = staleIssuedAt;
      },
    });
    expect(staleApproval.result).toBe("rejected");
    expect(staleApproval.code).toBe("assertion_expired");

    // Nothing reached coverage dispatch and no claim or AL-12 was emitted.
    expect(await vendorTableCount("assertion_used")).toBe(usedBefore);
    expect(await countDoGrantRows(scenario.installationId)).toBe(
      grantsBefore,
    );
    const al12Bodies = parseAlertBodies().filter(
      (body) => body.code === "AL-12",
    );
    expect(al12Bodies).toHaveLength(0);
  });

  it("R4-D1 / R2-P2 a correctly bound ceiling override applies once; replay returns the exact result and no second term", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    const accessJwt = await mintVendorAccessJwt();
    const signer = coverClinicSigner();

    const grantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const envelope = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId,
      count: 365,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "long trial override",
      ceilingOverride: {},
    });
    // R2-P2: the second approval is signed over the submitted envelope
    // minus ceiling_override.
    delete envelope.ceiling_override;
    const overrideOperation = await operationForCeilingOverride({
      accessJwt,
      envelope,
    });
    const overrideAssertion = encodeVendorAssertion(
      await signer.signerAuthenticator.assert({
        operation: overrideOperation,
        rpId: env.WEBAUTHN_RP_ID,
        origin: env.WEBAUTHN_ORIGIN,
        up: true,
        uv: true,
      }),
    );
    const submittedEnvelope = {
      ...envelope,
      ceiling_override: overrideAssertion,
    };
    const grantOperation = await operationForHpGrant({
      accessJwt,
      envelope: submittedEnvelope,
    });
    const grantAssertion = encodeVendorAssertion(
      await signer.signerAuthenticator.assert({
        operation: grantOperation,
        rpId: env.WEBAUTHN_RP_ID,
        origin: env.WEBAUTHN_ORIGIN,
        up: true,
        uv: true,
      }),
    );
    const grantArgs = {
      contract_version: CONTRACT_VERSION,
      envelope: submittedEnvelope,
      signer_credential_id: signer.signerCredentialId,
      operation: grantOperation,
      assertion: grantAssertion,
      ceiling_override_operation: overrideOperation,
    };

    const applied = await extendedVendorCall("grant", grantArgs, {
      accessJwt,
    });
    expect(applied.result).toBe("applied");
    const termsAfterApply = await readDoTerms(scenario.installationId);

    // Exact replay of the identical call: the completed result, once.
    const replay = await extendedVendorCall("grant", grantArgs, {
      accessJwt,
    });
    expect(replay.result).toBe("already_applied");
    expect(replay.receipt).toEqual(applied.receipt);
    expect(await readDoTerms(scenario.installationId)).toEqual(termsAfterApply);

    // Reusing both signed operations with a changed envelope (fresh
    // grant_id) fails: the main operation no longer matches the args.
    const changedEnvelope = {
      ...submittedEnvelope,
      grant_id: await grantIdComp(crypto.randomUUID().replace(/-/g, "")),
    };
    const reuse = await extendedVendorCall(
      "grant",
      {
        ...grantArgs,
        envelope: changedEnvelope,
      },
      { accessJwt },
    );
    expect(reuse.result).toBe("rejected");
    expect(reuse.code).toBe("assertion_invalid");
  });

  it("E2E-P3.6-03 90-day window accepts 31 plus 31 days and rejects a further day", async () => {
    const scenarioA = await newScenario();
    await coverClinic(scenarioA);

    for (let index = 0; index < 2; index += 1) {
      const grantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
      const envelope = await buildComplimentaryEnvelope({
        orgId: scenarioA.orgId,
        grantId,
        count: 31,
        operatorEmail: VENDOR_OPERATOR_EMAIL,
        reason: `window grant ${index}`,
      });
      const applied = await hpComplimentaryGrant({ envelope });
      expect(applied.result, JSON.stringify(applied)).toBe("applied");
    }

    const thirdGrantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const thirdEnvelope = await buildComplimentaryEnvelope({
      orgId: scenarioA.orgId,
      grantId: thirdGrantId,
      count: 1,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "one more day",
    });
    const third = await hpComplimentaryGrant({ envelope: thirdEnvelope });
    expect(third.result).toBe("rejected");
    expect(third.code).toBe("exceeds_ceiling");

    const scenarioB = await newScenario();
    await coverClinic(scenarioB);

    const firstGrantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const firstEnvelope = await buildComplimentaryEnvelope({
      orgId: scenarioB.orgId,
      grantId: firstGrantId,
      count: 31,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "org b first",
    });
    expect((await hpComplimentaryGrant({ envelope: firstEnvelope })).result).toBe(
      "applied",
    );

    const adjustGrantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const adjustEnvelope = await buildComplimentaryEnvelope({
      orgId: scenarioB.orgId,
      grantId: adjustGrantId,
      kind: "term_adjustment",
      count: 1,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "extend window",
      adjustment: { extend_days: 31 },
    });
    expect((await hpComplimentaryGrant({ envelope: adjustEnvelope })).result).toBe(
      "applied",
    );

    const extraGrantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const extraEnvelope = await buildComplimentaryEnvelope({
      orgId: scenarioB.orgId,
      grantId: extraGrantId,
      count: 1,
      allowanceCredits: 1,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "extra day",
    });
    const extra = await hpComplimentaryGrant({ envelope: extraEnvelope });
    expect(extra.result).toBe("rejected");
    expect(extra.code).toBe("exceeds_ceiling");
  });

  it("R4-D5 complimentary ceiling history survives same-org transfer and installation recreation", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    const firstInstallationId = scenario.installationId;
    for (let index = 0; index < 2; index += 1) {
      const grantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
      const envelope = await buildComplimentaryEnvelope({
        orgId: scenario.orgId,
        grantId,
        count: 31,
        operatorEmail: VENDOR_OPERATOR_EMAIL,
        reason: `R4-D5 pre-transfer contribution ${index}`,
      });
      expect((await hpComplimentaryGrant({ envelope })).result).toBe("applied");
    }

    const accessJwt = await mintVendorAccessJwt();
    const signer = coverClinicSigner();
    const params = {
      org_id: scenario.orgId,
      from_installation_id: firstInstallationId,
      reason: "R4-D5 transfer continuity",
    };
    const operation = {
      op: "beginTransfer",
      params: { contract_version: CONTRACT_VERSION, access_jwt: accessJwt, ...params },
      actor_email: VENDOR_OPERATOR_EMAIL,
      issued_at: getVendorTestClockIso() ?? new Date().toISOString(),
      nonce: crypto.randomUUID(),
      contract_version: CONTRACT_VERSION,
    };
    const assertion = encodeVendorAssertion(
      await signer.signerAuthenticator.assert({
        operation,
        rpId: env.WEBAUTHN_RP_ID,
        origin: env.WEBAUTHN_ORIGIN,
        up: true,
        uv: true,
      }),
    );
    const begun = await extendedVendorCall("beginTransfer", {
      contract_version: CONTRACT_VERSION,
      ...params,
      signer_credential_id: signer.signerCredentialId,
      operation,
      assertion,
    }, { accessJwt });
    expect(begun.result).toBe("ok");
    const transfer = JSON.parse(begun.detail) as { transfer_id: string };
    expect((await extendedVendorCall("transferOut", {
      contract_version: CONTRACT_VERSION,
      transfer_id: transfer.transfer_id,
    })).result).toBe("applied");
    expect((await extendedVendorCall("transferIn", {
      contract_version: CONTRACT_VERSION,
      transfer_id: transfer.transfer_id,
    })).result).toBe("applied");
    await newClinic(scenario);
    expect(scenario.installationId).not.toBe(firstInstallationId);

    const thirdGrantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const thirdEnvelope = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId: thirdGrantId,
      count: 1,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "R4-D5 post-transfer further day",
    });
    const rejected = await hpComplimentaryGrant({ envelope: thirdEnvelope });
    expect(rejected.result).toBe("rejected");
    expect(rejected.code).toBe("exceeds_ceiling");
    expect(await queryOne<{ count: number }>(
      `SELECT COUNT(*) AS count FROM complimentary_ceiling_claim
       WHERE org_id = ? AND status = 'applied'`,
      [scenario.orgId],
    )).toEqual({ count: 2 });
  });

  it("R4-D5 pending complimentary ceiling claim remains reserved beyond 90 days and exact retry counts once", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    const firstGrantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const firstEnvelope = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId: firstGrantId,
      count: 31,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "R4-D5 delayed reservation",
    });
    const acceptedAt = getVendorTestClockIso() ?? new Date().toISOString();
    const realGet = env.DO.get.bind(env.DO);
    const getSpy = vi.spyOn(env.DO, "get").mockImplementation((id) => {
      const stub = realGet(id);
      return {
        fetch: async (input: RequestInfo | URL, init?: RequestInit) => {
          const body = typeof init?.body === "string"
            ? JSON.parse(init.body) as Record<string, unknown>
            : {};
          if (body.kind === "apply_grant") return new Response(null, { status: 503 });
          return stub.fetch(input, init);
        },
      } as DurableObjectStub;
    });
    let unavailable: GrantResultEnvelope;
    try {
      unavailable = await hpComplimentaryGrant({ envelope: firstEnvelope });
    } finally {
      getSpy.mockRestore();
    }
    expect(unavailable.result).toBe("transient");
    expect(await queryOne<{ status: string }>(
      "SELECT status FROM complimentary_ceiling_claim WHERE grant_id = ?",
      [firstGrantId],
    )).toEqual({ status: "pending" });

    await setTestClock(new Date(Date.parse(acceptedAt) + 91 * 24 * 60 * 60 * 1000).toISOString());
    const secondGrantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const secondEnvelope = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId: secondGrantId,
      count: 31,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "R4-D5 second reserved contribution",
    });
    expect((await hpComplimentaryGrant({ envelope: secondEnvelope })).result).toBe("applied");

    const thirdGrantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const thirdEnvelope = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId: thirdGrantId,
      count: 1,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "R4-D5 third contribution",
    });
    const beforeThirdTouch = await vendorTableCount("assertion_used");
    const third = await hpComplimentaryGrant({ envelope: thirdEnvelope });
    expect(third.result).toBe("rejected");
    expect(third.code).toBe("exceeds_ceiling");
    expect(await vendorTableCount("assertion_used")).toBe(beforeThirdTouch);

    const retried = await hpComplimentaryGrant({ envelope: firstEnvelope });
    expect(retried.result).toBe("applied");
    expect(retried.receipt?.grant_id).toBe(firstGrantId);
    expect(await queryOne<{ count: number }>(
      `SELECT COUNT(*) AS count FROM complimentary_ceiling_claim
       WHERE org_id = ? AND status = 'applied'`,
      [scenario.orgId],
    )).toEqual({ count: 2 });
    expect(await queryOne<{ count: number }>(
      "SELECT COUNT(*) AS count FROM complimentary_ceiling_claim WHERE grant_id = ?",
      [firstGrantId],
    )).toEqual({ count: 1 });
    const firstClaim = await queryOne<{ applied_at: string; receipt: string }>(
      "SELECT applied_at, receipt FROM complimentary_ceiling_claim WHERE grant_id = ?",
      [firstGrantId],
    );
    expect(firstClaim?.applied_at).toBe(retried.receipt?.applied_at);
    expect(JSON.parse(firstClaim!.receipt)).toEqual(retried.receipt);
  });

  it("R4-D5 allowance-month history keeps each original plan denominator", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    const firstId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const first = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId: firstId,
      count: 1,
      allowanceCredits: PLAN_MAX_ALLOWANCE,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "R4-D5 original plan denominator",
    });
    expect((await hpComplimentaryGrant({ envelope: first })).result).toBe("applied");
    await publishPlanVersionTwo(getCapabilities(), PLAN_MAX_ALLOWANCE * 2);

    const secondId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const second = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId: secondId,
      count: 1,
      allowanceCredits: PLAN_MAX_ALLOWANCE * 2,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "R4-D5 new plan denominator",
      planVersion: 2,
    });
    expect((await hpComplimentaryGrant({ envelope: second })).result).toBe("applied");
    expect(await queryOne<{ allowance_denominator: number }>(
      "SELECT allowance_denominator FROM complimentary_ceiling_claim WHERE grant_id = ?",
      [firstId],
    )).toEqual({ allowance_denominator: PLAN_MAX_ALLOWANCE });
    expect(await queryOne<{ allowance_denominator: number }>(
      "SELECT allowance_denominator FROM complimentary_ceiling_claim WHERE grant_id = ?",
      [secondId],
    )).toEqual({ allowance_denominator: PLAN_MAX_ALLOWANCE * 2 });

    const thirdId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const third = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId: thirdId,
      count: 1,
      allowanceCredits: 1,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "R4-D5 third allowance fraction",
      planVersion: 2,
    });
    const rejected = await hpComplimentaryGrant({ envelope: third });
    expect(rejected.result).toBe("rejected");
    expect(rejected.code).toBe("exceeds_ceiling");
  });

  it("R4-D5 only a verified original-route no-effect seal releases a pending claim", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    const grantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const envelope = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId,
      count: 31,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "R4-D5 terminal no-effect seal",
    });
    const realGet = env.DO.get.bind(env.DO);
    let delayedApply: Record<string, unknown> | null = null;
    const getSpy = vi.spyOn(env.DO, "get").mockImplementation((id) => {
      const stub = realGet(id);
      return {
        fetch: async (input: RequestInfo | URL, init?: RequestInit) => {
          const body = typeof init?.body === "string"
            ? JSON.parse(init.body) as Record<string, unknown>
            : {};
          if (body.kind === "apply_grant") {
            delayedApply = body;
            return new Response(null, { status: 503 });
          }
          return stub.fetch(input, init);
        },
      } as DurableObjectStub;
    });
    let unavailable: GrantResultEnvelope;
    try {
      unavailable = await hpComplimentaryGrant({ envelope });
    } finally {
      getSpy.mockRestore();
    }
    expect(unavailable.result).toBe("transient");
    const policy = { window_max_days: 30 };
    const accessJwt = await mintVendorAccessJwt();
    const policyOperation = await operationForSetCeilingPolicy({ accessJwt, policy });
    expect((await hpSetCeilingPolicy({
      accessJwt,
      operation: policyOperation,
      policy,
    })).result).toBe("ok");

    const terminal = await hpComplimentaryGrant({ envelope });
    expect(terminal.result).toBe("rejected");
    expect(terminal.code).toBe("exceeds_ceiling");
    const sealed = await queryOne<{ status: string; receipt: string }>(
      `SELECT status, receipt FROM complimentary_ceiling_claim WHERE grant_id = ?`,
      [grantId],
    );
    expect(sealed?.status).toBe("sealed_no_effect");
    expect(JSON.parse(sealed!.receipt).result).toBe("sealed_no_effect");
    expect(delayedApply).not.toBeNull();
    const delayedResponse = await realGet(env.DO.idFromName(scenario.installationId)).fetch(
      "https://quota-do.internal/rpc",
      { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(delayedApply) },
    );
    const delayedResult = await delayedResponse.json() as Record<string, unknown>;
    expect(delayedResult.result).toBe("rejected");
    expect(delayedResult.code).toBe("ceiling_claim_sealed");
    expect(await countDoGrantRows(scenario.installationId)).toBe(1);
  });

  it("E2E-P3.6-04 Missing reason or operator_email is rejected", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);

    const missingReasonId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const missingReason = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId: missingReasonId,
      count: 14,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: undefined,
    });
    delete (missingReason.source as Record<string, unknown>).reason;

    const noReason = await hpComplimentaryGrant({ envelope: missingReason });
    expect(noReason.result).toBe("rejected");
    expect(noReason.code).toBe("bad_request");

    const missingOperatorId = await grantIdComp(
      crypto.randomUUID().replace(/-/g, ""),
    );
    const missingOperator = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId: missingOperatorId,
      count: 14,
      operatorEmail: undefined,
      reason: "no operator",
    });
    delete (missingOperator.source as Record<string, unknown>).operator_email;

    const noOperator = await hpComplimentaryGrant({ envelope: missingOperator });
    expect(noOperator.result).toBe("rejected");
    expect(noOperator.code).toBe("bad_request");
  });

  it("R4-D1 / E2E-P3.6-05 term_adjustment replay does not add allowance or extend twice", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    await newClinic(scenario);

    const beforeEndsAt = await readActiveTermEndsAt(scenario.installationId);
    expect(beforeEndsAt).toBeTruthy();

    const extendGrantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const extendEnvelope = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId: extendGrantId,
      kind: "term_adjustment",
      count: 1,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "extend coverage",
      adjustment: { extend_days: 7 },
    });
    const extended = await hpComplimentaryGrant({ envelope: extendEnvelope });
    expect(extended.result, JSON.stringify(extended)).toBe("applied");

    const afterExtendEndsAt = await readActiveTermEndsAt(scenario.installationId);
    expect(afterExtendEndsAt).toBe(
      addDuration(String(beforeEndsAt), "day", 7, "staging"),
    );
    const extendReplay = await hpComplimentaryGrant({ envelope: extendEnvelope });
    expect(extendReplay.result).toBe("already_applied");
    expect(extendReplay.receipt).toEqual(extended.receipt);
    expect(await readActiveTermEndsAt(scenario.installationId)).toBe(afterExtendEndsAt);

    const shortenGrantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const shortenEnvelope = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId: shortenGrantId,
      kind: "term_adjustment",
      count: 1,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "illegal shorten",
      adjustment: { extend_days: -7 },
    });
    const shortened = await hpComplimentaryGrant({ envelope: shortenEnvelope });
    expect(shortened.result).toBe("rejected");

    await publishPlanVersionTwo(["clinic.plan_changed"]);

    const planGrantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const planEnvelope = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId: planGrantId,
      kind: "term_adjustment",
      count: 1,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "plan change",
      planVersion: 2,
      adjustment: { plan: { plan_id: PLAN_ID, plan_version: 2 } },
    });
    const planChanged = await hpComplimentaryGrant({ envelope: planEnvelope });
    expect(planChanged.result).toBe("applied");

    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));
    const activatedPlanChanged = await vendorClassH("activateCohort", {
      capability_id: "clinic.plan_changed",
      capability_version: CAPABILITY_VERSION,
      installation_ids: [scenario.installationId],
    });
    expect(activatedPlanChanged.status).toBe(200);
    const promotedPlanChanged = await vendorClassH("promoteCohort", {
      capability_id: "clinic.plan_changed",
      capability_version: CAPABILITY_VERSION,
    });
    expect(promotedPlanChanged.status).toBe(200);
    clearConfigCache();

    const token = await mintAat(scenario);
    const caps = await getCapabilities(token);
    expect(caps.status).toBe(200);
    const allowed = discoveryCapabilityIds(caps.body);
    expect(allowed).not.toContain("clinic.visit_summary");
    expect(allowed).toContain("clinic.plan_changed");
  });

  it("E2E-P3.6-06 Suspend returns 403 suspended before any other refusal and resume admits", async () => {
    const scenario = await newScenario();
    await setupPromotedFakePolicy(scenario);

    const accessJwt = await mintVendorAccessJwt();
    clearCapturedVendorEmails();
    const suspended = await extendedVendorCall(
      "suspend",
      {
        contract_version: CONTRACT_VERSION,
        org_id: scenario.orgId,
        reason: "billing dispute",
      },
      { accessJwt },
    );
    expect(suspended.result).toBe("ok");
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));

    let token = await mintAat(scenario);
    const blocked = await invoke(scenario, { token });
    expect(blocked.status, JSON.stringify(blocked)).toBe(403);
    expect(blocked.body?.code).toBe("suspended");

    const endsAt = await readActiveTermEndsAt(scenario.installationId);
    expect(endsAt).toBeTruthy();
    await setTestClock(String(endsAt));
    token = await mintAat(scenario);
    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));

    const terms = await readDoTerms(scenario.installationId);
    expect(terms.some((row) => row.state === "grace")).toBe(true);

    const stillBlocked = await invoke(scenario, { token });
    expect(stillBlocked.status).toBe(403);
    expect(stillBlocked.body?.code).toBe("suspended");

    const resumed = await extendedVendorCall(
      "resume",
      {
        contract_version: CONTRACT_VERSION,
        org_id: scenario.orgId,
        reason: "resolved",
      },
      { accessJwt: await mintVendorAccessJwt() },
    );
    expect(resumed.result).toBe("ok");

    await runDurableObjectAlarm(quotaDoStub(scenario.installationId));
    const alertBodies = parseAlertBodies();
    expect(
      alertBodies.some(
        (body) =>
          body.code === "AL-19" &&
          (body.operation as { op?: string })?.op === "suspend",
      ),
    ).toBe(true);
    expect(
      alertBodies.some(
        (body) =>
          body.code === "AL-19" &&
          (body.operation as { op?: string })?.op === "resume",
      ),
    ).toBe(true);

    const admitted = await invoke(scenario);
    expect(admitted.status).toBe(200);
  });

  it("E2E-P3.6-07 A19 a 14-day trial then a paid grant queues the paid term", async () => {
    await coverClinic(await newScenario());

    const scenario = await newScenario();
    const grantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const envelope = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId,
      count: 14,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "trial onboarding",
    });

    const trial = await hpComplimentaryGrant({ envelope });
    expect(trial.result, JSON.stringify(trial)).toBe("applied");

    const binding = await queryOne<{ installation_id: string }>(
      "SELECT installation_id FROM tenant_binding WHERE org_id = ? AND status = 'active'",
      [scenario.orgId],
    );
    expect(binding?.installation_id).toBeTruthy();
    scenario.installationId = binding!.installation_id;

    const afterTrial = await readDoTerms(scenario.installationId);
    const activeTrial = afterTrial.find((row) => row.state === "active");
    expect(activeTrial).toBeTruthy();
    expect(activeTrial!.calendar_start).toBeTruthy();
    expect(activeTrial!.ends_at).toBe(
      addDuration(String(activeTrial!.calendar_start), "day", 14, "staging"),
    );

    await coverClinic(scenario);

    const afterPaid = await readDoTerms(scenario.installationId);
    const active = afterPaid.find((row) => row.state === "active");
    const queued = afterPaid.find((row) => row.state === "queued");
    expect(active).toBeTruthy();
    expect(queued).toBeTruthy();
    expect(termIntervalsOverlap(active!, queued!)).toBe(false);
  });

  it("E2E-P3.6-08 inspectCoverage returns the ledger and rejects a missing Access JWT", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);

    const ledger = await readDoLedger(scenario.installationId);
    const accessJwt = await mintVendorAccessJwt();

    const inspected = await extendedVendorCall(
      "inspectCoverage",
      {
        contract_version: CONTRACT_VERSION,
        org_id: scenario.orgId,
      },
      { accessJwt },
    );
    expect(inspected.result).toBe("ok");
    const detail = JSON.parse(inspected.detail) as {
      terms: Record<string, unknown>[];
      grants: Record<string, unknown>[];
      reservations: unknown;
    };
    expect(detail.terms).toEqual(ledger.terms);
    expect(detail.grants).toEqual(ledger.grants);
    expect(detail.reservations).toEqual(ledger.reservations);

    const missingJwt = await extendedVendorCall("inspectCoverage", {
      contract_version: CONTRACT_VERSION,
      org_id: scenario.orgId,
    });
    expect(missingJwt.result).toBe("rejected");
    expect(missingJwt.code).toBe("unauthenticated");
  });

  it("E2E-P3.6-09 Pilot grant of 30 days is accepted under the default policy", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);

    const accessJwt = await mintVendorAccessJwt();
    const operation = await operationForSetCeilingPolicy({ accessJwt });
    const signer = coverClinicSigner();
    const assertion = encodeVendorAssertion(
      await signer.signerAuthenticator.assert({
        operation,
        rpId: env.WEBAUTHN_RP_ID,
        origin: env.WEBAUTHN_ORIGIN,
        up: true,
        uv: true,
      }),
    );

    const first = await hpSetCeilingPolicy({
      accessJwt,
      operation,
      assertion,
    });
    expect(first.result).toBe("ok");
    const firstDetail = JSON.parse(first.detail) as { version: number };
    expect(firstDetail.version).toBe(2);
    const rowsAfterFirst = await countCeilingPolicyRows();

    const second = await hpSetCeilingPolicy({
      accessJwt,
      operation,
      assertion,
    });
    expect(second.result).toBe("ok");
    const secondDetail = JSON.parse(second.detail) as { version: number };
    expect(secondDetail.version).toBe(2);
    expect(await countCeilingPolicyRows()).toBe(rowsAfterFirst);

    const grantId = await grantIdComp(crypto.randomUUID().replace(/-/g, ""));
    const envelope = await buildComplimentaryEnvelope({
      orgId: scenario.orgId,
      grantId,
      count: 30,
      operatorEmail: VENDOR_OPERATOR_EMAIL,
      reason: "pilot program",
    });
    const pilot = await hpComplimentaryGrant({ envelope });
    expect(pilot.result).toBe("applied");
  });

  it("R8-CEILING1 concurrent policy updates allocate consecutive versions and exact retry records once", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    const accessJwt = await mintVendorAccessJwt();
    const policies: CeilingPolicyInput[] = [
      { ...LAUNCH_CEILING_POLICY, window_max_days: 61 },
      { ...LAUNCH_CEILING_POLICY, window_max_days: 60 },
    ];
    const operations = await Promise.all(policies.map((policy) =>
      operationForSetCeilingPolicy({ accessJwt, policy }),
    ));
    const signer = coverClinicSigner();
    const assertions = await Promise.all(operations.map(async (operation) =>
      encodeVendorAssertion(await signer.signerAuthenticator.assert({
        operation,
        rpId: env.WEBAUTHN_RP_ID,
        origin: env.WEBAUTHN_ORIGIN,
        up: true,
        uv: true,
      })),
    ));
    const beforePolicies = await countCeilingPolicyRows();
    const beforeCommands = await countCeilingPolicyCommands();
    const results = await Promise.all(operations.map((operation, index) =>
      hpSetCeilingPolicy({
        accessJwt,
        operation,
        assertion: assertions[index]!,
        policy: policies[index]!,
      }),
    ));
    expect(results.map((result) => JSON.parse(result.detail).version).sort((a, b) => a - b)).toEqual([
      beforePolicies + 1,
      beforePolicies + 2,
    ]);
    expect(await countCeilingPolicyRows()).toBe(beforePolicies + 2);
    expect(await countCeilingPolicyCommands()).toBe(beforeCommands + 2);

    const replay = await hpSetCeilingPolicy({
      accessJwt,
      operation: operations[0]!,
      assertion: assertions[0]!,
      policy: policies[0]!,
    });
    expect(replay.result).toBe("ok");
    expect(JSON.parse(replay.detail)).toEqual(JSON.parse(results[0]!.detail));
    expect(await countCeilingPolicyRows()).toBe(beforePolicies + 2);
    expect(await countCeilingPolicyCommands()).toBe(beforeCommands + 2);
  });
});
