import { authenticateBilling } from "./clinic-api/auth.js";
import {
  handleGetBillingContact,
  handlePutBillingContact,
} from "./clinic-api/billing-contact.js";
import {
  handleGetCheckout,
  handleListOpenCheckouts,
  handlePostCheckout,
} from "./clinic-api/checkouts.js";
import { handleGetOffers } from "./clinic-api/offers.js";
import { checkTokenRate } from "./clinic-api/rate.js";
import { checkContractVersion } from "./clinic-api/version.js";
import { refreshCoverageView } from "./coverage/view.js";
import { markExportLagIfDue, sendDueAlerts } from "./alert/index.js";
import { checkR2BucketLock } from "./alert/lock.js";
import {
  handleGetNotifyPaymob,
  handleGetReturnPaymob,
  handlePostNotifyPaymob,
} from "./notify/intake.js";
import { exportFacts } from "./records/export.js";
import { runDueConfirmWork } from "./work/runner.js";

export interface Env {
  DB: D1Database;
  R2: R2Bucket;
  BILLING_HOST: string;
  OPS_HOST: string;
  HEARTBEAT_URL: string;
  ALERT_EMAIL_TO: string;
  ISSUER_ID: string;
  ISSUER_KEYS: string;
  CLOUDFLARE_ACCOUNT_ID: string;
  R2_BUCKET_NAME: string;
  R2_LOCK_READ_TOKEN: string;
  TEST_CLOCK: string;
  PAYMOB_BASE_URL: string;
  PAYMOB_SECRET_KEY: string;
  PAYMOB_PUBLIC_KEY: string;
  PAYMOB_CARD_INTEGRATION_ID: string;
  PAYMOB_HMAC_SECRET: string;
  PAYMOB_API_KEY: string;
  PAYMOB_STUB?: Fetcher;
  PLATFORM: {
    getCoverage(args: Record<string, unknown>): Promise<Record<string, unknown>>;
    readCoverageEvents(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
  };
  SEND_EMAIL: {
    send(message: {
      from: string;
      to: string;
      subject: string;
      text: string;
    }): Promise<void>;
  };
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

  if (request.method === "POST" && path === "/v1/checkouts") {
    return handlePostCheckout(request, env, auth.claims, versionGate.version);
  }

  if (request.method === "GET" && path === "/v1/checkouts") {
    const url = new URL(request.url);
    if (url.searchParams.get("open") === "1") {
      return handleListOpenCheckouts(env, auth.claims.org, versionGate.version);
    }
    return emptyNotFound();
  }

  const checkoutIdMatch = /^\/v1\/checkouts\/([^/]+)$/u.exec(path);
  if (request.method === "GET" && checkoutIdMatch !== null) {
    return handleGetCheckout(
      env,
      auth.claims.org,
      checkoutIdMatch[1]!,
      versionGate.version,
    );
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
  async fetch(
    request: Request,
    env: Env,
    ctx: ExecutionContext,
  ): Promise<Response> {
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

    if (host === env.BILLING_HOST) {
      if (request.method === "POST" && path === "/notify/paymob") {
        return handlePostNotifyPaymob(request, env, ctx);
      }
      if (request.method === "GET" && path === "/notify/paymob") {
        return handleGetNotifyPaymob(request, env);
      }
      if (request.method === "GET" && path.startsWith("/return/paymob")) {
        return handleGetReturnPaymob(request, env);
      }
    }

    if (host === env.BILLING_HOST && path.startsWith("/v1/")) {
      return handleBillingV1(request, env, path);
    }

    if (host === env.OPS_HOST && path.startsWith("/ops/")) {
      return handleOps(request, env, path);
    }

    return emptyNotFound();
  },
  async scheduled(
    controller: ScheduledController,
    env: Env,
  ): Promise<void> {
    const cron = controller.cron;
    if (cron === "0 * * * *" || cron === "0 */6 * * *") {
      return;
    }
    if (cron === "* * * * *") {
      await markExportLagIfDue(env);
      try {
        await exportFacts(env);
      } catch {
        // Export races must not block the minute cron.
      }
      await sendDueAlerts(env);
      try {
        await refreshCoverageView(env);
      } catch {
        // Platform feed failures must not block the minute cron.
      }
      try {
        await runDueConfirmWork(env);
      } catch {
        // Confirm failures must not block the minute cron.
      }
      await markExportLagIfDue(env);
      return;
    }
    if (cron === "0 6 * * *") {
      await checkR2BucketLock(env);
      await sendDueAlerts(env);
    }
  },
};
