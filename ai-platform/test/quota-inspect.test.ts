import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { CHANNEL_VERSIONS } from "vendor-contracts";
import {
  inspectRPC,
  type QuotaDoState,
} from "../src/quota-do/index";

const EPHEMERAL_HORIZON_MS = 7_200_000;

function buildQuotaDoState(overrides: Partial<QuotaDoState> = {}): QuotaDoState {
  return {
    periodCounters: {
      requestsUsed: 0,
      tokensUsed: 0,
      costUsed: 0,
      inFlight: 0,
    },
    jtiReplay: {},
    idempotency: {},
    creditedRequests: {},
    admittedRequests: {},
    ...overrides,
  };
}

const STATE_KEY = "state";

function createMemoryStorage(initial: QuotaDoState): DurableObjectStorage {
  let state = structuredClone(initial);
  return {
    async get<T>(key: string): Promise<T | undefined> {
      if (key !== STATE_KEY) {
        return undefined;
      }
      return state as unknown as T;
    },
    async put(key: string, value: unknown): Promise<void> {
      if (key === STATE_KEY) {
        state = value as QuotaDoState;
      }
    },
    async delete(_key: string): Promise<boolean> {
      return true;
    },
    async deleteAll(): Promise<void> {},
    async list(): Promise<Map<string, unknown>> {
      return new Map();
    },
    async getAlarm(): Promise<number | null> {
      return null;
    },
    async setAlarm(): Promise<void> {},
    async deleteAlarm(): Promise<void> {},
    async sync(): Promise<void> {},
    transaction(_closure: unknown): Promise<unknown> {
      throw new Error("not implemented");
    },
  } as DurableObjectStorage;
}

describe("quota_inspect_do_rpc_contract", () => {
  it("returns inspect kind and in-memory state without persisting sweeps", async () => {
    const baseTime = Date.now();
    const idempotency = {
      "idem-1": {
        expiresAt: baseTime + EPHEMERAL_HORIZON_MS + 10_000,
        requestReference: "REF-001",
        state: "completed" as const,
        requestId: "req-1",
      },
    };
    const storage = createMemoryStorage(
      buildQuotaDoState({
        periodCounters: {
          requestsUsed: 2,
          tokensUsed: 60,
          costUsed: 0.01,
          inFlight: 0,
        },
        idempotency,
        jtiReplay: {
          "jti-1": { expiresAt: baseTime + EPHEMERAL_HORIZON_MS + 10_000 },
        },
        creditedRequests: {
          "req-1": { expiresAt: baseTime + EPHEMERAL_HORIZON_MS + 10_000 },
        },
      }),
    );

    const snapshot = await inspectRPC(storage, baseTime);
    expect(snapshot.kind).toBe("inspect");
    expect(snapshot.state.periodCounters.requestsUsed).toBe(2);
    expect(Object.keys(snapshot.state.idempotency)).toContain("idem-1");
  });

  it("uses the platform DO contract version in worker RPC payloads", () => {
    expect(CHANNEL_VERSIONS.platformDo).toBeGreaterThan(0);
  });
});

describe("quota_inspect_empty_do_state", () => {
  beforeEach(() => {
    void env.DB;
  });

  it("returns zeroed counters for an empty DO state", async () => {
    const storage = createMemoryStorage(buildQuotaDoState());
    const body = await inspectRPC(storage);
    expect(body.state.periodCounters).toEqual({
      requestsUsed: 0,
      tokensUsed: 0,
      costUsed: 0,
      inFlight: 0,
    });
    expect(body.state.idempotency).toEqual({});
  });
});
