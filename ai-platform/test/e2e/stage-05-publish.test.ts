import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  bootstrapE2e,
  controlFetch,
  count,
  dispatchControl,
  dispatchControlRequest,
  env,
  GATEWAY_ORIGIN,
  getAudits,
  getR2Json,
  getRoutingPolicy,
  OPERATOR_BEARER,
  OPERATOR_ID,
  operatorAuthFromEnv,
  PLATFORM_TABLES,
  publishPolicy,
  queryAll,
  readHttpResult,
  resetE2eState,
  r2Exists,
  uniqueConstraintError,
  wrapD1,
  type HttpResult,
} from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});

const PUBLISH_PATH = "/control/routing-policies/publish";
const STANDARD_V1_POINTER = "control/routing-policy/standard/1.json";
const ISO_8601 = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const CLOCK_SKEW_MS = 15_000;

/** Verbatim `ai-platform/control/routing-policy/platform-default/1.json`. */
const PLATFORM_DEFAULT_DOCUMENT = {
  schema_version: 1,
  policy_id: "standard",
  policy_version: 1,
  defaults: {
    cost_class: "standard",
    max_parallel_attempts: 1,
  },
  rules: [
    {
      rule_id: "platform-default-fallback",
      match: {},
      requires: {
        structured_output: false,
        min_context_window: 0,
        languages: [] as string[],
      },
      targets: [
        {
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
        },
        {
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
        },
      ],
    },
  ],
  overrides: [] as unknown[],
};

const UNREFERENCED_PREMIUM_EU_DOCUMENT = {
  schema_version: 1,
  policy_id: "premium-eu",
  policy_version: 1,
  defaults: { cost_class: "premium", max_parallel_attempts: 1 },
  rules: [
    {
      rule_id: "catch-all",
      match: {},
      requires: {
        structured_output: false,
        min_context_window: 0,
        languages: [] as string[],
      },
      targets: [
        {
          provider_id: "gemini",
          model_id: "gemini-3.5-pro",
          features: {
            structured_output: true,
            min_context_window: 200000,
            languages: ["en"],
            latency_class: "standard",
            cost_class: "premium",
          },
          max_attempts: 2,
          timeout_ms: 30000,
        },
      ],
    },
  ],
  overrides: [] as unknown[],
};

const LATENCY_MISMATCH_STANDARD_V7_DOCUMENT = {
  schema_version: 1,
  policy_id: "standard",
  policy_version: 7,
  defaults: { cost_class: "standard", max_parallel_attempts: 1 },
  rules: [
    {
      rule_id: "catch-all",
      match: {},
      requires: {
        structured_output: false,
        min_context_window: 0,
        languages: [] as string[],
      },
      targets: [
        {
          provider_id: "deepseek",
          model_id: "deepseek-v4-flash",
          features: {
            structured_output: true,
            min_context_window: 128000,
            languages: ["en"],
            latency_class: "batch",
            cost_class: "economy",
          },
          max_attempts: 2,
          timeout_ms: 30000,
        },
      ],
    },
  ],
  overrides: [] as unknown[],
};

const DUPLICATE_STANDARD_V1_DOCUMENT = {
  schema_version: 1,
  policy_id: "standard",
  policy_version: 1,
  defaults: { cost_class: "economy", max_parallel_attempts: 1 },
  rules: [
    {
      rule_id: "catch-all",
      match: {},
      requires: {
        structured_output: false,
        min_context_window: 0,
        languages: [] as string[],
      },
      targets: [
        {
          provider_id: "gemini",
          model_id: "gemini-3.5-flash",
          features: {
            structured_output: true,
            min_context_window: 128000,
            languages: ["en"],
            latency_class: "standard",
            cost_class: "economy",
          },
          max_attempts: 1,
          timeout_ms: 15000,
        },
      ],
    },
  ],
  overrides: [] as unknown[],
};

const IDENTITY_SHELL = {
  schema_version: 1,
  defaults: { cost_class: "standard", max_parallel_attempts: 1 },
  rules: [] as unknown[],
  overrides: [] as unknown[],
};

function contentPointer(policyId: string, version: number | string): string {
  return `control/routing-policy/${policyId}/${version}.json`;
}

function publish(
  body: unknown,
  auth?: "operator" | "none" | "wrong" | "empty" | "basic",
): Promise<HttpResult> {
  return controlFetch(PUBLISH_PATH, auth ? { auth, body } : { body });
}

