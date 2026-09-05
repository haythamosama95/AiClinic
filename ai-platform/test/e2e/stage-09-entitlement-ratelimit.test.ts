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
  createRateLimiterDouble,
  DEFAULT_ENTITLE_PAYLOAD,
  env,
  getAiRequest,
  getGrants,
  installEnvOverrides,
  mintAat,
  postRequest,
  provisionHappyPath,
  resetE2eState,
  seedSql,
  visitSummaryInvokeBody,
  type EntitlePayload,
  type InvokeResult,
  type RateLimiterOutcome,
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
const GRANT_REVOKED_AT = "2026-09-05T00:00:00.000Z";

/** DEFAULT also writes a plan grant; these journeys must not fall through to it. */
const INSTALLATION_ONLY_ENTITLE: EntitlePayload = {
  ...DEFAULT_ENTITLE_PAYLOAD,
  grants: [
    {
      capability_id: CAPABILITY_ID,
      capability_version: CAPABILITY_VERSION,
      scope: "installation",
    },
  ],
};

/** S09-035: plan-scope grant admits when the installation grant is absent. */
const PLAN_ONLY_ENTITLE: EntitlePayload = {
  ...DEFAULT_ENTITLE_PAYLOAD,
  grants: [
    {
      capability_id: CAPABILITY_ID,
      capability_version: CAPABILITY_VERSION,
      scope: "plan",
    },
  ],
};

type RateLimitCall = { binding: string; key: string };

function happyVisitBody(
  scenario: Scenario,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return visitSummaryInvokeBody(scenario, {
    user_intent: "Summarize today's visit for the chart.",
    ...overrides,
  });
}

async function invokeHappy(
  scenario: Scenario,
  opts: { idempotencyKey?: string } = {},
): Promise<InvokeResult> {
  return postRequest(scenario, {
    token: await mintAat(scenario),
    traceId: TRACE_ID,
    idempotencyKey: opts.idempotencyKey,
    body: happyVisitBody(scenario),
  });
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
  expect(result.body?.trace_id).toBe(TRACE_ID);
}

function assertAcceptedSse(result: InvokeResult): SseEvent {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("text/event-stream");
  assertSseSequence(result.events, ["accepted"]);
  const accepted = result.events[0];
  expect(accepted?.event).toBe("accepted");
  assertRequestReferenceShape(String(accepted?.data.request_reference));
  expect(accepted?.data.trace_id).toBe(TRACE_ID);
  return accepted!;
}

async function assertNoGuardWrites(): Promise<void> {
  expect(await count("ai_request")).toBe(0);
  expect(await count("usage_event")).toBe(0);
  expect(await count("grace_admission_queue")).toBe(0);
}

async function armKillSwitch(scope: string, target: string): Promise<void> {
  const armed = await controlFetch("/control/kill-switches/arm", {
    body: { scope, target },
  });
  expect(armed.status).toBe(200);
  clearConfigCache();
}

async function disarmKillSwitch(scope: string, target: string): Promise<void> {
  await controlFetch("/control/kill-switches/disarm", {
    body: { scope, target },
  });
  clearConfigCache();
}

function loggedLimiter(
  binding: string,
  log: RateLimitCall[],
  outcome: RateLimiterOutcome,
): RateLimit {
  return createRateLimiterDouble((key) => {
    log.push({ binding, key });
    return outcome;
  });
}

/**
 * Register 5 #31. `installEnvOverrides` swapping RATE_LIMITER_* does not
 * reach `limit()` on `SELF.fetch` (worker reads `env` from cloudflare:workers).
 * Patch `.limit` on the live host objects, then swap env keys. Restore both.
 *
 * HARNESS-GAP: RATE_LIMITER_* override never reaches limit() if the host
 * object freezes `limit` and installEnvOverrides cannot replace the binding.
 */
