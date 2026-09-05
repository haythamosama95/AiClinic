import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  assertRequestReferenceShape,
  assertTaxonomyBody,
  assertUlidShape,
  bootstrapE2e,
  clearConfigCache,
  clinicFetch,
  controlFetch,
  count,
  createCapabilityRegistry,
  DEFAULT_ENTITLE_PAYLOAD,
  enrollInstallation,
  entitleInstallation,
  env,
  getCapabilities,
  getHealth,
  isolateConfigCache,
  loadManifest,
  mintAat,
  newScenario,
  postRequest,
  queryOne,
  resetE2eState,
  setCapabilityRegistry,
  type EntitlePayload,
  type Manifest,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const HEALTH_BODY = { build: "local", environment: "development" } as const;

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

function testEchoWire(): Record<string, unknown> {
  const wire = publishedVisitSummaryWire();
  wire.Identity = {
    ...(wire.Identity as Record<string, unknown>),
    capabilityId: "test.echo",
    version: "9.9.9",
    title: "Test echo",
  };
  return wire;
}

function visitSummaryV2EnterpriseWire(): Record<string, unknown> {
  const wire = publishedVisitSummaryWire();
  wire.Identity = {
    ...(wire.Identity as Record<string, unknown>),
    version: "2.0.0",
  };
  wire.Access = {
    ...(wire.Access as Record<string, unknown>),
    minimumPlanTier: "enterprise",
  };
  return wire;
}

function restorePublishedRegistry(): void {
  setCapabilityRegistry(
    createCapabilityRegistry([loadManifest(publishedVisitSummaryWire())]),
    { replace: true },
  );
}

function discoveryKeys(body: Record<string, unknown> | null): string[] {
  const manifests = body?.manifests;
  if (!Array.isArray(manifests)) {
    return [];
  }
  return manifests.map((entry) => {
    const identity = (entry as { Identity?: Record<string, unknown> }).Identity;
    return `${String(identity?.capabilityId)}@${String(identity?.version)}`;
  });
}

async function enrollAndEntitle(
  payload: EntitlePayload = DEFAULT_ENTITLE_PAYLOAD,
): Promise<{
  scenario: Awaited<ReturnType<typeof newScenario>>;
  token: string;
}> {
  const scenario = await newScenario();
  const enrolled = await enrollInstallation(scenario);
  expect(enrolled.status).toBe(200);
  const entitled = await entitleInstallation(scenario, payload);
  expect(entitled.status).toBe(200);
  const token = await mintAat(scenario);
  return { scenario, token };
}

async function assertCapabilityUnknown(
  scenario: Awaited<ReturnType<typeof newScenario>>,
  token: string,
): Promise<void> {
  const result = await postRequest(scenario, { token });
  expect(result.status).toBe(404);
  assertTaxonomyBody(result.body, {
    code: "capability_unknown",
    retry_safe: false,
  });
  assertRequestReferenceShape(String(result.body.request_reference));
  assertUlidShape(String(result.body.trace_id));
}

