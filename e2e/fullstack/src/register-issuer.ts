const VENDOR_CALL_METHODS = new Set([
  "grant",
  "suspend",
  "resume",
  "armKillSwitch",
  "setCeilingPolicy",
  "beginTransfer",
  "releaseHeld",
  "voidGrant",
]);

type VendorCallArgs = Record<string, unknown>;

export interface Env {
  PLATFORM: {
    registerIssuerKey(args: VendorCallArgs): Promise<{
      contract_version: number;
      result: string;
      code: string;
      detail: string;
    }>;
    grant(args: VendorCallArgs): Promise<unknown>;
    suspend(args: VendorCallArgs): Promise<unknown>;
    resume(args: VendorCallArgs): Promise<unknown>;
    armKillSwitch(args: VendorCallArgs): Promise<unknown>;
    setCeilingPolicy(args: VendorCallArgs): Promise<unknown>;
    beginTransfer(args: VendorCallArgs): Promise<unknown>;
    releaseHeld(args: VendorCallArgs): Promise<unknown>;
    voidGrant(args: VendorCallArgs): Promise<unknown>;
  };
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "POST" && url.pathname === "/register-issuer-key") {
      const args = (await request.json()) as VendorCallArgs;
      const envelope = await env.PLATFORM.registerIssuerKey(args);
      return Response.json(envelope);
    }

    if (request.method === "POST" && url.pathname === "/vendor-call") {
      const body = (await request.json()) as {
        method?: string;
        args?: VendorCallArgs;
      };
      const method = body.method;
      if (!method || !VENDOR_CALL_METHODS.has(method)) {
        return new Response("Not Found", { status: 404 });
      }
      const args = body.args ?? {};
      const platform = env.PLATFORM;
      const result = await platform[method as keyof typeof platform](args);
      return Response.json(result);
    }

    return new Response("Not Found", { status: 404 });
  },
};