function patchLiveRateLimiters(doubles: {
  installation: RateLimit;
  actor: RateLimit;
  capability: RateLimit;
}): () => void {
  const originalLimits: Array<{
    binding: RateLimit;
    limit: RateLimit["limit"];
  }> = [];
  const pairs: Array<[RateLimit, RateLimit]> = [
    [env.RATE_LIMITER_INSTALLATION, doubles.installation],
    [env.RATE_LIMITER_INSTALLATION_ACTOR, doubles.actor],
    [env.RATE_LIMITER_INSTALLATION_CAPABILITY, doubles.capability],
  ];
  for (const [binding, double] of pairs) {
    const limit = binding.limit;
    try {
      (binding as { limit: RateLimit["limit"] }).limit = (options) =>
        double.limit(options);
      originalLimits.push({ binding, limit });
    } catch {
      // Native ratelimit host objects may freeze `limit`.
    }
  }
  const restoreEnv = installEnvOverrides({
    RATE_LIMITER_INSTALLATION: doubles.installation,
    RATE_LIMITER_INSTALLATION_ACTOR: doubles.actor,
    RATE_LIMITER_INSTALLATION_CAPABILITY: doubles.capability,
  });
  return () => {
    restoreEnv();
    for (const { binding, limit } of originalLimits) {
      try {
        (binding as { limit: RateLimit["limit"] }).limit = limit;
      } catch {
        // ignore restore failures on frozen host objects
      }
    }
  };
}

