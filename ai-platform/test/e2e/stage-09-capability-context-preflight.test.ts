import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  assertRequestReferenceShape,
  assertSseSequence,
  assertTaxonomyBody,
  bootstrapE2e,
  CAPABILITY_ID,
  CAPABILITY_VERSION,
  clearConfigCache,
  controlFetch,
  count,
  createCapabilityRegistry,
  DEFAULT_ENTITLE_PAYLOAD,
  env,
  fakePolicyDocument,
  fakePolicyTarget,
  getAiRequest,
  loadManifest,
  mintAat,
  POLICY_ID,
  postRequest,
  promotePolicy,
  provisionHappyPath,
  publishPolicy,
  queryOne,
  resetE2eState,
  seedSql,
  setCapabilityRegistry,
  visitSummaryInvokeBody,
  VISIT_CHIEF_COMPLAINT_V1,
  type EntitlePayload,
  type InvokeResult,
  type Scenario,
  type SseEvent,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const TRACE_ID = "01ARZ3NDEKTSV4RRFFQ69G5FAV";
const MISMATCH_UUID = "00000000-0000-4000-8000-000000000099";
const UNKNOWN_CAPABILITY_ID = "clinic.does_not_exist";
const KILL_CAPABILITY_ID = "clinic.visit_summary_kill";
const S09_065_JTI = "9e7f0a1b-2c3d-4e5f-8a9b-0c1d2e3f4a5b";
const H0_INTENT = "Summarize today's visit for the chart.";
const H0_COMPLAINT = "Patient reports headache for 3 days.";
const DEPRECATE_PATH = `/control/capabilities/${CAPABILITY_ID}/versions/${CAPABILITY_VERSION}/deprecate`;
const RETIRE_PATH = `/control/capabilities/${CAPABILITY_ID}/versions/${CAPABILITY_VERSION}/retire`;
const PAST_RETIRE_AFTER = "2020-01-01T00:00:00.000Z";
const PREFLIGHT_FAIL_TOTAL_BYTES = 27_825;

const PUBLISHED_VISIT_SUMMARY_JSON: Record<string, unknown> = {
  Identity: {
    capabilityId: "clinic.visit_summary",
    version: "1.0.0",
    title: "Visit summary",
    lifecycleState: "active",
    successorId: null,
  },
  Access: {
    requiredCapabilityScope: "ai.visit_summary",
    minimumPlanTier: "standard",
    allowedStaffRoles: ["administrator", "clinician", "nurse"],
    killSwitchFlag: false,
  },
  Interaction: {
    interactionMode: "single_shot",
  },
  Input: {
    userIntentShape: "plain_text",
    priorTurnShape: null,
    sizeLimits: {
      maxChars: 8000,
    },
    allowedLanguages: ["en"],
  },
  "Context requirements": [
    {
      key: "visit.chief_complaint@v1",
      required: true,
      shapeRef: "visit.chief_complaint@v1",
      maxSize: 4096,
    },
  ],
  "Prompt binding": {
    systemInstructionArtifactRef: "clinic.visit_summary/system@v1",
    businessRuleFragmentRefs: ["clinic.visit_summary/rules-visit-summary@v1"],
    contextRenderingTemplateRef:
      "clinic.visit_summary/template-visit-summary@v1",
    outputFormatInstructionDerivationRule: "derive_from_output_mode",
  },
  Output: {
    mode: "prose",
    outputSchemaRef: null,
    businessValidationRuleRefs: [],
    repairPolicy: {
      allowed: false,
      maxAttempts: 0,
    },
  },
  Routing: {
    routingPolicyRef: "routing/standard",
    requiredProviderFeatures: {
      structuredOutput: false,
      contextWindow: 32000,
      language: "en",
    },
    latencyClass: "standard",
    degradedTierPolicy: "fallback_chain",
  },
  Economics: {
    maxInputTokens: 8000,
    maxOutputTokens: 1024,
    perRequestTokenCeiling: 9024,
    quotaWeight: 1,
  },
  Governance: {
    acceptanceMode: "advisory_display",
    retentionClass: "diagnostic_30d",
    evalSuiteRef: "evals/visit-summary@v1",
  },
};

function publishedVisitSummaryWire(): Record<string, unknown> {
  return structuredClone(PUBLISHED_VISIT_SUMMARY_JSON);
}

