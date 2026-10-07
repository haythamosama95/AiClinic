export interface Env {
  PLATFORM: {
    registerIssuerKey(args: Record<string, unknown>): Promise<{
      contract_version: number;
      result: string;
      code: string;
      detail: string;
    }>;
  };
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "POST" && url.pathname === "/register-issuer-key") {
      const args = (await request.json()) as Record<string, unknown>;
      const envelope = await env.PLATFORM.registerIssuerKey(args);
      return Response.json(envelope);
    }

    return new Response("Not Found", { status: 404 });
  },
};
