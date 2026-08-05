/**
 * Worker entry seam tests (§5.2 final review).
 * Stubs/mocks live only in this file — production modules are exercised through
 * the worker default export / GatewayObject after dependency injection via vi.mock.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mockHandleAdapterRequest = vi.fn();
const mockAuthenticateGetRequest = vi.fn();
const mockGetRequest = vi.fn();
const mockGetRequestAuthErrorBody = vi.fn();
const mockFlushRejectionCounters = vi.fn();
const mockReconcileGraceUsage = vi.fn();
const mockRunRetentionPurge = vi.fn();
const mockCreateManifestRetentionClassResolver = vi.fn(() => vi.fn());
const mockRunRollupAndReconciliation = vi.fn();
const mockLogReconciliationReport = vi.fn();
const mockAdmissionRPC = vi.fn();
const mockCreditRPC = vi.fn();
const mockLiveHttpStatusForCode = vi.fn(
  (code: string) => (code === "unauthenticated" ? 401 : 403),
);

const runtimeEnv = {
  DB: { kind: "d1" },
  R2: { kind: "r2" },
  DO: { kind: "do" },
  BUILD_SHA: "test-sha",
  ENVIRONMENT: "development",
  OPERATOR_BEARER_TOKEN: "op-token",
  OPERATOR_ID: "op-id",
  RATE_LIMITER_INSTALLATION: {},
  RATE_LIMITER_INSTALLATION_ACTOR: {},
  RATE_LIMITER_INSTALLATION_CAPABILITY: {},
};

vi.mock("cloudflare:workers", () => {
  class DurableObject {
    ctx: unknown;
    env: unknown;
    constructor(ctx: unknown, env: unknown) {
      this.ctx = ctx;
      this.env = env;
    }
  }
  return { DurableObject, env: runtimeEnv };
});

vi.mock("../src/adapter", () => ({
  handleAdapterRequest: (...args: unknown[]) => mockHandleAdapterRequest(...args),
}));

vi.mock("../src/control", () => ({
  createSecretOperatorAuth: vi.fn(() => ({ resolve: () => null })),
  dispatchControlRequest: vi.fn(),
  isControlRoute: () => false,
}));

vi.mock("../src/credit", () => ({
  reconcileGraceUsage: (...args: unknown[]) => mockReconcileGraceUsage(...args),
}));

vi.mock("../src/errors", () => ({
  liveHttpStatusForCode: (code: string) => mockLiveHttpStatusForCode(code),
}));

vi.mock("../src/journal", () => ({
  authenticateGetRequest: (...args: unknown[]) =>
    mockAuthenticateGetRequest(...args),
  getRequest: (...args: unknown[]) => mockGetRequest(...args),
  getRequestAuthErrorBody: (...args: unknown[]) =>
    mockGetRequestAuthErrorBody(...args),
}));

vi.mock("../src/rate-limit", () => ({
  flushRejectionCounters: (...args: unknown[]) =>
    mockFlushRejectionCounters(...args),
}));

vi.mock("../src/retention", () => ({
  createManifestRetentionClassResolver: () =>
    mockCreateManifestRetentionClassResolver(),
  runRetentionPurge: (...args: unknown[]) => mockRunRetentionPurge(...args),
}));

vi.mock("../src/rollup", () => ({
  logReconciliationReport: (...args: unknown[]) =>
    mockLogReconciliationReport(...args),
  runRollupAndReconciliation: (...args: unknown[]) =>
    mockRunRollupAndReconciliation(...args),
}));

vi.mock("../src/quota-do/index", () => ({
  admissionRPC: (...args: unknown[]) => mockAdmissionRPC(...args),
  creditRPC: (...args: unknown[]) => mockCreditRPC(...args),
}));

type WorkerModule = typeof import("../src/worker");

let workerModule: WorkerModule;
let consoleErrorSpy: ReturnType<typeof vi.spyOn>;

function makeDoCtx() {
  const storage = {
    get: vi.fn(),
    put: vi.fn(),
  };
  return {
    storage,
    blockConcurrencyWhile: async <T>(fn: () => Promise<T>) => fn(),
  };
}

function gatewayStub() {
  const ctx = makeDoCtx();
  // DurableObject subclass constructed with (ctx, env) matching Workers runtime.
  const instance = new workerModule.GatewayObject(
    ctx as never,
    runtimeEnv as never,
  );
  return { instance, ctx };
}

async function rpc(
  instance: InstanceType<WorkerModule["GatewayObject"]>,
  init: RequestInit,
): Promise<Response> {
  return instance.fetch(new Request("https://quota-do.internal/rpc", init));
}

beforeEach(async () => {
  vi.resetModules();
  mockHandleAdapterRequest.mockReset();
  mockAuthenticateGetRequest.mockReset();
  mockGetRequest.mockReset();
  mockGetRequestAuthErrorBody.mockReset();
  mockFlushRejectionCounters.mockReset();
  mockReconcileGraceUsage.mockReset();
  mockRunRetentionPurge.mockReset();
  mockCreateManifestRetentionClassResolver.mockClear();
  mockRunRollupAndReconciliation.mockReset();
  mockLogReconciliationReport.mockReset();
  mockAdmissionRPC.mockReset();
  mockCreditRPC.mockReset();
  mockLiveHttpStatusForCode.mockClear();

  mockFlushRejectionCounters.mockResolvedValue(undefined);
  mockReconcileGraceUsage.mockResolvedValue(undefined);
  mockRunRetentionPurge.mockResolvedValue(undefined);
  mockRunRollupAndReconciliation.mockResolvedValue({ ok: true });
  mockHandleAdapterRequest.mockResolvedValue(
    new Response("event source required", { status: 503 }),
  );
  mockGetRequestAuthErrorBody.mockReturnValue({
    code: "unauthenticated",
    request_reference: "AAAA-AAAA",
    trace_id: "01TESTTRACEID0000000000000",
    retry_safe: true,
  });

  consoleErrorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
  workerModule = await import("../src/worker");
});

afterEach(() => {
  consoleErrorSpy.mockRestore();
});

describe("POST /v1/requests fail-fast without event source", () => {
  it("returns 503 when the adapter has no event source", async () => {
    const response = await workerModule.default.fetch(
      new Request("https://ai-gateway.test/v1/requests", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ installation: "inst-1", capability: "cap@v1" }),
      }),
    );

    expect(response.status).toBe(503);
    expect(mockHandleAdapterRequest).toHaveBeenCalledTimes(1);
    const adapterRequest = mockHandleAdapterRequest.mock.calls[0]?.[0] as Request;
    expect(adapterRequest.method).toBe("POST");
    expect(new URL(adapterRequest.url).pathname).toBe("/v1/requests");
    // Worker routes without injecting an eventSource — fail-fast path.
    expect(mockHandleAdapterRequest.mock.calls[0]?.length).toBe(1);
  });
});

describe("GET /v1/requests/:ref response shaping", () => {
  const REF = "ABCD-EFGH";

  async function getRef(headers?: HeadersInit): Promise<Response> {
    return workerModule.default.fetch(
      new Request(`https://ai-gateway.test/v1/requests/${REF}`, {
        method: "GET",
        headers,
      }),
    );
  }

  it("shapes Completed with result", async () => {
    mockAuthenticateGetRequest.mockResolvedValue({
      ok: true,
      principal: { installationId: "inst-1" },
    });
    mockGetRequest.mockResolvedValue({
      found: true,
      state: "Completed",
      result: { kind: "prose", text: "hello" },
    });

    const response = await getRef({ authorization: "Bearer tok" });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      state: "Completed",
      result: { kind: "prose", text: "hello" },
    });
  });

  it("shapes Completed without result when result is missing", async () => {
    mockAuthenticateGetRequest.mockResolvedValue({
      ok: true,
      principal: { installationId: "inst-1" },
    });
    mockGetRequest.mockResolvedValue({
      found: true,
      state: "Completed",
      resultMissing: true,
    });

    const response = await getRef({ authorization: "Bearer tok" });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ state: "Completed" });
  });

  it("shapes pending in-flight states", async () => {
    mockAuthenticateGetRequest.mockResolvedValue({
      ok: true,
      principal: { installationId: "inst-1" },
    });
    mockGetRequest.mockResolvedValue({
      found: true,
      state: "Invoking",
      pending: true,
    });

    const response = await getRef({ authorization: "Bearer tok" });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      state: "Invoking",
      pending: true,
    });
  });

  it("shapes Failed with terminal_error_code", async () => {
    mockAuthenticateGetRequest.mockResolvedValue({
      ok: true,
      principal: { installationId: "inst-1" },
    });
    mockGetRequest.mockResolvedValue({
      found: true,
      state: "Failed",
      terminalErrorCode: "provider_unavailable",
    });

    const response = await getRef({ authorization: "Bearer tok" });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      state: "Failed",
      terminal_error_code: "provider_unavailable",
    });
  });

  it("shapes AwaitingContext", async () => {
    mockAuthenticateGetRequest.mockResolvedValue({
      ok: true,
      principal: { installationId: "inst-1" },
    });
    mockGetRequest.mockResolvedValue({
      found: true,
      state: "AwaitingContext",
    });

    const response = await getRef({ authorization: "Bearer tok" });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ state: "AwaitingContext" });
  });

  it("shapes Cancelled", async () => {
    mockAuthenticateGetRequest.mockResolvedValue({
      ok: true,
      principal: { installationId: "inst-1" },
    });
    mockGetRequest.mockResolvedValue({
      found: true,
      state: "Cancelled",
    });

    const response = await getRef({ authorization: "Bearer tok" });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ state: "Cancelled" });
  });

  it("returns 404 when the reference is not found", async () => {
    mockAuthenticateGetRequest.mockResolvedValue({
      ok: true,
      principal: { installationId: "inst-1" },
    });
    mockGetRequest.mockResolvedValue({ found: false });

    const response = await getRef({ authorization: "Bearer tok" });
    expect(response.status).toBe(404);
    expect(await response.text()).toBe("");
  });

  it("returns 401 when authentication fails", async () => {
    mockAuthenticateGetRequest.mockResolvedValue({
      ok: false,
      code: "unauthenticated",
    });

    const response = await getRef();
    expect(response.status).toBe(401);
    expect(mockGetRequestAuthErrorBody).toHaveBeenCalledWith("unauthenticated");
    expect(mockGetRequest).not.toHaveBeenCalled();
  });
});

describe("scheduled() cron dispatch", () => {
  function callOrder(): string[] {
    const calls: string[] = [];
    mockFlushRejectionCounters.mockImplementation(async () => {
      calls.push("flush");
    });
    mockReconcileGraceUsage.mockImplementation(async () => {
      calls.push("reconcile");
    });
    mockRunRetentionPurge.mockImplementation(async () => {
      calls.push("retention");
    });
    mockRunRollupAndReconciliation.mockImplementation(async () => {
      calls.push("rollup");
      return { ok: true };
    });
    return calls;
  }

  it("runs flush then reconcile before retention on 0 3 * * *", async () => {
    const calls = callOrder();
    await workerModule.default.scheduled(
      { cron: "0 3 * * *", scheduledTime: Date.now(), noRetry() {} },
      runtimeEnv as never,
      {} as ExecutionContext,
    );

    expect(calls).toEqual(["flush", "reconcile", "retention"]);
    expect(mockRunRollupAndReconciliation).not.toHaveBeenCalled();
    expect(mockRunRetentionPurge).toHaveBeenCalledWith(
      expect.objectContaining({
        db: runtimeEnv.DB,
        r2: runtimeEnv.R2,
      }),
    );
  });

  it("runs flush then reconcile before rollup on 0 4 * * *", async () => {
    const calls = callOrder();
    await workerModule.default.scheduled(
      { cron: "0 4 * * *", scheduledTime: Date.now(), noRetry() {} },
      runtimeEnv as never,
      {} as ExecutionContext,
    );

    expect(calls).toEqual(["flush", "reconcile", "rollup"]);
    expect(mockRunRetentionPurge).not.toHaveBeenCalled();
    expect(mockLogReconciliationReport).toHaveBeenCalled();
  });

  it("always flushes and reconciles even for unrecognized crons", async () => {
    const calls = callOrder();
    await workerModule.default.scheduled(
      { cron: "0 5 * * *", scheduledTime: Date.now(), noRetry() {} },
      runtimeEnv as never,
      {} as ExecutionContext,
    );

    expect(calls).toEqual(["flush", "reconcile"]);
    expect(mockRunRetentionPurge).not.toHaveBeenCalled();
    expect(mockRunRollupAndReconciliation).not.toHaveBeenCalled();
  });
});

describe("GatewayObject.fetch negatives and §3.1.7", () => {
  const validAdmission = {
    kind: "admission",
    jti: "jti-1",
    installationId: "inst-1",
    idempotencyKey: "idem-1",
    requestReference: "ABCD-EFGH",
    entitlement: {
      plan: "standard",
      period_bounds: { period_start: "a", period_end: "b" },
      request_quota: 100,
      token_cost_budget: { token_budget: 1, cost_budget: 1 },
      allowed_capabilities: [],
      soft_threshold: 0,
      status: "active",
    },
  };

  it("returns 405 for non-POST", async () => {
    const { instance } = gatewayStub();
    const response = await rpc(instance, { method: "GET" });
    expect(response.status).toBe(405);
  });

  it("returns 400 invalid_json for malformed body", async () => {
    const { instance } = gatewayStub();
    const response = await rpc(instance, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "{not-json",
    });
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "invalid_json" });
  });

  it("returns 400 unknown_kind for unrecognized kind", async () => {
    const { instance } = gatewayStub();
    const response = await rpc(instance, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ kind: "not-a-real-kind" }),
    });
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "unknown_kind" });
  });

  it("returns 400 bad_request for known arg-validation failures", async () => {
    const { instance } = gatewayStub();
    const response = await rpc(instance, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ kind: "admission", jti: "only-jti" }),
    });
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "bad_request" });
    expect(mockAdmissionRPC).not.toHaveBeenCalled();
    expect(consoleErrorSpy).not.toHaveBeenCalled();
  });

  it("returns 400 for installation_id_mismatch from RPC", async () => {
    mockAdmissionRPC.mockRejectedValue(new Error("installation_id_mismatch"));
    const { instance } = gatewayStub();
    const response = await rpc(instance, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(validAdmission),
    });
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "bad_request" });
    expect(consoleErrorSpy).not.toHaveBeenCalled();
  });

  it("returns 500 and logs structured error for unexpected RPC failures", async () => {
    mockAdmissionRPC.mockRejectedValue(new Error("storage_put_failed"));
    const { instance } = gatewayStub();
    const response = await rpc(instance, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(validAdmission),
    });

    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({ error: "internal_error" });
    expect(consoleErrorSpy).toHaveBeenCalledTimes(1);
    const logged = JSON.parse(String(consoleErrorSpy.mock.calls[0]?.[0]));
    expect(logged).toMatchObject({
      level: "error",
      message: "gateway_object_rpc_failed",
      kind: "admission",
      error: "storage_put_failed",
      installation: "inst-1",
      request_reference: "ABCD-EFGH",
      jti: "jti-1",
    });
  });
});