function restorePublishedRegistry(): void {
  setCapabilityRegistry(
    createCapabilityRegistry([loadManifest(publishedVisitSummaryWire())]),
    { replace: true },
  );
}

async function entitledJourney(
  entitle: EntitlePayload = DEFAULT_ENTITLE_PAYLOAD,
): Promise<{ scenario: Scenario; token: string }> {
  const scenario = await provisionHappyPath(undefined, entitle);
  const token = await mintAat(scenario);
  return { scenario, token };
}

function happyVisitBody(
  scenario: Scenario,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return visitSummaryInvokeBody(scenario, {
    user_intent: H0_INTENT,
    ...overrides,
  });
}

function complaintObject(
  visitId: string,
  extra: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    visit_id: visitId,
    complaint: H0_COMPLAINT,
    ...extra,
  };
}

function h0Context(
  scenario: Scenario,
  extra: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    org: scenario.orgId,
    branch: scenario.branchId,
    [VISIT_CHIEF_COMPLAINT_V1]: complaintObject(crypto.randomUUID()),
    ...extra,
  };
}

function jsonUtf8Bytes(value: unknown): number {
  return new TextEncoder().encode(JSON.stringify(value)).byteLength;
}

function complaintValueOfJsonBytes(
  visitId: string,
  targetBytes: number,
): Record<string, unknown> {
  const base = { visit_id: visitId, complaint: "" };
  const pad = Math.max(0, targetBytes - jsonUtf8Bytes(base));
  return { visit_id: visitId, complaint: "x".repeat(pad) };
}

function serializePreflightInput(
  filteredContext: Record<string, unknown>,
  userIntent: string,
): string {
  return JSON.stringify({ filteredContext, userIntent });
}

function intentForPreflightTotal(
  filteredContext: Record<string, unknown>,
  targetTotalBytes: number,
): string {
  const emptyBytes = new TextEncoder().encode(
    serializePreflightInput(filteredContext, ""),
  ).byteLength;
  const pad = Math.max(0, targetTotalBytes - emptyBytes);
  return "x".repeat(pad);
}

function assertJsonTaxonomy(
  result: InvokeResult,
  status: number,
  code: string,
  retrySafe: boolean,
): void {
  expect(result.status).toBe(status);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.events).toEqual([]);
  assertTaxonomyBody(result.body, { code, retry_safe: retrySafe });
  assertRequestReferenceShape(String(result.body?.request_reference));
}

function assertAcceptedSse(
  result: InvokeResult,
  opts: { traceId?: string; degradedNotice?: boolean } = {},
): SseEvent {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("text/event-stream");
  assertSseSequence(result.events, ["accepted"]);
  const accepted = result.events[0];
  expect(accepted?.event).toBe("accepted");
  assertRequestReferenceShape(String(accepted?.data.request_reference));
  if (opts.traceId !== undefined) {
    expect(accepted?.data.trace_id).toBe(opts.traceId);
  } else {
    expect(typeof accepted?.data.trace_id).toBe("string");
    expect(String(accepted?.data.trace_id).length).toBeGreaterThan(0);
  }
  if (opts.degradedNotice === true) {
    expect(accepted?.data.degraded_notice).toBe(true);
  } else {
    expect("degraded_notice" in (accepted?.data ?? {})).toBe(false);
  }
  return accepted!;
}

async function assertNoGuardWrites(): Promise<void> {
  expect(await count("ai_request")).toBe(0);
  expect(await count("usage_event")).toBe(0);
  expect(await count("grace_admission_queue")).toBe(0);
}

async function postH0(
  scenario: Scenario,
  token: string,
  extra: {
    body?: Record<string, unknown>;
    capabilityVersion?: string;
    idempotencyKey?: string;
  } = {},
): Promise<InvokeResult> {
  return postRequest(scenario, {
    token,
    traceId: TRACE_ID,
    capabilityVersion: extra.capabilityVersion,
    idempotencyKey: extra.idempotencyKey,
    body: extra.body ?? happyVisitBody(scenario),
  });
}

async function deleteGlobalOverlays(): Promise<void> {
  await env.DB.prepare(
    "DELETE FROM capability_grant WHERE scope = 'global' AND capability_id = ?",
  )
    .bind(CAPABILITY_ID)
    .run();
  clearConfigCache();
}

