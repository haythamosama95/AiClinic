/**
 * P3.9 — Fallback admission, coverage feed, administrator coverage read (H-AP).
 */

import { env, runInDurableObject, SELF } from "cloudflare:test";
import {
  CHANNEL_VERSIONS,
  grantIdPaid,
  sha256Hex,
  subscriptionRef,
} from "vendor-contracts";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { supplementaryFieldsForCode } from "../../src/errors";
import {
  applyAllMigrations,
  coverClinic,
  coverClinicAboKid,
  count,
  fakePolicyDocument,
  flushBackgroundWork,
  GATEWAY_ORIGIN,
  getUsageEvents,
  getVendorTestClockIso,
  invoke,
  mintAat,
  mintVendorAccessJwt,
  signCoverAbo,
  newClinic,
  newScenario,
  POLICY_ID,
  POLICY_VERSION,
  promote,
  publishPolicy,
  queryAll,
  queryOne,
  registerVisitSummaryCapability,
  resetPlatformState,
  runScheduled,
  setTestClock,
  setupVendorHarness,
  vendorCall,
  type Scenario,
  type VendorMethod,
} from "./harness";

const CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;
const PLATFORM_CLINIC_VERSION = CHANNEL_VERSIONS.platformClinic;
const PLATFORM_FEED_VERSION = CHANNEL_VERSIONS.platformFeed;
const COVER_PLAN_ID = "live-monthly";
const COVER_PLAN_VERSION = 1;
const COVER_PLAN_MAX_ALLOWANCE = 10_000;
const QUOTA_WEIGHT = 1;
const W_MAX = QUOTA_WEIGHT;
const FALLBACK_WEIGHT_CAP = 5 * W_MAX;

const doGetReal = env.DO.get.bind(env.DO);

// T010 relocates these helpers to harness.ts and wires GatewayObject.
let admissionFault: { mode: "throw" | "hold"; hold_until?: number } | null =
  null;

async function setAdmissionFault(
  mode: "throw" | "hold",
  opts: { hold_until?: number } = {},
): Promise<void> {
  admissionFault = { mode, ...opts };
  void admissionFault;
}

function clearAdmissionFault(): void {
  admissionFault = null;
}

async function mintFeedToken(): Promise<string> {
  return "harness-feed-token-stub";
}

type P39VendorMethod = VendorMethod | "feedConsumerHealth";

const p39VendorCall = vendorCall as (
  method: P39VendorMethod,
  args: Record<string, unknown>,
  opts?: {
    accessJwt?: string;
    assertion?: Record<string, unknown>;
  },
) => Promise<{ result: string; code: string; detail: string }>;

type FallbackAdmissionRow = {
  installation_id: string;
  idempotency_key: string;
  term_id: string;
  request_id: string;
  weight: number;
  admitted_at: string;
  state: string;
};

