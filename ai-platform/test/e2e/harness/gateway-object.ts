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
  const payload =
    options.now !== undefined ? { ...body, now: options.now } : body;
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