async function deprecateVisitSummary(): Promise<void> {
  // Catalog S09-047 successor_id is clinic.visit_summary_v2, but the real
  // deprecate route returns 400 unknown_successor unless that id is registered.
  // Use the published identity (S04-086) so the overlay is created by HTTP.
  const result = await controlFetch(DEPRECATE_PATH, {
    body: { successor_id: CAPABILITY_ID },
  });
  expect(result.status).toBe(200);
  clearConfigCache();
}

async function retireVisitSummary(): Promise<void> {
  await deprecateVisitSummary();
  // Register 5 #23: 90-day overlap cannot elapse in-pool. Same seed as S04-098.
  await seedSql([
    {
      sql: `UPDATE capability_grant
            SET retire_after = ?
            WHERE scope = 'global'
              AND capability_id = ?
              AND lifecycle_state = 'deprecated'`,
      params: [PAST_RETIRE_AFTER, CAPABILITY_ID],
    },
  ]);
  const retired = await controlFetch(RETIRE_PATH, { body: {} });
  expect(retired.status).toBe(200);
  clearConfigCache();
}

describe("Stage 09 — capability, context, preflight (S09-044…S09-065)", () => {
  it("S09-044 — unregistered capability_id is capability_unknown", async () => {
    const entitle: EntitlePayload = {
      ...DEFAULT_ENTITLE_PAYLOAD,
      allowed_capabilities: [
        ...DEFAULT_ENTITLE_PAYLOAD.allowed_capabilities,
        UNKNOWN_CAPABILITY_ID,
      ],
      grants: [
        ...DEFAULT_ENTITLE_PAYLOAD.grants,
        {
          capability_id: UNKNOWN_CAPABILITY_ID,
          capability_version: CAPABILITY_VERSION,
          scope: "installation",
        },
      ],
    };
    const { scenario, token } = await entitledJourney(entitle);

    const result = await postH0(scenario, token, {
      body: happyVisitBody(scenario, { capability_id: UNKNOWN_CAPABILITY_ID }),
    });

    assertJsonTaxonomy(result, 404, "capability_unknown", false);
    expect(result.body?.trace_id).toBe(TRACE_ID);
    await assertNoGuardWrites();
  });

  it("S09-045 — unregistered version is capability_unknown", async () => {
    const { scenario, token } = await entitledJourney();
    // [SEED] Catalog: un-pin (capability_version NULL/empty) so stage 3 does
    // not 403 version_mismatch. Schema is TEXT NOT NULL; empty string still
    // mismatches 9.9.9. Pin the live grants to the requested version so stage 3
    // passes and stage 5 registry miss is reached.
    await seedSql([
      {
        sql: `UPDATE capability_grant
              SET capability_version = '9.9.9'
              WHERE capability_id = ? AND revoked_at IS NULL`,
        params: [CAPABILITY_ID],
      },
    ]);
    clearConfigCache();

    const result = await postH0(scenario, token, {
      capabilityVersion: "9.9.9",
    });

    assertJsonTaxonomy(result, 404, "capability_unknown", false);
    expect(result.body?.trace_id).toBe(TRACE_ID);
    await assertNoGuardWrites();
  });

  it("S09-046 — retired lifecycle overlay is capability_retired", async () => {
    const { scenario, token } = await entitledJourney();
    try {
      await retireVisitSummary();

      const result = await postH0(scenario, token);

      assertJsonTaxonomy(result, 404, "capability_retired", false);
      expect(result.body?.trace_id).toBe(TRACE_ID);
      await assertNoGuardWrites();
    } finally {
      await deleteGlobalOverlays();
    }
  });

  it("S09-047 — deprecated lifecycle still resolves", async () => {
    const { scenario, token } = await entitledJourney();
    try {
      await deprecateVisitSummary();

      const result = await postH0(scenario, token);
      const accepted = assertAcceptedSse(result, { traceId: TRACE_ID });

      const overlay = await queryOne<{
        lifecycle_state: string | null;
        successor_id: string | null;
      }>(
        `SELECT lifecycle_state, successor_id FROM capability_grant
         WHERE scope = 'global' AND capability_id = ?
         ORDER BY changed_at DESC LIMIT 1`,
        [CAPABILITY_ID],
      );
      expect(overlay?.lifecycle_state).toBe("deprecated");

      const row = await getAiRequest(String(accepted.data.request_reference));
      expect(row).not.toBeNull();
      expect(row?.capability_id).toBe(CAPABILITY_ID);
    } finally {
      await deleteGlobalOverlays();
    }
  });

  it("S09-048 — missing requiredCapabilityScope is forbidden_capability", async () => {
    const scenario = await provisionHappyPath();
    const token = await mintAat(scenario, { claims: { scopes: ["ai.access"] } });

    const result = await postH0(scenario, token);

    assertJsonTaxonomy(result, 403, "forbidden_capability", false);
    expect(result.body?.trace_id).toBe(TRACE_ID);
    await assertNoGuardWrites();
  });

  it("S09-049 — staff role outside allowedStaffRoles is forbidden_capability", async () => {
    const scenario = await provisionHappyPath();
    const token = await mintAat(scenario, {
      claims: { role: "doctor", scopes: ["ai.visit_summary"] },
    });

    const result = await postH0(scenario, token);

    assertJsonTaxonomy(result, 403, "forbidden_capability", false);
    expect(result.body?.trace_id).toBe(TRACE_ID);
    await assertNoGuardWrites();
  });

  it("S09-050 — manifest killSwitchFlag true is capability_disabled", async () => {
    const published = loadManifest(publishedVisitSummaryWire());
    const killWire = publishedVisitSummaryWire();
    killWire.Identity = {
      ...(killWire.Identity as Record<string, unknown>),
      capabilityId: KILL_CAPABILITY_ID,
    };
    killWire.Access = {
      ...(killWire.Access as Record<string, unknown>),
      killSwitchFlag: true,
    };
    const killManifest = loadManifest(killWire);
    setCapabilityRegistry(createCapabilityRegistry([published, killManifest]), {
      replace: true,
    });
    try {
      const entitle: EntitlePayload = {
        ...DEFAULT_ENTITLE_PAYLOAD,
        allowed_capabilities: [
          ...DEFAULT_ENTITLE_PAYLOAD.allowed_capabilities,
          KILL_CAPABILITY_ID,
        ],
        grants: [
          ...DEFAULT_ENTITLE_PAYLOAD.grants,
          {
            capability_id: KILL_CAPABILITY_ID,
            capability_version: CAPABILITY_VERSION,
            scope: "installation",
          },
        ],
      };
      const { scenario, token } = await entitledJourney(entitle);

      const result = await postH0(scenario, token, {
        body: happyVisitBody(scenario, { capability_id: KILL_CAPABILITY_ID }),
      });

      assertJsonTaxonomy(result, 503, "capability_disabled", true);
      expect(result.body?.trace_id).toBe(TRACE_ID);
      await assertNoGuardWrites();
    } finally {
      restorePublishedRegistry();
    }
  });

  it("S09-051 — provider kill switch collects killedProviderIds and still accepts", async () => {
    const scenario = await provisionHappyPath();
    const document = fakePolicyDocument(POLICY_ID, 2, {
      targets: [
        fakePolicyTarget("fake-v1"),
        fakePolicyTarget("deepseek-chat", { providerId: "deepseek" }),
      ],
    });
    const published = await publishPolicy(POLICY_ID, "2", document);
    expect(published.status).toBe(200);
    const promoted = await promotePolicy(POLICY_ID, "2");
    expect(promoted.status).toBe(200);

    const armed = await controlFetch("/control/kill-switches/arm", {
      body: { scope: "provider", target: "deepseek" },
    });
    expect(armed.status).toBe(200);
    clearConfigCache();

    const token = await mintAat(scenario);
    const result = await postH0(scenario, token);
    assertAcceptedSse(result, { traceId: TRACE_ID });
  });

  it("S09-052 — missing required context key is context_required", async () => {
    const { scenario, token } = await entitledJourney();

    const result = await postH0(scenario, token, {
      body: visitSummaryInvokeBody(scenario, {
        user_intent: H0_INTENT,
        context: {
          org: scenario.orgId,
          branch: scenario.branchId,
        },
      }),
    });

    assertJsonTaxonomy(result, 422, "context_required", true);
    expect(result.body?.trace_id).toBe(TRACE_ID);
    expect(result.body?.missing_keys).toEqual([VISIT_CHIEF_COMPLAINT_V1]);
    expect(result.body?.manifest_version).toBe(CAPABILITY_VERSION);
    expect(result.body?.manifest_capability_id).toBe(CAPABILITY_ID);
    const shapes = result.body?.shapes as Record<string, unknown> | undefined;
    expect(shapes).toBeDefined();
    expect(shapes?.[VISIT_CHIEF_COMPLAINT_V1]).toBeDefined();
    const shape = shapes?.[VISIT_CHIEF_COMPLAINT_V1] as {
      key?: string;
      fields?: unknown[];
    };
    expect(shape.key).toBe(VISIT_CHIEF_COMPLAINT_V1);
    expect(Array.isArray(shape.fields)).toBe(true);
    await assertNoGuardWrites();
  });

  it("S09-053 — context.org mismatch is context_invalid", async () => {
    const { scenario, token } = await entitledJourney();

    const result = await postH0(scenario, token, {
      body: happyVisitBody(scenario, {
        context: {
          org: MISMATCH_UUID,
          branch: scenario.branchId,
          [VISIT_CHIEF_COMPLAINT_V1]: complaintObject(crypto.randomUUID()),
        },
      }),
    });

    assertJsonTaxonomy(result, 422, "context_invalid", false);
    expect(result.body?.trace_id).toBe(TRACE_ID);
    await assertNoGuardWrites();
  });

  it("S09-054 — context.branch mismatch is context_invalid", async () => {
    const { scenario, token } = await entitledJourney();

    const result = await postH0(scenario, token, {
      body: happyVisitBody(scenario, {
        context: {
          org: scenario.orgId,
          branch: MISMATCH_UUID,
          [VISIT_CHIEF_COMPLAINT_V1]: complaintObject(crypto.randomUUID()),
        },
      }),
    });

    assertJsonTaxonomy(result, 422, "context_invalid", false);
    expect(result.body?.trace_id).toBe(TRACE_ID);
    await assertNoGuardWrites();
  });

  it("S09-055 — required key as string is context_invalid", async () => {
    const { scenario, token } = await entitledJourney();

    const result = await postH0(scenario, token, {
      body: happyVisitBody(scenario, {
        context: {
          org: scenario.orgId,
          branch: scenario.branchId,
          [VISIT_CHIEF_COMPLAINT_V1]: "not-an-object",
        },
      }),
    });

    assertJsonTaxonomy(result, 422, "context_invalid", false);
    expect(result.body?.trace_id).toBe(TRACE_ID);
    await assertNoGuardWrites();
  });

  it("S09-056 — complaint missing visit_id is context_invalid", async () => {
    const { scenario, token } = await entitledJourney();

    const result = await postH0(scenario, token, {
      body: happyVisitBody(scenario, {
        context: {
          org: scenario.orgId,
          branch: scenario.branchId,
          [VISIT_CHIEF_COMPLAINT_V1]: { complaint: "headache" },
        },
      }),
    });

    assertJsonTaxonomy(result, 422, "context_invalid", false);
    expect(result.body?.trace_id).toBe(TRACE_ID);
    await assertNoGuardWrites();
  });

  it("S09-057 — visit_id not-a-uuid is context_invalid", async () => {
    const { scenario, token } = await entitledJourney();

    const result = await postH0(scenario, token, {
      body: happyVisitBody(scenario, {
        context: {
          org: scenario.orgId,
          branch: scenario.branchId,
          [VISIT_CHIEF_COMPLAINT_V1]: {
            visit_id: "not-a-uuid",
            complaint: H0_COMPLAINT,
          },
        },
      }),
    });

    assertJsonTaxonomy(result, 422, "context_invalid", false);
    expect(result.body?.trace_id).toBe(TRACE_ID);
    await assertNoGuardWrites();
  });

  it("S09-058 — complaint over maxLength is context_invalid", async () => {
    const { scenario } = await entitledJourney();

    const over = await postH0(scenario, await mintAat(scenario), {
      body: happyVisitBody(scenario, {
        context: {
          org: scenario.orgId,
          branch: scenario.branchId,
          [VISIT_CHIEF_COMPLAINT_V1]: {
            visit_id: crypto.randomUUID(),
            complaint: "x".repeat(10_001),
          },
        },
      }),
    });
    assertJsonTaxonomy(over, 422, "context_invalid", false);
    expect(over.body?.trace_id).toBe(TRACE_ID);

    const atLimit = await postH0(scenario, await mintAat(scenario), {
      body: happyVisitBody(scenario, {
        context: {
          org: scenario.orgId,
          branch: scenario.branchId,
          [VISIT_CHIEF_COMPLAINT_V1]: {
            visit_id: crypto.randomUUID(),
            complaint: "x".repeat(10_000),
          },
        },
      }),
    });
    // Catalog: 10000 passes maxLength (strict >). Manifest maxSize 4096 still
    // maps the same 422 context_invalid — not a distinct cardinality code.
    expect(atLimit.status).not.toBe(413);
    if (atLimit.status === 200) {
      assertAcceptedSse(atLimit, { traceId: TRACE_ID });
    } else {
      assertJsonTaxonomy(atLimit, 422, "context_invalid", false);
    }
  });

  it("S09-059 — context value over maxSize is context_invalid", async () => {
    const { scenario } = await entitledJourney();
    const visitOver = crypto.randomUUID();
    const visitAt = crypto.randomUUID();
    const overValue = complaintValueOfJsonBytes(visitOver, 4097);
    const atValue = complaintValueOfJsonBytes(visitAt, 4096);
    expect(jsonUtf8Bytes(overValue)).toBe(4097);
    expect(jsonUtf8Bytes(atValue)).toBe(4096);

    const over = await postH0(scenario, await mintAat(scenario), {
      body: happyVisitBody(scenario, {
        context: {
          org: scenario.orgId,
          branch: scenario.branchId,
          [VISIT_CHIEF_COMPLAINT_V1]: overValue,
        },
      }),
    });
    assertJsonTaxonomy(over, 422, "context_invalid", false);
    expect(over.body?.trace_id).toBe(TRACE_ID);
    await assertNoGuardWrites();

    const atLimit = await postH0(scenario, await mintAat(scenario), {
      body: happyVisitBody(scenario, {
        context: {
          org: scenario.orgId,
          branch: scenario.branchId,
          [VISIT_CHIEF_COMPLAINT_V1]: atValue,
        },
      }),
    });
    expect(atLimit.status).not.toBe(422);
    if (atLimit.status === 200) {
      assertAcceptedSse(atLimit, { traceId: TRACE_ID });
    }
  });

  it("S09-060 — malformed recorded_at iso8601 is context_invalid", async () => {
    const { scenario } = await entitledJourney();

    const yesterday = await postH0(scenario, await mintAat(scenario), {
      body: happyVisitBody(scenario, {
        context: {
          org: scenario.orgId,
          branch: scenario.branchId,
          [VISIT_CHIEF_COMPLAINT_V1]: complaintObject(crypto.randomUUID(), {
            recorded_at: "yesterday",
          }),
        },
      }),
    });
    assertJsonTaxonomy(yesterday, 422, "context_invalid", false);

    const spaced = await postH0(scenario, await mintAat(scenario), {
      body: happyVisitBody(scenario, {
        context: {
          org: scenario.orgId,
          branch: scenario.branchId,
          [VISIT_CHIEF_COMPLAINT_V1]: complaintObject(crypto.randomUUID(), {
            recorded_at: "2026-09-05 10:00:00",
          }),
        },
      }),
    });
    assertJsonTaxonomy(spaced, 422, "context_invalid", false);

    const valid = await postH0(scenario, await mintAat(scenario), {
      body: happyVisitBody(scenario, {
        context: {
          org: scenario.orgId,
          branch: scenario.branchId,
          [VISIT_CHIEF_COMPLAINT_V1]: complaintObject(crypto.randomUUID(), {
            recorded_at: "2026-09-05T10:00:00Z",
          }),
        },
      }),
    });
    expect(valid.status).not.toBe(422);
    if (valid.status === 200) {
      assertAcceptedSse(valid, { traceId: TRACE_ID });
    }
  });

  it("S09-061 — extra context keys are dropped; client routing keys ignored", async () => {
    const { scenario, token } = await entitledJourney();

    const result = await postH0(scenario, token, {
      body: happyVisitBody(scenario, {
        conversation_id: "should-be-ignored",
        turn_ordinal: 3,
        transcript: [],
        routing_tier: "degraded",
        degraded: true,
        degraded_notice: true,
        context: {
          ...h0Context(scenario, {
            "unpermitted.extra@v1": { note: "drop me" },
          }),
        },
      }),
    });

    const accepted = assertAcceptedSse(result, { traceId: TRACE_ID });
    const row = await getAiRequest(String(accepted.data.request_reference));
    expect(row).not.toBeNull();
    expect(row?.conversation_id).toBeNull();
    expect(row?.turn_ordinal).toBeNull();
    expect(row?.routing_tier).toBe("standard");
  });

  it("S09-062 — oversized intent is request_too_large with populated ref", async () => {
    const { scenario, token } = await entitledJourney();

    const result = await postH0(scenario, token, {
      body: happyVisitBody(scenario, { user_intent: "x".repeat(40_000) }),
    });

    assertJsonTaxonomy(result, 413, "request_too_large", false);
    expect(result.body?.request_reference).not.toBe("");
    expect(result.body?.trace_id).toBe(TRACE_ID);
    expect(String(result.body?.trace_id).length).toBeGreaterThan(0);
    await assertNoGuardWrites();
  });

  it("S09-063 — preflight just under maxInputTokens accepts", async () => {
    // HARNESS-GAP: promptScaffoldByteLength not on barrel. Catalog wants
    // B0+intent+S = 27824; without S this POSTs the short H0 intent that
    // clearly passes. Exact 27824 needs the composer scaffold helper.
    const { scenario, token } = await entitledJourney();

    const result = await postH0(scenario, token, {
      body: happyVisitBody(scenario, {
        context: {
          org: scenario.orgId,
          branch: scenario.branchId,
          [VISIT_CHIEF_COMPLAINT_V1]: complaintObject(crypto.randomUUID()),
        },
      }),
    });
    assertAcceptedSse(result, { traceId: TRACE_ID });
  });

  it("S09-064 — one byte over the preflight boundary is request_too_large", async () => {
    // HARNESS-GAP: promptScaffoldByteLength not on barrel. Pad so
    // B0+intentBytes = 27825 (S treated as 0); fixer can subtract measured S.
    const { scenario, token } = await entitledJourney();
    const visitId = crypto.randomUUID();
    const complaint = complaintObject(visitId);
    const filteredContext = { [VISIT_CHIEF_COMPLAINT_V1]: complaint };
    const userIntent = intentForPreflightTotal(
      filteredContext,
      PREFLIGHT_FAIL_TOTAL_BYTES,
    );

    const result = await postH0(scenario, token, {
      body: happyVisitBody(scenario, {
        user_intent: userIntent,
        context: {
          org: scenario.orgId,
          branch: scenario.branchId,
          [VISIT_CHIEF_COMPLAINT_V1]: complaint,
        },
      }),
    });

    assertJsonTaxonomy(result, 413, "request_too_large", false);
    expect(result.body?.request_reference).not.toBe("");
    expect(result.body?.trace_id).toBe(TRACE_ID);
    await assertNoGuardWrites();
  });

  it("S09-065 — jti replay is unauthenticated", async () => {
    const scenario = await provisionHappyPath();
    const token = await mintAat(scenario, { claims: { jti: S09_065_JTI } });

    const first = await postH0(scenario, token, { idempotencyKey: "jti-a" });
    const accepted = assertAcceptedSse(first, { traceId: TRACE_ID });
    const firstRef = String(accepted.data.request_reference);
    const firstRow = await getAiRequest(firstRef);
    expect(firstRow).not.toBeNull();
    expect(await count("ai_request")).toBe(1);

    const second = await postH0(scenario, token, { idempotencyKey: "jti-b" });
    expect(second.status).toBe(401);
    assertTaxonomyBody(second.body, {
      code: "unauthenticated",
      retry_safe: true,
    });
    assertRequestReferenceShape(String(second.body?.request_reference));
    expect(second.body?.trace_id).toBe(TRACE_ID);

    expect(await count("ai_request")).toBe(1);
    const after = await getAiRequest(firstRef);
    expect(after).not.toBeNull();
    // Catalog S09-065: first journal row "untouched". Code keeps settling
    // request 1 after accept (payload_pointer, routing_decision, state,
    // timestamps) via persistPostResponseDetail / journalTransition — not a
    // second INSERT. Replay must not rewrite identity columns.
    const settlementKeys = new Set([
      "payload_pointer",
      "routing_decision",
      "state",
      "updated_at",
      "completed_at",
      "terminal_error_code",
    ]);
    const identityOf = (row: Record<string, unknown>) =>
      Object.fromEntries(
        Object.entries(row).filter(([key]) => !settlementKeys.has(key)),
      );
    expect(identityOf(after!)).toEqual(identityOf(firstRow!));
    expect(after?.idempotency_key).toBe("jti-a");
    const pointer = after?.payload_pointer;
    if (pointer != null) {
      expect(pointer).toBe(`request/${String(firstRow?.request_id)}/envelope`);
    }
  });
});