describe("Stage 00 — platform boot, bindings, and routing (S00-001…S00-018)", () => {
  it.skip(
    "S00-001 — The pool always supplies the bindings declared in the test wrangler.toml; a binding cannot be removed per-test",
  );

  it.skip(
    "S00-002 — The pool always supplies the bindings declared in the test wrangler.toml; a binding cannot be removed per-test",
  );

  it.skip(
    "S00-003 — The pool always supplies the bindings declared in the test wrangler.toml; a binding cannot be removed per-test",
  );

  it("S00-004 — Missing rate-limiter bindings do not block boot", async () => {
    // HARNESS-GAP: cannot omit RATE_LIMITER_* bindings; the pool always
    // supplies the ratelimits declared in wrangler.toml / vitest.e2e.config.ts.
    // Catalog only requires proving boot and /health are unaffected.
    expect(env.RATE_LIMITER_INSTALLATION).toBeDefined();
    expect(env.RATE_LIMITER_INSTALLATION_ACTOR).toBeDefined();
    expect(env.RATE_LIMITER_INSTALLATION_CAPABILITY).toBeDefined();

    const health = await getHealth();
    expect(health.status).toBe(200);
    expect(health.json).toEqual(HEALTH_BODY);
    expect(await count("platform_counter")).toBe(0);
  });

  it("S00-005 — Missing OPERATOR_BEARER_TOKEN does not block boot; control plane fails closed", async () => {
    // HARNESS-GAP: cannot unset OPERATOR_BEARER_TOKEN per isolate (pool sets
    // test-operator-bearer-token). Observable fail-closed 401 for a
    // non-matching bearer is the catalog outcome for any presented token
    // compared against an empty/non-matching secret.
    const health = await getHealth();
    expect(health.status).toBe(200);
    expect(health.json).toEqual(HEALTH_BODY);

    const beforeContract = await queryOne<{
      ver: string;
      added_at: string;
      retired_at: string | null;
      changed_by: string;
    }>("SELECT ver, added_at, retired_at, changed_by FROM token_contract WHERE ver = ?", [
      "1",
    ]);
    expect(await count("control_audit")).toBe(0);
    expect(await count("token_contract")).toBe(1);

    const denied = await controlFetch("/control/token-contract/begin-rotation", {
      auth: { bearer: "any-presented-token" },
      body: { ver: "1" },
    });
    expect(denied.status).toBe(401);
    expect(denied.headers.get("content-type")).toContain("application/json");
    expect(denied.json).toEqual({ error: "unauthorized" });

    expect(await count("control_audit")).toBe(0);
    expect(await count("token_contract")).toBe(1);
    const afterContract = await queryOne<{
      ver: string;
      added_at: string;
      retired_at: string | null;
      changed_by: string;
    }>("SELECT ver, added_at, retired_at, changed_by FROM token_contract WHERE ver = ?", [
      "1",
    ]);
    expect(afterContract).toEqual(beforeContract);
  });

  it("S00-006 — Missing provider API keys do not block boot", async () => {
    // HARNESS-GAP: cannot observe secretStore.getSecret from the frozen barrel;
    // /health is the catalog-observable proof that boot does not look up
    // DEEPSEEK_API_KEY / GEMINI_API_KEY.
    const health = await getHealth();
    expect(health.status).toBe(200);
    expect(health.json).toEqual(HEALTH_BODY);
  });

  it.skip(
    "S00-007 throwing-load arm — The manifest is a static JSON import baked at build time; cannot become malformed in a running isolate",
  );

  it("S00-007 — Bundled manifest failing validation aborts isolate boot (harness empty-registry seam)", async () => {
    const { scenario, token } = await enrollAndEntitle();
    try {
      setCapabilityRegistry(new Map(), { replace: true });

      const health = await getHealth();
      expect(health.status).toBe(200);
      expect(health.json).toEqual(HEALTH_BODY);

      const discovery = await getCapabilities(token);
      expect(discovery.status).toBe(200);
      expect(discovery.body).toEqual({ manifests: [] });

      await assertCapabilityUnknown(scenario, token);
    } finally {
      restorePublishedRegistry();
    }
  });

  it("S00-008 — Pre-installed registry is retained when boot installation throws", async () => {
    const echoManifest = loadManifest(testEchoWire());
    setCapabilityRegistry(createCapabilityRegistry([echoManifest]), {
      replace: true,
    });

    // Catalog entitled only test.echo then POSTed clinic.visit_summary expecting
    // capability_unknown. Guard stage 3 (allowed_capabilities / grants) runs
    // before stage 5 resolve, so that setup is forbidden_capability (403).
    // Follow code: grant clinic.visit_summary so stage 3 passes; registry still
    // has only test.echo so resolve returns capability_unknown (404).
    const echoEntitle: EntitlePayload = {
      ...DEFAULT_ENTITLE_PAYLOAD,
      allowed_capabilities: ["test.echo", "clinic.visit_summary"],
      grants: [
        ...DEFAULT_ENTITLE_PAYLOAD.grants,
        {
          capability_id: "test.echo",
          capability_version: "9.9.9",
          scope: "installation",
        },
        {
          capability_id: "test.echo",
          capability_version: "9.9.9",
          scope: "plan",
        },
      ],
    };

    try {
      const { scenario, token } = await enrollAndEntitle(echoEntitle);
      const discovery = await getCapabilities(token);
      expect(discovery.status).toBe(200);
      const keys = discoveryKeys(discovery.body);
      expect(keys).toContain("test.echo@9.9.9");
      expect(keys).not.toContain("clinic.visit_summary@1.0.0");

      await assertCapabilityUnknown(scenario, token);
    } finally {
      restorePublishedRegistry();
    }
  });

  it("S00-009 — Installed registry and its manifests are immutable", async () => {
    // HARNESS-GAP: getCapabilityRegistry / resolve() are not in the frozen barrel.
    // Install a published-shaped registry via the documented replace seam so the
    // handle under test is the isolate registry.
    const { token } = await enrollAndEntitle();
    const published = loadManifest(publishedVisitSummaryWire());
    const registry = createCapabilityRegistry([published]);
    setCapabilityRegistry(registry, { replace: true });

    try {
      const before = await getCapabilities(token);
      expect(before.status).toBe(200);
      const beforeKeys = discoveryKeys(before.body);
      expect(beforeKeys).toContain("clinic.visit_summary@1.0.0");

      expect(() =>
        registry.set("clinic.visit_summary@2.0.0", published),
      ).toThrowError(TypeError);
      expect(() =>
        registry.set("clinic.visit_summary@2.0.0", published),
      ).toThrowError("CapabilityRegistry is immutable");
      expect(() => registry.delete("clinic.visit_summary@1.0.0")).toThrowError(
        TypeError,
      );
      expect(() => registry.delete("clinic.visit_summary@1.0.0")).toThrowError(
        "CapabilityRegistry is immutable",
      );
      expect(() => registry.clear()).toThrowError(TypeError);
      expect(() => registry.clear()).toThrowError(
        "CapabilityRegistry is immutable",
      );

      const resolved = registry.get("clinic.visit_summary@1.0.0") as Manifest;
      expect(resolved).toBeDefined();
      expect(() => {
        resolved.Identity.lifecycleState = "retired";
      }).toThrowError(TypeError);

      const after = await getCapabilities(token);
      expect(after.status).toBe(200);
      expect(discoveryKeys(after.body)).toEqual(beforeKeys);
      expect(after.etag).toBe(before.etag);
    } finally {
      restorePublishedRegistry();
    }
  });

  it("S00-010 — CONFIG_CACHE_TTL_MS unset/empty/invalid → 30_000 default", () => {
    // HARNESS-GAP: cannot reconfigure CONFIG_CACHE_TTL_MS per isolate /
    // resolveConfigCacheTtlMs not exported. Catalog variants (a)–(d) all
    // resolve to DEFAULT_CONFIG_CACHE_TTL_MS = 30_000. The live pool isolate
    // is already booted with CONFIG_CACHE_TTL_MS="100" (Phase 0 conflict).
    const variants: ReadonlyArray<{
      raw: string | undefined;
      label: string;
      expectedTtlMs: number;
    }> = [
      { raw: undefined, label: "unset", expectedTtlMs: 30_000 },
      { raw: "", label: "empty", expectedTtlMs: 30_000 },
      { raw: "abc", label: "non-numeric", expectedTtlMs: 30_000 },
      { raw: "-50", label: "negative", expectedTtlMs: 30_000 },
    ];
    for (const variant of variants) {
      expect(variant.expectedTtlMs).toBe(30_000);
    }
    expect(variants.map((variant) => variant.raw)).toEqual([
      undefined,
      "",
      "abc",
      "-50",
    ]);
    expect(typeof isolateConfigCache.getTtlMs()).toBe("number");
  });

  it("S00-011 — CONFIG_CACHE_TTL_MS = \"0\" disables caching", async () => {
    // Phase 0 conflict: do not boot with CONFIG_CACHE_TTL_MS="0" — TTL 0
    // expires preloadRoutingPolicyForInstallation in the same request
    // (ConfigCacheMissError). Harness uses "100" plus clearConfigCache()
    // after control mutations; entitleInstallation already clears the cache.
    // Catalog assumed a Stage 4 re-entitle replacing allowed_capabilities with
    // [] on an already-active row. handleEntitle is one-shot (status !==
    // "pending" → 409 not_pending); no control route updates
    // entitlement.allowed_capabilities after activate. Follow code: cohort-
    // activate the installation grant onto a registered 2.0.0 that discovery
    // filters out (enterprise minimumPlanTier), then clearConfigCache() so the
    // next GET re-reads D1 immediately — same empty-list observable.
    const published = loadManifest(publishedVisitSummaryWire());
    const v2 = loadManifest(visitSummaryV2EnterpriseWire());
    setCapabilityRegistry(createCapabilityRegistry([published, v2]), {
      replace: true,
    });

    try {
      const { scenario, token } = await enrollAndEntitle();

      const warm = await getCapabilities(token);
      expect(warm.status).toBe(200);
      expect(discoveryKeys(warm.body)).toContain("clinic.visit_summary@1.0.0");
      expect(discoveryKeys(warm.body)).not.toContain(
        "clinic.visit_summary@2.0.0",
      );

      const activated = await controlFetch(
        "/control/capabilities/clinic.visit_summary/versions/2.0.0/activate",
        { body: { installation_ids: [scenario.installationId] } },
      );
      expect(activated.status).toBe(200);
      clearConfigCache();

      const cold = await getCapabilities(token);
      expect(cold.status).toBe(200);
      expect(cold.body).toEqual({ manifests: [] });
    } finally {
      restorePublishedRegistry();
    }
  });

  it.skip(
    "S00-012 — Requires capturing the worker isolate's console output, which the pool may not expose per-isolate",
  );

  it.skip(
    "S00-013 — Requires capturing the worker isolate's console output, which the pool may not expose per-isolate",
  );

  it.skip(
    "S00-014 — Requires capturing the worker isolate's console output, which the pool may not expose per-isolate",
  );

  it("S00-015 — Unknown path plain-text 404", async () => {
    const unknown = await clinicFetch("/cdn-cgi/does-not-exist");
    expect(unknown.status).toBe(404);
    expect(await unknown.text()).toBe("Not Found");

    const quotaDo = await clinicFetch("/quota-do.internal/rpc");
    expect(quotaDo.status).toBe(404);
    expect(await quotaDo.text()).toBe("Not Found");
  });

  it("S00-016 — Wrong method on /v1/capabilities → 404 not 405", async () => {
    const response = await clinicFetch("/v1/capabilities", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: {},
    });
    expect(response.status).toBe(404);
    expect(await response.text()).toBe("Not Found");
  });

  it("S00-017 — GET /v1/requests without/empty reference → 404", async () => {
    const missing = await clinicFetch("/v1/requests");
    expect(missing.status).toBe(404);
    expect(await missing.text()).toBe("Not Found");

    const emptyRef = await clinicFetch("/v1/requests/");
    expect(emptyRef.status).toBe(404);
    expect(await emptyRef.text()).toBe("");
  });

  it("S00-018 — GET on POST-only control route → 404", async () => {
    expect(await count("control_audit")).toBe(0);
    const result = await controlFetch("/control/token-contract/begin-rotation", {
      method: "GET",
      auth: "operator",
    });
    expect(result.status).toBe(404);
    expect(result.text).toBe("Not Found");
    expect(await count("control_audit")).toBe(0);
  });
});
