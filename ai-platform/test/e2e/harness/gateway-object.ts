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
 * Drain this installation's pending coverage outbox before its isolated
 * Durable Object storage frame is restored. A bounded loop handles an alarm
 * that ships work in batches. Once the outbox is empty, cancel and verify any
 * re-armed alarm while holding a DO turn; this also joins an alarm turn that
 * was already queued/running before isolated storage is restored.
 */
export async function drainGatewayObjectOutbox(
  installationId: string,
  maxAlarmRuns = 8,
): Promise<void> {
  const stub = env.DO.get(env.DO.idFromName(installationId));
  // getAlarm/deleteAlarm are asynchronous storage operations, so perform them
  // in a DO turn alongside the SQL inspection rather than racing an alarm
  // callback from outside the object.
  const inspectWithAlarm = async (): Promise<{
    outboxCount: number;
    alarm: number | null;
  }> =>
    runInDurableObject(stub, async (_instance, state) => {
      const storage = state.storage as DurableObjectStorage & {
        sql?: {
          exec: (query: string) => Iterable<{ count: number }>;
        };
      };
      if (!storage.sql) {
        throw new Error("quota DO sql storage unavailable while draining outbox");
      }
      const rows = [...storage.sql.exec("SELECT COUNT(*) AS count FROM outbox")];
      return {
        outboxCount: Number(rows[0]?.count ?? 0),
        alarm: await state.storage.getAlarm(),
      };
    });

  const cancelAndVerifyAlarm = async (): Promise<boolean> =>
    runInDurableObject(stub, async (_instance, state) => {
      if ((await state.storage.getAlarm()) !== null) {
        await state.storage.deleteAlarm();
      }
      return (await state.storage.getAlarm()) === null;
    });

  for (let run = 0; run < maxAlarmRuns; run += 1) {
    const state = await inspectWithAlarm();
    if (state.outboxCount === 0) {
      if (state.alarm === null) return;
      // A DO turn is a serialization barrier with any alarm callback already
      // in flight. Cancel its re-arm, then inspect again so a racing callback
      // cannot leave an alarm behind as the isolated frame is popped.
      if (!(await cancelAndVerifyAlarm())) {
        throw new Error(
          `quota DO alarm remained scheduled after cleanup for ${installationId}`,
        );
      }
      const afterCancel = await inspectWithAlarm();
      if (afterCancel.outboxCount === 0 && afterCancel.alarm === null) return;
      continue;
    }
    if (state.alarm === null) {
      throw new Error(
        `quota DO outbox remains pending without a scheduled alarm for ${installationId}`,
      );
    }

    const alarmRan = await runDurableObjectAlarm(stub);
    if (!alarmRan) {
      throw new Error(
        `quota DO outbox remains pending without a scheduled alarm for ${installationId}`,
      );
    }
  }

  const remaining = await inspectWithAlarm();
  if (remaining.outboxCount !== 0) {
    throw new Error(
      `quota DO outbox did not drain after ${maxAlarmRuns} alarm runs for ${installationId}`,
    );
  }
  if (remaining.alarm !== null && !(await cancelAndVerifyAlarm())) {
    throw new Error(
      `quota DO alarm remained scheduled after cleanup for ${installationId}`,
    );
  }
  const finalState = await inspectWithAlarm();
  if (finalState.outboxCount !== 0 || finalState.alarm !== null) {
    throw new Error(
      `quota DO cleanup did not reach an idle state for ${installationId}`,
    );
  }
}