function quotaDoStub(installationId: string) {
  return doGetReal(env.DO.idFromName(installationId));
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

async function harnessNowMs(): Promise<number> {
  const row = await queryOne<{ now_iso: string }>(
    "SELECT now_iso FROM harness_test_clock WHERE id = 'default'",
  );
  if (row?.now_iso) {
    const parsed = Date.parse(row.now_iso);
    if (!Number.isNaN(parsed)) {
      return parsed;
    }
  }
  return Date.now();
}

async function readHotUsed(installationId: string): Promise<number> {
  const rows = await runInDurableObject(
    quotaDoStub(installationId),
    async (_instance, state) =>
      sqlSelect<{ used: number }>(state, "SELECT used FROM hot LIMIT 1"),
  );
  return rows[0]?.used ?? 0;
}

async function expectFallbackAdmissionTable(): Promise<void> {
  const table = await queryOne<{ ok: number }>(
    "SELECT 1 AS ok FROM sqlite_master WHERE type = 'table' AND name = 'fallback_admission'",
  );
  expect(table?.ok).toBe(1);
}

async function listFallbackAdmissions(
  installationId: string,
): Promise<FallbackAdmissionRow[]> {
  await expectFallbackAdmissionTable();
  return queryAll<FallbackAdmissionRow>(
    `SELECT installation_id, idempotency_key, term_id, request_id, weight, admitted_at, state
     FROM fallback_admission WHERE installation_id = ?`,
    [installationId],
  );
}

async function activeTermRef(
  installationId: string,
  orgId: string,
): Promise<string> {
  const mirror = await queryOne<{ term_snapshot: string }>(
    "SELECT term_snapshot FROM coverage_mirror WHERE installation_id = ?",
    [installationId],
  );
  if (mirror?.term_snapshot) {
    const snapshot = JSON.parse(mirror.term_snapshot) as { ref?: string };
    if (snapshot.ref) {
      return snapshot.ref;
    }
  }
  const accessJwt = await mintVendorAccessJwt();
  const inspected = await p39VendorCall(
    "inspectCoverage",
    { contract_version: CONTRACT_VERSION, org_id: orgId },
    { accessJwt },
  );
  expect(inspected.result).toBe("ok");
  const detail = JSON.parse(inspected.detail) as {
    terms: Array<{ term_id: string; state: string }>;
  };
  const active = detail.terms.find((row) => row.state === "active");
  expect(active?.term_id).toBeTruthy();
  return active!.term_id;
}

async function insertPendingFallbackRows(
  installationId: string,
  orgId: string,
  totalWeight: number,
): Promise<void> {
  await expectFallbackAdmissionTable();
  const termId = await activeTermRef(installationId, orgId);
  const admittedAt = (await queryOne<{ now_iso: string }>(
    "SELECT now_iso FROM harness_test_clock WHERE id = 'default'",
  ))?.now_iso ?? new Date().toISOString();
  let remaining = totalWeight;
  while (remaining > 0) {
    const weight = Math.min(remaining, W_MAX);
    remaining -= weight;
    await env.DB.prepare(
      `INSERT INTO fallback_admission (
         installation_id, idempotency_key, term_id, request_id, weight, admitted_at, state
       ) VALUES (?, ?, ?, ?, ?, ?, 'pending')`,
    )
      .bind(
        installationId,
        `pending-${crypto.randomUUID()}`,
        termId,
        crypto.randomUUID(),
        weight,
        admittedAt,
      )
      .run();
  }
}

async function setupPromotedPolicy(scenario: Scenario): Promise<string> {
  const document = fakePolicyDocument(POLICY_ID, POLICY_VERSION);
  const published = await publishPolicy(POLICY_ID, POLICY_VERSION, document);
  expect(published.status).toBe(200);
  const promoted = await promote(POLICY_ID, POLICY_VERSION);
  expect(promoted.status).toBe(200);
  return await mintAat(scenario);
}

async function postRequest(
  scenario: Scenario,
  token: string,
  idempotencyKey: string,
): Promise<{
  status: number;
  body: Record<string, unknown> | null;
}> {
  const response = await SELF.fetch(
    new Request(`${GATEWAY_ORIGIN}/v1/requests`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
        "x-idempotency-key": idempotencyKey,
        "x-capability-version": "1.0.0",
        "Aip-Contract-Version": "1",
      },
      body: JSON.stringify({
        capability_id: "clinic.visit_summary",
        org_id: scenario.orgId,
        branch_id: scenario.branchId,
        actor_id: scenario.actorId,
        context: {
          "visit.chief_complaint@v1": { text: "Test complaint" },
        },
      }),
    }),
  );
  const contentType = response.headers.get("content-type") ?? "";
  if (contentType.includes("text/event-stream")) {
    await flushBackgroundWork();
    return { status: response.status, body: null };
  }
  const text = await response.text();
  await flushBackgroundWork();
  return {
    status: response.status,
    body: text.length > 0 ? (JSON.parse(text) as Record<string, unknown>) : null,
  };
}

