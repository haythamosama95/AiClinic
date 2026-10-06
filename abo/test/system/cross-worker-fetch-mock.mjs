import { MockAgent, setGlobalDispatcher } from "undici";

export const ACCESS_CERTS_JSON = JSON.stringify({
  keys: [
    {
      kid: "hxw-access-test",
      kty: "RSA",
      alg: "RS256",
      n:
        "xMIKMmlJKgCRxRFWgQP8LHgKowKzsqtskoLWlxdqvkTv1Vb5j_6v2BhjHHPiv1awOMyUuOPKEpgvw3FgFwxeRXuDF0KJiMLArnF5IOBPx-srym9drWlPbZjntkN6bl-ZxEosMvzyt5V2ZuFipgQuOIQya9EWe_APEXby2BcAOB8_g1iB0yEl1GPK2a3Kt-5NjqTrePI-P6seXvt3qFfN9qIByiH0A0_5clAjRBup_8zBLTT2oPMA25WrnVdUsH3WzMO2qBzs3C9xewH90DuvlQzFCxWPs5HkgyP4miA2daEwiXMQsK97UMx3PANyUXt3tBtLU9otWbmWZJY6_Ql46w",
      e: "AQAB",
    },
  ],
});

/** Outbound fetch handler for the auxiliary platform worker (Access JWKS). */
export async function hxwPlatformOutboundFetch(request) {
  const url = new URL(request.url);
  if (
    url.origin === "https://access.test" &&
    url.pathname === "/cdn-cgi/access/certs"
  ) {
    return new Response(ACCESS_CERTS_JSON, {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  }
  return new Response(`unexpected outbound fetch: ${url}`, { status: 502 });
}

export function installCrossWorkerFetchMock() {
  const agent = new MockAgent();
  agent.disableNetConnect();
  agent
    .get("https://access.test")
    .intercept({ path: "/cdn-cgi/access/certs", method: "GET" })
    .reply(200, ACCESS_CERTS_JSON)
    .persist();
  setGlobalDispatcher(agent);
  return agent;
}
