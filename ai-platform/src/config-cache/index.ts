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

function parseCanaryIds(raw: unknown): string[] {
  if (typeof raw !== "string" || raw.length === 0) {
    return [];
  }
  try {
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed) || !parsed.every((e) => typeof e === "string")) {
      return [];
    }
    return parsed as string[];
  } catch {
    return [];
  }
}

async function loadRoutingPolicyDocument(
  row: D1Row,
  r2: R2Bucket | undefined,
): Promise<D1Row | "miss"> {
  if (!r2) {
    return row;
  }
  const pointer = row.content_pointer;
  if (typeof pointer !== "string") {
    return "miss";
  }
  const object = await r2.get(pointer);
  if (!object) {
    return "miss";
  }
  const document = JSON.parse(await object.text()) as unknown;
  return { ...row, document };
}

/**
 * Production D1Reader for enrolled-key verification and related config loads.
 * Covers installations, keys, entitlements, grants, kill_switches,
 * active_routing_policy (with optional R2 document load), and token_contracts.
 * Reader keys are `${kind}:${key}` (see loadConfig).
 */
export function createD1ConfigReader(db: D1Database, r2?: R2Bucket): D1Reader {
  return {
    async read(prefixedKey: string): Promise<D1Row | "miss"> {
      const separator = prefixedKey.indexOf(":");
      if (separator === -1) {
        return "miss";
      }

      const kind = prefixedKey.slice(0, separator);
      const key = prefixedKey.slice(separator + 1);

      switch (kind) {
        case "installations": {
          const row = await db
            .prepare("SELECT * FROM installation WHERE installation_id = ?")
            .bind(key)
            .first<D1Row>();
          return row ?? "miss";
        }
        case "keys": {
          const row = await db
            .prepare("SELECT * FROM installation_key WHERE key_id = ?")
            .bind(key)
            .first<D1Row>();
          return row ?? "miss";
        }
        case "token_contracts": {
          const row = await db
            .prepare("SELECT * FROM token_contract WHERE ver = ?")
            .bind(key)
            .first<D1Row>();
          return row ?? "miss";
        }
        case "entitlements": {
          const row = await db
            .prepare("SELECT * FROM entitlement WHERE installation_id = ?")
            .bind(key)
            .first<D1Row>();
          return row ?? "miss";
        }
        case "kill_switches": {
          let scope: string;
          let target: string;
          if (key === "global") {
            scope = "global";
            target = "global";
          } else {
            const colon = key.indexOf(":");
            if (colon === -1) {
              return "miss";
            }
            scope = key.slice(0, colon);
            target = key.slice(colon + 1);
          }

          const row = await db
            .prepare(
              `SELECT scope, target, active, changed_at, changed_by
               FROM kill_switch
               WHERE scope = ? AND target = ?
               LIMIT 1`,
            )
            .bind(scope, target)
            .first<D1Row>();
          if (!row) {
            return "miss";
          }

          return {
            active: row.active === 1 || row.active === true,
            scope: row.scope,
            target: row.target,
            changed_at: row.changed_at,
            changed_by: row.changed_by,
          };
        }
        case "grants": {
          if (key.startsWith("global/")) {
            const parts = key.slice("global/".length).split("/");
            const capabilityId = parts[0];
            const version = parts[1];
            if (!capabilityId || !version) {
              return "miss";
            }
            const row = await db
              .prepare(
                `SELECT * FROM capability_grant
                 WHERE scope = 'global' AND capability_id = ? AND capability_version = ?
                 ORDER BY changed_at DESC LIMIT 1`,
              )
              .bind(capabilityId, version)
              .first<D1Row>();
            return row ?? "miss";
          }

          if (key.startsWith("plan:")) {
            const slash = key.lastIndexOf("/");
            if (slash === -1) {
              return "miss";
            }
            const scope = key.slice(0, slash);
            const capabilityId = key.slice(slash + 1);
            const row = await db
              .prepare(
                `SELECT * FROM capability_grant
                 WHERE scope = ? AND capability_id = ? AND revoked_at IS NULL
                 ORDER BY changed_at DESC LIMIT 1`,
              )
              .bind(scope, capabilityId)
              .first<D1Row>();
            return row ?? "miss";
          }

          const [installationId, capabilityId] = key.split("/", 2);
          if (!installationId || !capabilityId) {
            return "miss";
          }
          const row = await db
            .prepare(
              `SELECT * FROM capability_grant
               WHERE scope = ? AND capability_id = ? AND revoked_at IS NULL
               ORDER BY changed_at DESC LIMIT 1`,
            )
            .bind(`installation:${installationId}`, capabilityId)
            .first<D1Row>();
          return row ?? "miss";
        }
        case "active_routing_policy": {
          const withInstall = key.match(/^(.+@v\d+)\/(.+)$/);
          const policyRef = withInstall ? withInstall[1] : key;
          const installationId = withInstall ? withInstall[2] : undefined;
          const policyId = policyRef
            .replace(/^routing\//, "")
            .replace(/@v\d+$/, "");

          if (installationId) {
            const canaryRows = await db
              .prepare(
                `SELECT * FROM routing_policy
                 WHERE policy_id = ? AND status = 'canary'
                 ORDER BY active_from DESC, version DESC`,
              )
              .bind(policyId)
              .all<D1Row>();

            for (const row of canaryRows.results ?? []) {
              const ids = parseCanaryIds(row.canary_installation_ids);
              if (ids.includes(installationId)) {
                return loadRoutingPolicyDocument(row, r2);
              }
            }
          }

          const activeRow = await db
            .prepare(
              `SELECT * FROM routing_policy
               WHERE policy_id = ? AND status = 'active'
               ORDER BY active_from DESC, version DESC LIMIT 1`,
            )
            .bind(policyId)
            .first<D1Row>();

          if (!activeRow) {
            return "miss";
          }
          return loadRoutingPolicyDocument(activeRow, r2);
        }
        default:
          return "miss";
      }
    },
  };
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
