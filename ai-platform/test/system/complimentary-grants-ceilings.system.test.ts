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
  setTestClock,
  setupPromotedFakePolicy,
  setupVendorHarness,
  vendorCall,
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
  | "setCeilingPolicy";

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
      approvals: [{ credential_id: "cred-001", assertion: "stub" }],
    },
  };

  if (input.ceilingOverride !== undefined) {
    envelope.ceiling_override = input.ceilingOverride;
    envelope.evidence = {
      content_sha256: contentSha256,
      approvals: [
        { credential_id: "cred-001", assertion: "stub" },
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
}): Promise<Record<string, unknown>> {
  return {
    op: "setCeilingPolicy",
    params: {
      contract_version: CONTRACT_VERSION,
      access_jwt: input.accessJwt,
      ...LAUNCH_CEILING_POLICY,
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
}): Promise<VendorResultEnvelope> {
  const signer = coverClinicSigner();
  const accessJwt = input.accessJwt ?? (await mintVendorAccessJwt());
  const operation =
    input.operation ??
    (await operationForSetCeilingPolicy({ accessJwt }));
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
      signer_credential_id: signer.signerCredentialId,
      operation,
      assertion,
    },
    { accessJwt },
  );
}

async function publishPlanVersionTwo(
  capabilities: string[],
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
      max_allowance_per_month: PLAN_MAX_ALLOWANCE,
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
      max_allowance_per_month: PLAN_MAX_ALLOWANCE,
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

    const rejected = await hpComplimentaryGrant({ envelope: baseEnvelope });
    expect(rejected.result).toBe("rejected");
    expect(rejected.code).toBe("exceeds_ceiling");

    const accessJwt = await mintVendorAccessJwt();
    const overrideEncoded = await encodeCeilingOverrideAssertion({
      envelope: baseEnvelope,
      accessJwt,
    });
    const withOverride = {
      ...baseEnvelope,
      ceiling_override: overrideEncoded.assertion,
      evidence: {
        ...(baseEnvelope.evidence as Record<string, unknown>),
        approvals: [
          { credential_id: "cred-001", assertion: "stub" },
          { credential_id: "cred-002", assertion: "stub" },
        ],
      },
    };

    clearCapturedVendorEmails();
    const applied = await hpComplimentaryGrant({
      envelope: withOverride,
      accessJwt,
      ceilingOverrideOperation: overrideEncoded.operation,
    });
    expect(applied.result).toBe("applied");

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
          { credential_id: "cred-001", assertion: "stub" },
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
      expect(applied.result).toBe("applied");
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

  it("E2E-P3.6-05 term_adjustment moves ends_at later, rejects a shortening, and shows a plan change", async () => {
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
    expect(extended.result).toBe("applied");

    const afterExtendEndsAt = await readActiveTermEndsAt(scenario.installationId);
    expect(afterExtendEndsAt).toBe(
      addDuration(String(beforeEndsAt), "day", 7),
    );

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
    expect(blocked.status).toBe(403);
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
    expect(trial.result).toBe("applied");

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
      addDuration(String(activeTrial!.calendar_start), "day", 14),
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
});
