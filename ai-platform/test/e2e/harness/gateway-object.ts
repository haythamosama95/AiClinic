import { CHANNEL_VERSIONS } from "vendor-contracts";
import { runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { env, QUOTA_DO_RPC_URL } from "./env";

export type GatewayObjectRpcOptions = {
  /** Injectable clock (`now` on the RPC JSON body). */
  now?: number;
  method?: string;
  namespace?: DurableObjectNamespace;
  /** Raw body; when set, `kind`/`args` are ignored. */
  rawBody?: string;
  headers?: Record<string, string>;
};

/**
 * Direct GatewayObject RPC: `idFromName(installationId)` → `stub.fetch`.
 * Production worker uses `https://quota-do.internal/rpc` (no public HTTP route).
 */
export async function gatewayObjectRpc(
  installationId: string,
  body: Record<string, unknown>,
  options: GatewayObjectRpcOptions = {},
): Promise<Response> {
  const namespace = options.namespace ?? env.DO;
  const id = namespace.idFromName(installationId);
  const stub = namespace.get(id);
  const payload = {
    ...body,
    contract_version:
      body.contract_version ?? CHANNEL_VERSIONS.platformDo,
    ...(options.now !== undefined ? { now: options.now } : {}),
  };
  return stub.fetch(QUOTA_DO_RPC_URL, {
    method: options.method ?? "POST",
    headers: {
      "content-type": "application/json",
      ...options.headers,
    },
    body: options.rawBody ?? JSON.stringify(payload),
  });
}

export async function gatewayObjectJson(
  installationId: string,
  body: Record<string, unknown>,
  options: GatewayObjectRpcOptions = {},
): Promise<{ status: number; json: unknown; text: string }> {
  const response = await gatewayObjectRpc(installationId, body, options);
  const text = await response.text();
  let json: unknown = null;
  if (text.length > 0) {
    try {
      json = JSON.parse(text) as unknown;
    } catch {
      json = null;
    }
  }
  return { status: response.status, json, text };
}

/**
 * Drain only this installation's pending coverage outbox before its isolated
 * Durable Object storage frame is restored. A bounded loop handles an alarm
 * that ships work in batches, while leaving unrelated/future alarms alone.
 */
export async function drainGatewayObjectOutbox(
  installationId: string,
  maxAlarmRuns = 8,
): Promise<void> {
  const stub = env.DO.get(env.DO.idFromName(installationId));
  const pendingOutboxCount = async (): Promise<number> =>
    runInDurableObject(stub, (_instance, state) => {
      const storage = state.storage as DurableObjectStorage & {
        sql?: {
          exec: (query: string) => Iterable<{ count: number }>;
        };
      };
      if (!storage.sql) {
        throw new Error("quota DO sql storage unavailable while draining outbox");
      }
      const rows = [...storage.sql.exec("SELECT COUNT(*) AS count FROM outbox")];
      return Number(rows[0]?.count ?? 0);
    });

  for (let run = 0; run < maxAlarmRuns; run += 1) {
    if ((await pendingOutboxCount()) === 0) return;
    const alarmRan = await runDurableObjectAlarm(stub);
    if (!alarmRan) {
      throw new Error(
        `quota DO outbox remains pending without a scheduled alarm for ${installationId}`,
      );
    }
  }

  if ((await pendingOutboxCount()) !== 0) {
    throw new Error(
      `quota DO outbox did not drain after ${maxAlarmRuns} alarm runs for ${installationId}`,
    );
  }
}