async function readFirstReservationId(orgId: string): Promise<string | null> {
  const accessJwt = await mintVendorAccessJwt();
  const inspected = await p39VendorCall(
    "inspectCoverage",
    { contract_version: CONTRACT_VERSION, org_id: orgId },
    { accessJwt },
  );
  if (inspected.result !== "ok") {
    return null;
  }
  const detail = JSON.parse(inspected.detail) as {
    reservations: Array<{ id: string }>;
  };
  return detail.reservations[0]?.id ?? null;
}

async function waitForReservation(orgId: string): Promise<string | null> {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const id = await readFirstReservationId(orgId);
    if (id) {
      return id;
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  return null;
}

async function buildSecondPaidGrantEnvelope(input: {
  orgId: string;
  grantId: string;
}): Promise<Record<string, unknown>> {
  const paidAt = getVendorTestClockIso() ?? new Date().toISOString();
  const paymentRef = crypto.randomUUID().replace(/-/g, "");
  const contentSha256 = await sha256Hex(new TextEncoder().encode(paymentRef));
  return {
    contract_version: CONTRACT_VERSION,
    grant_id: input.grantId,
    org_id: input.orgId,
    kind: "term",
    placement: "queue",
    source: { kind: "paid", ref: paymentRef },
    plan: { plan_id: COVER_PLAN_ID, plan_version: COVER_PLAN_VERSION },
    duration: { unit: "month", count: 1 },
    allowance_credits: COVER_PLAN_MAX_ALLOWANCE,
    grace: { days: 7, cap_rule: "proportional" },
    paid_at: paidAt,
    evidence: {
      content_sha256: contentSha256,
      approvals: [{ credential_id: "cred-001", assertion: "stub" }],
    },
  };
}

async function grantSecondPaidTerm(scenario: Scenario): Promise<void> {
  const grantId = await grantIdPaid(crypto.randomUUID().replace(/-/g, ""));
  const envelope = await buildSecondPaidGrantEnvelope({
    orgId: scenario.orgId,
    grantId,
  });
  const aboSignature = await signCoverAbo(envelope);
  const granted = await p39VendorCall("grant", {
    contract_version: CONTRACT_VERSION,
    envelope,
    abo_kid: coverClinicAboKid(),
    abo_signature: aboSignature,
  });
  expect(granted.result === "applied" || granted.result === "already_applied").toBe(
    true,
  );
}

async function getCoverageDetail(scenario: Scenario): Promise<string> {
  const accessJwt = await mintVendorAccessJwt();
  const coverage = await p39VendorCall(
    "getCoverage",
    {
      contract_version: CONTRACT_VERSION,
      org_id: scenario.orgId,
      installation_id: scenario.installationId,
    },
    { accessJwt },
  );
  expect(coverage.result).toBe("ok");
  return coverage.detail;
}

async function insertCoverageEventRow(input: {
  eventId: string;
  orgId: string;
  installationId: string;
  bindingEpoch: number;
  clinicSeq: number;
  kind: string;
  snapshot: Record<string, unknown>;
  at: string;
}): Promise<number> {
  const result = await env.DB.prepare(
    `INSERT INTO coverage_event (
       event_id, org_id, installation_id, binding_epoch, clinic_seq, kind, snapshot, at
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      input.eventId,
      input.orgId,
      input.installationId,
      input.bindingEpoch,
      input.clinicSeq,
      input.kind,
      JSON.stringify(input.snapshot),
      input.at,
    )
    .run();
  const feedSeq = Number(result.meta.last_row_id);
  expect(feedSeq).toBeGreaterThan(0);
  return feedSeq;
}

beforeAll(async () => {
  await applyAllMigrations(env.DB);
  registerVisitSummaryCapability();
  await setupVendorHarness();
});

beforeEach(async () => {
  await resetPlatformState();
  clearAdmissionFault();
  await setTestClock("2026-04-01T12:00:00.000Z");
});

describe("P3.9 fallback admission, feed, and coverage read", () => {
  it("E2E-P3.9-01 FM-06 DO failure admits via fallback and */5 charges once", async () => {
    const scenario = await newScenario();
    await coverClinicAndPolicy(scenario);
    const token = await setupPromotedPolicy(scenario);

    await setAdmissionFault("throw");
    const idempotencyKey = crypto.randomUUID();
    const admitted = await postRequest(scenario, token, idempotencyKey);
    expect(admitted.body?.code).not.toBe("coverage_unknown");

    const rows = await listFallbackAdmissions(scenario.installationId);
    expect(rows).toHaveLength(1);
    expect(rows[0]?.state).toBe("pending");
    expect(rows[0]?.term_id).toBeTruthy();
    expect(rows[0]?.request_id).toBeTruthy();

    clearAdmissionFault();
    const usedBefore = await readHotUsed(scenario.installationId);
    await runScheduled("*/5 * * * *");
    const usedAfterFirst = await readHotUsed(scenario.installationId);
    expect(usedAfterFirst - usedBefore).toBe(rows[0]!.weight);

    await runScheduled("*/5 * * * *");
    expect(await readHotUsed(scenario.installationId)).toBe(usedAfterFirst);

    const settled = await queryOne<{ state: string }>(
      "SELECT state FROM fallback_admission WHERE installation_id = ? AND idempotency_key = ?",
      [scenario.installationId, idempotencyKey],
    );
    expect(settled?.state).toBe("settled");
  });

  it("E2E-P3.9-02 fallback weight beyond 5 × w_max is coverage_unknown", async () => {
    const scenario = await newScenario();
    await coverClinicAndPolicy(scenario);
    const token = await setupPromotedPolicy(scenario);

    await insertPendingFallbackRows(
      scenario.installationId,
      scenario.orgId,
      FALLBACK_WEIGHT_CAP,
    );
    const beforeCount = await count(
      "fallback_admission",
      "installation_id = ?",
      [scenario.installationId],
    );

    await setAdmissionFault("throw");
    const denied = await postRequest(scenario, token, crypto.randomUUID());
    expect(denied.status).toBe(503);
    expect(denied.body?.code).toBe("coverage_unknown");
    const expectedRetry = supplementaryFieldsForCode("coverage_unknown", {});
    expect(denied.body?.retry_after).toBe(expectedRetry.retry_after);

    const afterCount = await count(
      "fallback_admission",
      "installation_id = ?",
      [scenario.installationId],
    );
    expect(afterCount).toBe(beforeCount);
  });

  it("E2E-P3.9-03 fallback at or after hard_stop_at is coverage_unknown", async () => {
    const scenario = await newScenario();
    await coverClinicAndPolicy(scenario);
    const token = await setupPromotedPolicy(scenario);

    const mirror = await queryOne<{ hard_stop_at: string }>(
      "SELECT hard_stop_at FROM coverage_mirror WHERE installation_id = ?",
      [scenario.installationId],
    );
    expect(mirror?.hard_stop_at).toBeTruthy();
    await setTestClock(mirror!.hard_stop_at);

    await expectFallbackAdmissionTable();
    const beforeCount = await count(
      "fallback_admission",
      "installation_id = ?",
      [scenario.installationId],
    );

    await setAdmissionFault("throw");
    const denied = await postRequest(scenario, token, crypto.randomUUID());
    expect(denied.body?.code).toBe("coverage_unknown");

    const afterCount = await count(
      "fallback_admission",
      "installation_id = ?",
      [scenario.installationId],
    );
    expect(afterCount).toBe(beforeCount);
  });

  it("E2E-P3.9-04 drain skips a request_id reserved before the admission deadline", async () => {
    const scenario = await newScenario();
    await coverClinicAndPolicy(scenario);
    const token = await setupPromotedPolicy(scenario);

    const startMs = await harnessNowMs();
    const holdUntil = startMs + 5_000;
    await setAdmissionFault("hold", { hold_until: holdUntil });

    const fetchPromise = invoke(scenario, {
      token,
      idempotencyKey: crypto.randomUUID(),
    });
    const reservationId = await waitForReservation(scenario.orgId);
    expect(reservationId).toBeTruthy();

    const advanceTo = new Date(Math.max(holdUntil + 1, startMs + 2_001)).toISOString();
    await setTestClock(advanceTo);

    const settled = await fetchPromise;
    expect(settled.status).toBe(200);

    const usedBeforeDrain = await readHotUsed(scenario.installationId);
    const usageBefore = await getUsageEvents(reservationId!);

    await runScheduled("*/5 * * * *");

    const usageAfterFirst = await getUsageEvents(reservationId!);
    const usedAfterFirst = await readHotUsed(scenario.installationId);
    const countedOnce =
      usageAfterFirst.length === 1 ||
      (usageBefore.length === usageAfterFirst.length &&
        usedAfterFirst - usedBeforeDrain <= W_MAX);
    expect(countedOnce).toBe(true);

    await runScheduled("*/5 * * * *");
    const usageAfterSecond = await getUsageEvents(reservationId!);
    expect(usageAfterSecond.length).toBe(usageAfterFirst.length);
    expect(await readHotUsed(scenario.installationId)).toBe(usedAfterFirst);
  });

  it("E2E-P3.9-05 feed page, token separation, and feedConsumerHealth", async () => {
    const scenario = await newScenario();
    const clockIso = "2026-05-01T10:00:00.000Z";
    await setTestClock(clockIso);

    const firstSeq = await insertCoverageEventRow({
      eventId: `evt-${crypto.randomUUID()}`,
      orgId: scenario.orgId,
      installationId: scenario.installationId,
      bindingEpoch: 1,
      clinicSeq: 1,
      kind: "term_activated",
      snapshot: { note: "first" },
      at: clockIso,
    });
    await insertCoverageEventRow({
      eventId: `evt-${crypto.randomUUID()}`,
      orgId: scenario.orgId,
      installationId: scenario.installationId,
      bindingEpoch: 1,
      clinicSeq: 2,
      kind: "band_crossed",
      snapshot: { note: "second" },
      at: clockIso,
    });

    const feedToken = await mintFeedToken();
    const afterCursor = firstSeq - 1;
    const feedResponse = await SELF.fetch(
      new Request(
        `${GATEWAY_ORIGIN}/v1/feed/coverage?after=${afterCursor}&limit=1`,
        {
          headers: {
            authorization: `Bearer ${feedToken}`,
            "Aip-Contract-Version": String(PLATFORM_FEED_VERSION),
          },
        },
      ),
    );
    expect(feedResponse.status).toBe(200);
    expect(feedResponse.headers.get("Aip-Contract-Version")).toBe(
      String(PLATFORM_FEED_VERSION),
    );
    const feedBody = (await feedResponse.json()) as Record<string, unknown>;
    expect(feedBody).toMatchObject({
      contract_version: PLATFORM_FEED_VERSION,
      after: afterCursor,
      has_more: true,
    });
    const events = feedBody.events as Array<Record<string, unknown>>;
    expect(events).toHaveLength(1);
    expect(events[0]?.feed_seq).toBe(firstSeq);
    expect(feedBody.next_after).toBe(firstSeq);

    const health = await p39VendorCall("feedConsumerHealth", {
      contract_version: PLATFORM_FEED_VERSION,
    });
    expect(health.result).toBe("ok");
    const healthDetail = JSON.parse(health.detail) as {
      last_pull_at: string | null;
    };
    expect(healthDetail.last_pull_at).toBeTruthy();

    const requestWithFeedToken = await postRequest(
      scenario,
      feedToken,
      crypto.randomUUID(),
    );
    expect(requestWithFeedToken.status).toBe(401);

    const aat = await mintAat(scenario);
    const aatOnFeed = await SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}/v1/feed/coverage?after=0&limit=1`, {
        headers: {
          authorization: `Bearer ${aat}`,
          "Aip-Contract-Version": String(PLATFORM_FEED_VERSION),
        },
      }),
    );
    expect(aatOnFeed.status).toBe(401);
  });

  it("E2E-P3.9-06 feed version missing or unsupported is refused before auth", async () => {
    const missingVersion = await SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}/v1/feed/coverage?after=0&limit=1`),
    );
    expect(missingVersion.status).toBe(400);
    const missingBody = (await missingVersion.json()) as Record<string, unknown>;
    expect(missingBody.code).toBe("contract_version_unsupported");

    const unsupported = await SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}/v1/feed/coverage?after=0&limit=1`, {
        headers: { "Aip-Contract-Version": "2" },
      }),
    );
    expect(unsupported.status).toBe(400);
    const unsupportedBody = (await unsupported.json()) as Record<string, unknown>;
    expect(unsupportedBody.code).toBe("contract_version_unsupported");

    const table = await queryOne<{ ok: number }>(
      "SELECT 1 AS ok FROM sqlite_master WHERE type = 'table' AND name = 'feed_consumer'",
    );
    if (table?.ok) {
      const consumer = await queryOne<{ last_pull_at: string | null }>(
        "SELECT last_pull_at FROM feed_consumer WHERE consumer = 'backend-feed'",
      );
      expect(consumer?.last_pull_at ?? null).toBeNull();
    }
  });

  it("E2E-P3.9-07 administrator coverage read does not write the DO", async () => {
    const scenario = await newScenario();
    await coverClinic(scenario);
    await grantSecondPaidTerm(scenario);

    const detailBefore = await getCoverageDetail(scenario);
    const vendorCoverage = JSON.parse(detailBefore) as {
      snapshot: Record<string, unknown>;
      queued_terms: unknown[];
      recent_terms: unknown[];
    };
    expect(vendorCoverage.queued_terms).toHaveLength(1);

    const accessJwt = await mintVendorAccessJwt();
    const inspected = await p39VendorCall(
      "inspectCoverage",
      { contract_version: CONTRACT_VERSION, org_id: scenario.orgId },
      { accessJwt },
    );
    expect(inspected.result).toBe("ok");
    const inspectDetail = JSON.parse(inspected.detail) as {
      terms: Array<{ state: string }>;
    };
    expect(inspectDetail.terms.filter((row) => row.state === "queued")).toHaveLength(
      1,
    );

    const adminToken = await mintAat(scenario, { role: "administrator" });
    const coverageResponse = await SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}/v1/coverage`, {
        headers: {
          authorization: `Bearer ${adminToken}`,
          "Aip-Contract-Version": String(PLATFORM_CLINIC_VERSION),
        },
      }),
    );
    expect(coverageResponse.status).toBe(200);
    expect(coverageResponse.headers.get("Aip-Contract-Version")).toBe(
      String(PLATFORM_CLINIC_VERSION),
    );
    const coverageBody = (await coverageResponse.json()) as Record<string, unknown>;
    expect(coverageBody.subscription_ref).toBe(
      await subscriptionRef(scenario.orgId),
    );
    expect(coverageBody.snapshot).toEqual(vendorCoverage.snapshot);
    expect(coverageBody.queued_terms).toEqual(vendorCoverage.queued_terms);
    expect(coverageBody.recent_terms).toEqual(vendorCoverage.recent_terms);

    const detailAfterAdminRead = await getCoverageDetail(scenario);
    expect(detailAfterAdminRead).toBe(detailBefore);

    const staffToken = await mintAat(scenario, { role: "staff" });
    const staffResponse = await SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}/v1/coverage`, {
        headers: {
          authorization: `Bearer ${staffToken}`,
          "Aip-Contract-Version": String(PLATFORM_CLINIC_VERSION),
        },
      }),
    );
    expect(staffResponse.status).toBe(403);

    const detailAfterStaffDenied = await getCoverageDetail(scenario);
    expect(detailAfterStaffDenied).toBe(detailBefore);
  });

  it("E2E-P3.9-08 GET /v1/usage is 404", async () => {
    const usageResponse = await SELF.fetch(
      new Request(`${GATEWAY_ORIGIN}/v1/usage`, { method: "GET" }),
    );
    expect(usageResponse.status).toBe(404);
  });
});

async function coverClinicAndPolicy(scenario: Scenario): Promise<void> {
  await coverClinic(scenario);
  await newClinic(scenario);
}