function assertOkEmpty(result: HttpResult): void {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.json).toEqual({});
}

function assertOkWarnings(result: HttpResult, warnings: string[]): void {
  expect(result.status).toBe(200);
  expect(result.headers.get("content-type")).toContain("application/json");
  expect(result.json).toEqual({ warnings });
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

function assertIsoApproxNow(value: unknown): string {
  expect(typeof value).toBe("string");
  const iso = String(value);
  expect(iso).toMatch(ISO_8601);
  const parsed = Date.parse(iso);
  expect(Number.isNaN(parsed)).toBe(false);
  expect(Math.abs(Date.now() - parsed)).toBeLessThan(CLOCK_SKEW_MS);
  return iso;
}

async function r2Text(key: string): Promise<string | null> {
  const object = await env.R2.get(key);
  if (!object) {
    return null;
  }
  return object.text();
}

async function assertNoPublishWrites(pointer?: string): Promise<void> {
  expect(await count("routing_policy")).toBe(0);
  expect(await count("control_audit")).toBe(0);
  if (pointer) {
    expect(await r2Exists(pointer)).toBe(false);
  }
  expect(await r2Exists(STANDARD_V1_POINTER)).toBe(false);
}

async function assertPublishedRow(opts: {
  policyId: string;
  version: string;
  pointer: string;
  target: string;
}): Promise<void> {
  const row = await getRoutingPolicy(opts.policyId, opts.version);
  expect(row).not.toBeNull();
  expect(row?.policy_id).toBe(opts.policyId);
  expect(row?.version).toBe(opts.version);
  expect(row?.content_pointer).toBe(opts.pointer);
  expect(row?.activated_by).toBe(OPERATOR_ID);
  expect(row?.canary_installation_ids).toBeNull();
  expect(row?.status).toBe("published");
  const activeFrom = assertIsoApproxNow(row?.active_from);

  const audits = await getAudits("routing_policy_publish", opts.target);
  expect(audits).toHaveLength(1);
  expect(audits[0]?.operator_id).toBe(OPERATOR_ID);
  expect(audits[0]?.action).toBe("routing_policy_publish");
  expect(audits[0]?.target).toBe(opts.target);
  expect(audits[0]?.before_pointer).toBeNull();
  expect(audits[0]?.after_pointer).toBe(opts.pointer);
  expect(audits[0]?.recorded_at).toBe(activeFrom);

  expect(await count("routing_policy")).toBe(1);
  expect(await count("control_audit")).toBe(1);
}

async function assertOnlyPublishTablesTouched(): Promise<void> {
  for (const table of PLATFORM_TABLES) {
    if (table === "token_contract") {
      expect(await count(table)).toBe(1);
      continue;
    }
    if (table === "routing_policy" || table === "control_audit") {
      expect(await count(table)).toBe(1);
      continue;
    }
    expect(await count(table)).toBe(0);
  }
}

describe("Stage 05 — routing policy publish (S05-001…S05-020)", () => {
  it("S05-001 — Publish platform-default policy", async () => {
    const result = await publish({ document: PLATFORM_DEFAULT_DOCUMENT });

    assertOkEmpty(result);

    const stored = await env.R2.get(STANDARD_V1_POINTER);
    expect(stored).not.toBeNull();
    expect(stored?.httpMetadata?.contentType).toBe("application/json");
    expect(await stored!.text()).toBe(JSON.stringify(PLATFORM_DEFAULT_DOCUMENT));
    expect(await getR2Json(STANDARD_V1_POINTER)).toEqual(
      PLATFORM_DEFAULT_DOCUMENT,
    );

    await assertPublishedRow({
      policyId: "standard",
      version: "1",
      pointer: STANDARD_V1_POINTER,
      target: "standard@1",
    });
    await assertOnlyPublishTablesTouched();
  });

  it("S05-002 — Publish unreferenced policy id warns unreferenced_policy", async () => {
    const pointer = contentPointer("premium-eu", 1);
    const result = await publish({ document: UNREFERENCED_PREMIUM_EU_DOCUMENT });

    assertOkWarnings(result, ["unreferenced_policy"]);

    expect(await r2Text(pointer)).toBe(
      JSON.stringify(UNREFERENCED_PREMIUM_EU_DOCUMENT),
    );
    expect(await getR2Json(pointer)).toEqual(UNREFERENCED_PREMIUM_EU_DOCUMENT);

    await assertPublishedRow({
      policyId: "premium-eu",
      version: "1",
      pointer,
      target: "premium-eu@1",
    });
  });

  it("S05-003 — Publish referenced policy with latency_class_mismatch", async () => {
    const pointer = contentPointer("standard", 7);
    const result = await publish({
      document: LATENCY_MISMATCH_STANDARD_V7_DOCUMENT,
    });

    assertOkWarnings(result, ["latency_class_mismatch"]);

    expect(await r2Text(pointer)).toBe(
      JSON.stringify(LATENCY_MISMATCH_STANDARD_V7_DOCUMENT),
    );
    expect(await getR2Json(pointer)).toEqual(
      LATENCY_MISMATCH_STANDARD_V7_DOCUMENT,
    );

    await assertPublishedRow({
      policyId: "standard",
      version: "7",
      pointer,
      target: "standard@7",
    });
  });

  it("S05-004 — Duplicate publish returns already_published", async () => {
    const first = await publishPolicy(
      "standard",
      "1",
      PLATFORM_DEFAULT_DOCUMENT,
    );
    expect(first.status).toBe(200);
    const bytesBefore = await r2Text(STANDARD_V1_POINTER);
    expect(bytesBefore).toBe(JSON.stringify(PLATFORM_DEFAULT_DOCUMENT));
    const rowBefore = await getRoutingPolicy("standard", "1");
    const auditsBefore = await getAudits("routing_policy_publish", "standard@1");

    const result = await publish({ document: DUPLICATE_STANDARD_V1_DOCUMENT });

    assertControlError(result, 409, "already_published");
    expect(await r2Text(STANDARD_V1_POINTER)).toBe(bytesBefore);
    expect(await getR2Json(STANDARD_V1_POINTER)).toEqual(
      PLATFORM_DEFAULT_DOCUMENT,
    );
    expect(await getRoutingPolicy("standard", "1")).toEqual(rowBefore);
    expect(await count("routing_policy")).toBe(1);
    expect(await getAudits("routing_policy_publish", "standard@1")).toEqual(
      auditsBefore,
    );
    expect(await count("control_audit")).toBe(1);
  });

  it("S05-005 — Publish with unparseable JSON returns invalid_json", async () => {
    const result = await publish('{"document": {"policy_id": "standard",');

    assertControlError(result, 400, "invalid_json");
    await assertNoPublishWrites();
  });

  it("S05-006 — Publish without document key returns missing_document", async () => {
    const result = await publish({ policy_id: "standard", policy_version: 1 });

    assertControlError(result, 400, "missing_document");
    await assertNoPublishWrites();
  });

  it("S05-007 — Publish with document null returns missing_document", async () => {
    const result = await publish({ document: null });

    assertControlError(result, 400, "missing_document");
    await assertNoPublishWrites();
  });

  it("S05-008 — Publish with a string document returns missing_document", async () => {
    const result = await publish({ document: "standard@1" });

    assertControlError(result, 400, "missing_document");
    await assertNoPublishWrites();
  });

  it("S05-009 — Publish with an array document returns invalid_policy_identity", async () => {
    const result = await publish({ document: [] });

    assertControlError(result, 400, "invalid_policy_identity");
    await assertNoPublishWrites();
  });

  it("S05-010 — Publish with missing policy_id returns invalid_policy_identity", async () => {
    const result = await publish({
      document: { ...IDENTITY_SHELL, policy_version: 1 },
    });

    assertControlError(result, 400, "invalid_policy_identity");
    await assertNoPublishWrites();
  });

  it("S05-011 — Publish with empty-string policy_id returns invalid_policy_identity", async () => {
    const result = await publish({
      document: { ...IDENTITY_SHELL, policy_id: "", policy_version: 1 },
    });

    assertControlError(result, 400, "invalid_policy_identity");
    await assertNoPublishWrites();
  });

  it("S05-012 — Publish with numeric policy_id returns invalid_policy_identity", async () => {
    const result = await publish({
      document: { ...IDENTITY_SHELL, policy_id: 42, policy_version: 1 },
    });

    assertControlError(result, 400, "invalid_policy_identity");
    await assertNoPublishWrites();
  });

  it("S05-013 — Publish with string policy_version returns invalid_policy_identity", async () => {
    const result = await publish({
      document: {
        ...IDENTITY_SHELL,
        policy_id: "standard",
        policy_version: "1",
      },
    });

    assertControlError(result, 400, "invalid_policy_identity");
    await assertNoPublishWrites();
  });

  it("S05-014 — Publish with fractional policy_version returns invalid_policy_identity", async () => {
    const result = await publish({
      document: {
        ...IDENTITY_SHELL,
        policy_id: "standard",
        policy_version: 1.5,
      },
    });

    assertControlError(result, 400, "invalid_policy_identity");
    await assertNoPublishWrites();
  });

  it("S05-015 — Publish with policy_version 0 or negative returns invalid_policy_identity", async () => {
    const zero = await publish({
      document: {
        ...IDENTITY_SHELL,
        policy_id: "standard",
        policy_version: 0,
      },
    });
    assertControlError(zero, 400, "invalid_policy_identity");

    const negative = await publish({
      document: {
        ...IDENTITY_SHELL,
        policy_id: "standard",
        policy_version: -3,
      },
    });
    assertControlError(negative, 400, "invalid_policy_identity");
    await assertNoPublishWrites();
  });

  it("S05-016 — Publish without an R2 binding returns missing_r2_binding", async () => {
    // Register 5 #2: missing R2 is not expressible via SELF.fetch / dispatchControl
    // (controlBindingsFromEnv fills R2 from pool env). Call dispatchControlRequest
    // with { DB } only so the handler sees a missing R2 binding.
    const response = await dispatchControlRequest(
      new Request(`${GATEWAY_ORIGIN}${PUBLISH_PATH}`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${OPERATOR_BEARER}`,
        },
        body: JSON.stringify({ document: PLATFORM_DEFAULT_DOCUMENT }),
      }),
      { DB: env.DB },
      operatorAuthFromEnv(),
    );
    const result = await readHttpResult(response);

    assertControlError(result, 500, "missing_r2_binding");
    await assertNoPublishWrites();
  });

  it("S05-017 — Publish without Authorization header returns unauthorized", async () => {
    const result = await publish(
      { document: PLATFORM_DEFAULT_DOCUMENT },
      "none",
    );

    assertControlError(result, 401, "unauthorized");
    await assertNoPublishWrites();
  });

  it("S05-018 — Publish with wrong bearer token returns unauthorized", async () => {
    const result = await publish(
      { document: PLATFORM_DEFAULT_DOCUMENT },
      "wrong",
    );

    assertControlError(result, 401, "unauthorized");
    await assertNoPublishWrites();
  });

  it("S05-019 — Publish with non-Bearer scheme and empty bearer returns unauthorized", async () => {
    const basic = await publish(
      { document: PLATFORM_DEFAULT_DOCUMENT },
      "basic",
    );
    assertControlError(basic, 401, "unauthorized");

    const empty = await publish(
      { document: PLATFORM_DEFAULT_DOCUMENT },
      "empty",
    );
    assertControlError(empty, 401, "unauthorized");
    await assertNoPublishWrites();
  });

  it("S05-020 — Concurrent first publish maps UNIQUE to already_published", async () => {
    // Register 5 #10: pool D1 serializes concurrent publishes; a SELF.fetch
    // race cannot interleave SELECT and batch. wrapD1({ batchUniqueThrow }) +
    // dispatchControl is the documented seam for the UNIQUE → 409 mapping
    // (isUniqueConstraint). uniqueConstraintError("other") is the typed
    // generic UNIQUE payload (harness does not take a routing_policy target).
    const body = JSON.stringify({ document: PLATFORM_DEFAULT_DOCUMENT });
    const db = wrapD1(env.DB, {
      batchUniqueThrow: uniqueConstraintError("other"),
    });
    const uniqueResponse = await dispatchControl(
      new Request(`${GATEWAY_ORIGIN}${PUBLISH_PATH}`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${OPERATOR_BEARER}`,
          "content-type": "application/json",
        },
        body,
      }),
      { DB: db },
    );
    const uniqueResult = await readHttpResult(uniqueResponse);

    assertControlError(uniqueResult, 409, "already_published");
    expect(await r2Exists(STANDARD_V1_POINTER)).toBe(true);
    expect(await count("routing_policy")).toBe(0);
    expect(await count("control_audit")).toBe(0);
    expect(await queryAll("SELECT * FROM routing_policy")).toEqual([]);

    const winner = await publish({ document: PLATFORM_DEFAULT_DOCUMENT });
    assertOkEmpty(winner);

    expect(await r2Exists(STANDARD_V1_POINTER)).toBe(true);
    await assertPublishedRow({
      policyId: "standard",
      version: "1",
      pointer: STANDARD_V1_POINTER,
      target: "standard@1",
    });
  });
});
