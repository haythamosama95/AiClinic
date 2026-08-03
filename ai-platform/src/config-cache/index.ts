/**
 * In-isolate config cache (§4.3.2, §4.4, §9.15).
 * Short-TTL map per entity kind; D1 on miss; owns nothing — returns copies.
 */

export type ConfigEntityKind =
  | "installations"
  | "keys"
  | "entitlements"
  | "grants"
  | "kill_switches"
  | "active_routing_policy"
  | "token_contracts";

type D1Row = Record<string, unknown>;

/** D1Reader port — single read(key) seam for spy-based tests (Clarification Q3). */
export interface D1Reader {
  read(key: string): Promise<D1Row | "miss">;
}

/** Plan-time short TTL (§4.3.2); not a configuration surface (R-20). */
export const CACHE_TTL_MS = 30_000;

type CacheEntry = {
  value: D1Row;
  expiresAt: number;
};

export class ConfigCacheMissError extends Error {
  override readonly name = "ConfigCacheMissError";

  constructor(
    readonly kind: ConfigEntityKind,
    readonly key: string,
  ) {
    super(`Config cache miss for ${kind}:${key}`);
  }
}

function cloneRow(row: D1Row): D1Row {
  return structuredClone(row);
}

export class ConfigCache {
  private readonly stores = new Map<ConfigEntityKind, Map<string, CacheEntry>>();
  /** In-flight cold loads keyed by `${kind}:${key}` — single-flight / stampede protection. */
  private readonly inflight = new Map<string, Promise<D1Row>>();

  private storeFor(kind: ConfigEntityKind): Map<string, CacheEntry> {
    let store = this.stores.get(kind);
    if (!store) {
      store = new Map();
      this.stores.set(kind, store);
    }
    return store;
  }

  consult(
    kind: ConfigEntityKind,
    key: string,
    now: number = Date.now(),
  ): D1Row | undefined {
    const entry = this.storeFor(kind).get(key);
    if (!entry) {
      return undefined;
    }
    if (now >= entry.expiresAt) {
      this.storeFor(kind).delete(key);
      return undefined;
    }
    return cloneRow(entry.value);
  }

  remember(
    kind: ConfigEntityKind,
    key: string,
    value: D1Row,
    now: number = Date.now(),
  ): void {
    this.storeFor(kind).set(key, {
      value: cloneRow(value),
      expiresAt: now + CACHE_TTL_MS,
    });
  }

  /** @internal single-flight seam used by `loadConfig`. */
  beginInflight(
    kind: ConfigEntityKind,
    key: string,
    loader: () => Promise<D1Row>,
  ): Promise<D1Row> {
    const flightKey = `${kind}:${key}`;
    const existing = this.inflight.get(flightKey);
    if (existing !== undefined) {
      return existing.then(cloneRow);
    }

    const promise = loader().finally(() => {
      this.inflight.delete(flightKey);
    });
    this.inflight.set(flightKey, promise);
    return promise.then(cloneRow);
  }
}

export async function loadConfig(
  cache: ConfigCache,
  reader: D1Reader,
  kind: ConfigEntityKind,
  key: string,
): Promise<D1Row> {
  const now = Date.now();
  const cached = cache.consult(kind, key, now);
  if (cached !== undefined) {
    return cached;
  }

  return cache.beginInflight(kind, key, async () => {
    // Reader keys are `${kind}:${key}` so one D1Reader serves every entity kind
    // without colliding on shared identifiers (installations vs entitlements).
    const row = await reader.read(`${kind}:${key}`);
    if (row === "miss") {
      throw new ConfigCacheMissError(kind, key);
    }

    cache.remember(kind, key, row, now);
    return cloneRow(row);
  });
}