describe("Stage 09 — entitlement and rate limit (S09-023…S09-043)", () => {
  it("S09-023 — suspended installation is installation_suspended", async () => {
    const scenario = await provisionHappyPath();
    const suspended = await controlFetch(
      `/control/installations/${scenario.installationId}/suspend`,
      { body: {} },
    );
    expect(suspended.status).toBe(200);
    clearConfigCache();

    const result = await invokeHappy(scenario);
    assertJsonTaxonomy(result, 403, "installation_suspended", false);
    expect(result.body).not.toHaveProperty("retry_after");
    await assertNoGuardWrites();

    const resumed = await controlFetch(
      `/control/installations/${scenario.installationId}/resume`,
      { body: {} },
    );
    expect(resumed.status).toBe(200);
  });

  it("S09-024 — deleted installation is unauthenticated not installation_suspended", async () => {
    const scenario = await provisionHappyPath();
    await seedSql([
      {
        sql: "UPDATE installation SET status = 'deleted' WHERE installation_id = ?",
        params: [scenario.installationId],
      },
    ]);
    clearConfigCache();

    const result = await invokeHappy(scenario);
    assertJsonTaxonomy(result, 401, "unauthenticated", true);
    expect(result.body?.code).not.toBe("installation_suspended");
    await assertNoGuardWrites();

    await seedSql([
      {
        sql: "UPDATE installation SET status = 'active' WHERE installation_id = ?",
        params: [scenario.installationId],
      },
    ]);
    clearConfigCache();
  });

  it("S09-025 — unknown token-contract ver 999 is unauthenticated", async () => {
    const scenario = await provisionHappyPath();
    const token = await mintAat(scenario, { claims: { ver: "999" } });

    const result = await postRequest(scenario, {
      token,
      traceId: TRACE_ID,
      body: happyVisitBody(scenario),
    });

    assertJsonTaxonomy(result, 401, "unauthenticated", true);
    await assertNoGuardWrites();
  });

  it("S09-026 — retired token-contract ver 1 is unauthenticated", async () => {
    const scenario = await provisionHappyPath();
    const opened = await controlFetch("/control/token-contract/begin-rotation", {
      body: { ver: "2" },
    });
    expect(opened.status).toBe(200);
    const retired = await controlFetch("/control/token-contract/retire", {
      body: { ver: "1" },
    });
    expect(retired.status).toBe(200);
    clearConfigCache();

    const result = await invokeHappy(scenario);
    assertJsonTaxonomy(result, 401, "unauthenticated", true);
    await assertNoGuardWrites();

    await seedSql([
      { sql: "DELETE FROM token_contract WHERE ver = ?", params: ["2"] },
      {
        sql: "UPDATE token_contract SET retired_at = NULL WHERE ver = ?",
        params: ["1"],
      },
    ]);
    clearConfigCache();
  });

  it("S09-027 — missing entitlement row is stage-3 internal_error", async () => {
    const scenario = await provisionHappyPath();
    await seedSql([
      {
        sql: "DELETE FROM entitlement WHERE installation_id = ?",
        params: [scenario.installationId],
      },
    ]);
    clearConfigCache();

    const result = await invokeHappy(scenario);
    assertJsonTaxonomy(result, 500, "internal_error", true);
    await assertNoGuardWrites();

    // Catalog restore via Stage 4 entitle: provisionHappyPath already wrote
    // grants; re-entitle INSERT capability_grant hits UNIQUE → storage_error.
    // Isolation is beforeEach resetE2eState().
  });

  it("S09-028 — non-active entitlement is forbidden_capability", async () => {
    const scenario = await provisionHappyPath();

    await seedSql([
      {
        sql: "UPDATE entitlement SET status = 'pending' WHERE installation_id = ?",
        params: [scenario.installationId],
      },
    ]);
    clearConfigCache();
    const pending = await invokeHappy(scenario);
    assertJsonTaxonomy(pending, 403, "forbidden_capability", false);
    await assertNoGuardWrites();

    await seedSql([
      {
        sql: "UPDATE entitlement SET status = 'suspended' WHERE installation_id = ?",
        params: [scenario.installationId],
      },
    ]);
    clearConfigCache();
    const suspended = await invokeHappy(scenario);
    assertJsonTaxonomy(suspended, 403, "forbidden_capability", false);
    await assertNoGuardWrites();

    await seedSql([
      {
        sql: "UPDATE entitlement SET status = 'active' WHERE installation_id = ?",
        params: [scenario.installationId],
      },
    ]);
    clearConfigCache();
  });

  it("S09-029 — plan below minimum is forbidden_capability", async () => {
    const scenario = await provisionHappyPath();

    await seedSql([
      {
        sql: "UPDATE entitlement SET plan = 'starter' WHERE installation_id = ?",
        params: [scenario.installationId],
      },
    ]);
    clearConfigCache();
    const starter = await invokeHappy(scenario);
    assertJsonTaxonomy(starter, 403, "forbidden_capability", false);
    await assertNoGuardWrites();

    await seedSql([
      {
        sql: "UPDATE entitlement SET plan = 'verify' WHERE installation_id = ?",
        params: [scenario.installationId],
      },
    ]);
    clearConfigCache();
    const unknown = await invokeHappy(scenario);
    assertJsonTaxonomy(unknown, 403, "forbidden_capability", false);
    await assertNoGuardWrites();

    await seedSql([
      {
        sql: "UPDATE entitlement SET plan = 'standard' WHERE installation_id = ?",
        params: [scenario.installationId],
      },
    ]);
    clearConfigCache();
  });

  it("S09-030 — empty allowed_capabilities is forbidden_capability", async () => {
    const scenario = await provisionHappyPath();
    await seedSql([
      {
        sql: "UPDATE entitlement SET allowed_capabilities = '[]' WHERE installation_id = ?",
        params: [scenario.installationId],
      },
    ]);
    clearConfigCache();

    const result = await invokeHappy(scenario);
    assertJsonTaxonomy(result, 403, "forbidden_capability", false);
    await assertNoGuardWrites();

    await seedSql([
      {
        sql: "UPDATE entitlement SET allowed_capabilities = ? WHERE installation_id = ?",
        params: [JSON.stringify([CAPABILITY_ID]), scenario.installationId],
      },
    ]);
    clearConfigCache();
  });

  it("S09-031 — malformed allowed_capabilities is forbidden_capability", async () => {
    const scenario = await provisionHappyPath();

    await seedSql([
      {
        sql: "UPDATE entitlement SET allowed_capabilities = 'not json' WHERE installation_id = ?",
        params: [scenario.installationId],
      },
    ]);
    clearConfigCache();
    const unparseable = await invokeHappy(scenario);
    assertJsonTaxonomy(unparseable, 403, "forbidden_capability", false);
    await assertNoGuardWrites();

    await seedSql([
      {
        sql: "UPDATE entitlement SET allowed_capabilities = ? WHERE installation_id = ?",
        params: [
          `["${CAPABILITY_ID}", 7]`,
          scenario.installationId,
        ],
      },
    ]);
    clearConfigCache();
    const mixed = await invokeHappy(scenario);
    assertJsonTaxonomy(mixed, 403, "forbidden_capability", false);
    await assertNoGuardWrites();

    await seedSql([
      {
        sql: "UPDATE entitlement SET allowed_capabilities = ? WHERE installation_id = ?",
        params: [JSON.stringify([CAPABILITY_ID]), scenario.installationId],
      },
    ]);
    clearConfigCache();
  });

  it("S09-032 — revoked installation-scope grant is forbidden_capability", async () => {
    // Reader filters revoked_at IS NULL, so a revoked installation grant is a
    // miss and plan fallback would admit. Entitle without the plan grant first.
    const scenario = await provisionHappyPath(undefined, INSTALLATION_ONLY_ENTITLE);
    expect(await getGrants("plan:standard")).toEqual([]);

    await seedSql([
      {
        sql: `UPDATE capability_grant SET revoked_at = ?
              WHERE scope = ? AND capability_id = ?`,
        params: [
          GRANT_REVOKED_AT,
          `installation:${scenario.installationId}`,
          CAPABILITY_ID,
        ],
      },
    ]);
    clearConfigCache();

    const result = await invokeHappy(scenario);
    assertJsonTaxonomy(result, 403, "forbidden_capability", false);
    await assertNoGuardWrites();

    await seedSql([
      {
        sql: `UPDATE capability_grant SET revoked_at = NULL
              WHERE scope = ? AND capability_id = ?`,
        params: [`installation:${scenario.installationId}`, CAPABILITY_ID],
      },
    ]);
    clearConfigCache();
  });

  it("S09-033 — grant capability_version mismatch is forbidden_capability", async () => {
    const scenario = await provisionHappyPath(undefined, INSTALLATION_ONLY_ENTITLE);
    expect(await getGrants("plan:standard")).toEqual([]);

    await seedSql([
      {
        sql: `UPDATE capability_grant SET capability_version = '9.9.9'
              WHERE scope = ? AND capability_id = ?`,
        params: [`installation:${scenario.installationId}`, CAPABILITY_ID],
      },
    ]);
    clearConfigCache();

    const result = await postRequest(scenario, {
      token: await mintAat(scenario),
      traceId: TRACE_ID,
      capabilityVersion: CAPABILITY_VERSION,
      body: happyVisitBody(scenario),
    });
    assertJsonTaxonomy(result, 403, "forbidden_capability", false);
    await assertNoGuardWrites();

    await seedSql([
      {
        sql: `UPDATE capability_grant SET capability_version = ?
              WHERE scope = ? AND capability_id = ?`,
        params: [
          CAPABILITY_VERSION,
          `installation:${scenario.installationId}`,
          CAPABILITY_ID,
        ],
      },
    ]);
    clearConfigCache();
  });

  it("S09-034 — no installation grant and no plan grant is forbidden_capability", async () => {
    const scenario = await provisionHappyPath(undefined, INSTALLATION_ONLY_ENTITLE);
    expect(await getGrants("plan:standard")).toEqual([]);

    await seedSql([
      {
        sql: `DELETE FROM capability_grant
              WHERE scope = ? AND capability_id = ?`,
        params: [`installation:${scenario.installationId}`, CAPABILITY_ID],
      },
    ]);
    clearConfigCache();

    const result = await invokeHappy(scenario);
    assertJsonTaxonomy(result, 403, "forbidden_capability", false);
    await assertNoGuardWrites();

    // Catalog restore via entitle: entitlement is already active (409 not_pending).
    // Grant rows are restored by beforeEach resetE2eState.
  });

  it("S09-035 — plan-scope grant admits a missing installation grant", async () => {
    const scenario = await provisionHappyPath(undefined, PLAN_ONLY_ENTITLE);
    expect(await getGrants(`installation:${scenario.installationId}`)).toEqual(
      [],
    );
    expect(await getGrants("plan:standard")).toHaveLength(1);

    const result = await invokeHappy(scenario, {
      idempotencyKey: crypto.randomUUID(),
    });
    const accepted = assertAcceptedSse(result);
    expect(await count("ai_request")).toBe(1);
    const row = await getAiRequest(String(accepted.data.request_reference));
    expect(row).not.toBeNull();
    expect(row?.capability_id).toBe(CAPABILITY_ID);
    expect(row?.capability_version).toBe(CAPABILITY_VERSION);
  });

  it("S09-036 — global kill switch is capability_disabled", async () => {
    const scenario = await provisionHappyPath();
    await armKillSwitch("global", "global");

    try {
      const result = await invokeHappy(scenario);
      assertJsonTaxonomy(result, 503, "capability_disabled", true);
      await assertNoGuardWrites();
    } finally {
      await disarmKillSwitch("global", "global");
    }
  });

  it("S09-037 — capability kill switch is capability_disabled", async () => {
    const scenario = await provisionHappyPath();
    await armKillSwitch("capability", CAPABILITY_ID);

    try {
      const result = await invokeHappy(scenario);
      assertJsonTaxonomy(result, 503, "capability_disabled", true);
      await assertNoGuardWrites();
    } finally {
      await disarmKillSwitch("capability", CAPABILITY_ID);
    }
  });

  it("S09-038 — installation kill switch is capability_disabled", async () => {
    const scenario = await provisionHappyPath();
    await armKillSwitch("installation", scenario.installationId);

    try {
      const result = await invokeHappy(scenario);
      assertJsonTaxonomy(result, 503, "capability_disabled", true);
      await assertNoGuardWrites();
    } finally {
      await disarmKillSwitch("installation", scenario.installationId);
    }
  });

  it("S09-039 — provider kill switch on fake is capability_disabled", async () => {
    const scenario = await provisionHappyPath();
    await armKillSwitch("provider", "fake");

    try {
      const result = await invokeHappy(scenario);
      assertJsonTaxonomy(result, 503, "capability_disabled", true);
      await assertNoGuardWrites();
    } finally {
      await disarmKillSwitch("provider", "fake");
    }
  });

  it("S09-040 — installation limiter trips with binding retry_after 17", async () => {
    const scenario = await provisionHappyPath();
    const calls: RateLimitCall[] = [];
    const deny = loggedLimiter("RATE_LIMITER_INSTALLATION", calls, {
      success: false,
      retryAfter: 17,
    });
    const allowActor = loggedLimiter(
      "RATE_LIMITER_INSTALLATION_ACTOR",
      calls,
      { success: true },
    );
    const allowCapability = loggedLimiter(
      "RATE_LIMITER_INSTALLATION_CAPABILITY",
      calls,
      { success: true },
    );
    const restore = patchLiveRateLimiters({
      installation: deny,
      actor: allowActor,
      capability: allowCapability,
    });
    try {
      const result = await invokeHappy(scenario);
      assertJsonTaxonomy(result, 429, "rate_limited", true);
      expect(result.body?.retry_after).toBe(17);
      expect(calls).toEqual([
        {
          binding: "RATE_LIMITER_INSTALLATION",
          key: scenario.installationId,
        },
      ]);
      await assertNoGuardWrites();
    } finally {
      restore();
    }
  });

  it("S09-041 — actor limiter with no hint uses retry_after 60", async () => {
    const scenario = await provisionHappyPath();
    const variants: Array<{ retryAfter?: number }> = [
      {},
      { retryAfter: 0 },
      { retryAfter: -3 },
    ];

    for (const variant of variants) {
      const calls: RateLimitCall[] = [];
      const allowInstallation = loggedLimiter(
        "RATE_LIMITER_INSTALLATION",
        calls,
        { success: true },
      );
      const denyActor = loggedLimiter(
        "RATE_LIMITER_INSTALLATION_ACTOR",
        calls,
        variant.retryAfter === undefined
          ? { success: false }
          : { success: false, retryAfter: variant.retryAfter },
      );
      const allowCapability = loggedLimiter(
        "RATE_LIMITER_INSTALLATION_CAPABILITY",
        calls,
        { success: true },
      );
      const restore = patchLiveRateLimiters({
        installation: allowInstallation,
        actor: denyActor,
        capability: allowCapability,
      });
      try {
        const result = await invokeHappy(scenario);
        assertJsonTaxonomy(result, 429, "rate_limited", true);
        expect(result.body?.retry_after).toBe(60);
        expect(calls).toEqual([
          {
            binding: "RATE_LIMITER_INSTALLATION",
            key: scenario.installationId,
          },
          {
            binding: "RATE_LIMITER_INSTALLATION_ACTOR",
            key: `${scenario.installationId}:${scenario.actorId}`,
          },
        ]);
        await assertNoGuardWrites();
      } finally {
        restore();
      }
    }
  });

  it("S09-042 — capability limiter ceils fractional retryAfter 3.2 to 4", async () => {
    const scenario = await provisionHappyPath();
    const calls: RateLimitCall[] = [];
    const allowInstallation = loggedLimiter(
      "RATE_LIMITER_INSTALLATION",
      calls,
      { success: true },
    );
    const allowActor = loggedLimiter(
      "RATE_LIMITER_INSTALLATION_ACTOR",
      calls,
      { success: true },
    );
    const denyCapability = loggedLimiter(
      "RATE_LIMITER_INSTALLATION_CAPABILITY",
      calls,
      { success: false, retryAfter: 3.2 },
    );
    const restore = patchLiveRateLimiters({
      installation: allowInstallation,
      actor: allowActor,
      capability: denyCapability,
    });
    try {
      const result = await invokeHappy(scenario);
      assertJsonTaxonomy(result, 429, "rate_limited", true);
      expect(result.body?.retry_after).toBe(4);
      expect(calls).toEqual([
        {
          binding: "RATE_LIMITER_INSTALLATION",
          key: scenario.installationId,
        },
        {
          binding: "RATE_LIMITER_INSTALLATION_ACTOR",
          key: `${scenario.installationId}:${scenario.actorId}`,
        },
        {
          binding: "RATE_LIMITER_INSTALLATION_CAPABILITY",
          key: `${scenario.installationId}:${CAPABILITY_ID}`,
        },
      ]);
      await assertNoGuardWrites();
    } finally {
      restore();
    }
  });

  it("S09-043 — rate-limit short-circuits after installation dimension", async () => {
    const scenario = await provisionHappyPath();
    const calls: RateLimitCall[] = [];
    const denyInstallation = loggedLimiter(
      "RATE_LIMITER_INSTALLATION",
      calls,
      { success: false, retryAfter: 9 },
    );
    const denyActor = loggedLimiter(
      "RATE_LIMITER_INSTALLATION_ACTOR",
      calls,
      { success: false, retryAfter: 9 },
    );
    const denyCapability = loggedLimiter(
      "RATE_LIMITER_INSTALLATION_CAPABILITY",
      calls,
      { success: false, retryAfter: 9 },
    );
    const restore = patchLiveRateLimiters({
      installation: denyInstallation,
      actor: denyActor,
      capability: denyCapability,
    });
    try {
      const result = await invokeHappy(scenario);
      assertJsonTaxonomy(result, 429, "rate_limited", true);
      expect(calls).toEqual([
        {
          binding: "RATE_LIMITER_INSTALLATION",
          key: scenario.installationId,
        },
      ]);
      await assertNoGuardWrites();
    } finally {
      restore();
    }
  });
});
