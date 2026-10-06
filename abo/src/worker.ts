import { authenticateBilling } from "./clinic-api/auth.js";
import {
  handleGetBillingContact,
  handlePutBillingContact,
} from "./clinic-api/billing-contact.js";
import { handleGetOffers } from "./clinic-api/offers.js";
import { checkTokenRate } from "./clinic-api/rate.js";
import { checkContractVersion } from "./clinic-api/version.js";

export interface Env {
  DB: D1Database;
  R2: R2Bucket;
  BILLING_HOST: string;
  OPS_HOST: string;
  ISSUER_ID: string;
  ISSUER_KEYS: string;
  TEST_CLOCK: string;
}

function emptyNotFound(): Response {
  return new Response(null, { status: 404 });
}

function isCrossHostRejection(host: string, path: string, env: Env): boolean {
  if (host === env.BILLING_HOST && path.startsWith("/ops/")) {
    return true;
  }
  if (host === env.OPS_HOST && path.startsWith("/v1/")) {
    return true;
  }
  return false;
}

function isKnownHost(host: string, env: Env): boolean {
  return host === env.BILLING_HOST || host === env.OPS_HOST;
}

function isAcceptedPath(host: string, path: string, env: Env): boolean {
  if (host === env.BILLING_HOST) {
    return (
      path.startsWith("/v1/") ||
      path.startsWith("/notify/") ||
      path.startsWith("/return/")
    );
  }
  if (host === env.OPS_HOST) {
    return path.startsWith("/ops/");
  }
  return false;
}

async function handleBillingV1(
  request: Request,
  env: Env,
  path: string,
): Promise<Response> {
  const versionGate = checkContractVersion(request, "aboClinic");
  if (!versionGate.ok) {
    return versionGate.response;
  }

  const auth = await authenticateBilling(request, env, versionGate.version);
  if (!auth.ok) {
    return auth.response;
  }

  const rate = await checkTokenRate(env.DB, auth.claims, versionGate.version);
  if (!rate.ok) {
    return rate.response;
  }

  if (request.method === "GET" && path === "/v1/offers") {
    return handleGetOffers(env, versionGate.version);
  }

  if (path === "/v1/billing-contact") {
    if (request.method === "GET") {
      return handleGetBillingContact(env, auth.claims.org, versionGate.version);
    }
    if (request.method === "PUT") {
      return handlePutBillingContact(
        request,
        env,
        auth.claims,
        versionGate.version,
      );
    }
  }

  return emptyNotFound();
}

async function handleOps(
  request: Request,
  _env: Env,
  _path: string,
): Promise<Response> {
  const versionGate = checkContractVersion(request, "aboConsole");
  if (!versionGate.ok) {
    return versionGate.response;
  }
  return emptyNotFound();
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const host = url.hostname;
    const path = url.pathname;

    if (!isKnownHost(host, env)) {
      return emptyNotFound();
    }

    if (isCrossHostRejection(host, path, env)) {
      return emptyNotFound();
    }

    if (!isAcceptedPath(host, path, env)) {
      return emptyNotFound();
    }

    if (host === env.BILLING_HOST && path.startsWith("/v1/")) {
      return handleBillingV1(request, env, path);
    }

    if (host === env.OPS_HOST && path.startsWith("/ops/")) {
      return handleOps(request, env, path);
    }

    return emptyNotFound();
  },
  async scheduled(): Promise<void> {},
};
