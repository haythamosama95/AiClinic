import { authenticateBilling } from "./clinic-api/auth.js";
import {
  handleGetPayments,
  handleGetSubscription,
} from "./clinic-api/billing-reads.js";
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
import { handleOps as dispatchOps, runDueTransferSteps } from "./ops/index.js";
import { refreshCoverageView } from "./coverage/view.js";
import { markExportLagIfDue, sendDueAlerts } from "./alert/index.js";
import { checkR2BucketLock } from "./alert/lock.js";
import { clockNowIso } from "./clock.js";
import { runDailyDigest } from "./digest/run.js";
import { runHousekeeping } from "./housekeeping/run.js";
import { runHourlyWatch } from "./watch/hourly.js";
import {
  handleGetNotifyPaymob,
  handleGetReturnPaymob,
  handlePostNotifyPaymob,
} from "./notify/intake.js";
import { runReconciliation } from "./reconciliation/run.js";
import { exportFacts } from "./records/export.js";
import { refreshSigningKeyCheck } from "./work/grant.js";
import { runMinuteInquiryBudget } from "./work/inquiry-budget.js";
import {
  enqueueDailyReversalPopulation,
  enqueueHourlyReversalPopulation,
  enqueueSixHourReversalPopulation,
  scheduleCheckoutSweepRows,
} from "./work/sweep.js";

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
  ABO_GRANT_KEY: string;
  PLATFORM_PUBLIC_KEYS: string;
  ACCESS_TEAM_DOMAIN: string;
  ACCESS_AUD: string;
  PLATFORM: {
    getCoverage(args: Record<string, unknown>): Promise<Record<string, unknown>>;
    readCoverageEvents(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    grant(args: Record<string, unknown>): Promise<Record<string, unknown>>;
    beginTransfer(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    transferOut(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    transferIn(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    releaseHeld(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    voidGrant(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    listGrantsForVoid(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    suspend(args: Record<string, unknown>): Promise<Record<string, unknown>>;
    resume(args: Record<string, unknown>): Promise<Record<string, unknown>>;
    deleteInstallation(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    listServiceKeys(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    voidForReversal(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    inspectCoverage(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    listGrants(args: Record<string, unknown>): Promise<Record<string, unknown>>;
    listIssuerKeys(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    listOperatorCredentials(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    feedConsumerHealth(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    recordOperatorAction(
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

const SIGNING_KEY_GATE_ROW_ID = 1;

async function stampScheduledJobRun(env: Env, job: string): Promise<void> {
  try {
    const nowIso = await clockNowIso(env);
    await env.DB.prepare(
      `INSERT INTO scheduled_job_run (job, last_run_at) VALUES (?, ?)
       ON CONFLICT(job) DO UPDATE SET last_run_at = excluded.last_run_at`,
    )
      .bind(job, nowIso)
      .run();
  } catch {
    // Missing table is ignored.
  }
}

async function pingHeartbeat(env: Env): Promise<void> {
  try {
    await fetch(env.HEARTBEAT_URL);
  } catch {
    // Heartbeat failures must not block the cron.
  }
}

function emptyNotFound(): Response {
  return new Response(null, { status: 404 });
}

async function signingKeyGateMissing(env: Env): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT id FROM signing_key_gate WHERE id = ?`,
  )
    .bind(SIGNING_KEY_GATE_ROW_ID)
    .first<{ id: number }>();
  return row === null;
}

async function maybeRefreshSigningKeyCheck(env: Env): Promise<void> {
  if (!(await signingKeyGateMissing(env))) {
    return;
  }
  try {
    await refreshSigningKeyCheck(env);
  } catch {
    // Signing-key check failures must not block fetch or cron.
  }
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
  const versionGate = checkContractVersion(request, "aboClinic", env);
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

  if (request.method === "GET" && path === "/v1/subscription") {
    return handleGetSubscription(env, auth.claims.org, versionGate.version);
  }

  if (request.method === "GET" && path === "/v1/payments") {
    return handleGetPayments(request, env, auth.claims.org, versionGate.version);
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
    const response = await handlePostCheckout(
      request,
      env,
      auth.claims,
      versionGate.version,
    );
    if (response.status === 201) {
      try {
        const body = (await response.clone().json()) as { checkout_id?: string };
        if (typeof body.checkout_id === "string") {
          await scheduleCheckoutSweepRows(env, body.checkout_id);
        }
      } catch {
        // Sweep scheduling failures must not block checkout creation.
      }
    }
    return response;
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
  env: Env,
  path: string,
): Promise<Response> {
  const versionGate = checkContractVersion(request, "aboConsole", env);
  if (!versionGate.ok) {
    const body = (await versionGate.response.clone().json()) as Record<
      string,
      unknown
    >;
    body.reload = true;
    return new Response(JSON.stringify(body), {
      status: 400,
      headers: versionGate.response.headers,
    });
  }
  return dispatchOps(request, env, path, versionGate.version);
}

export default {
  async fetch(
    request: Request,
    env: Env,
    ctx: ExecutionContext,
  ): Promise<Response> {
    await maybeRefreshSigningKeyCheck(env);

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
    await stampScheduledJobRun(env, cron);
    if (cron === "0 */6 * * *") {
      try {
        await enqueueSixHourReversalPopulation(env);
      } catch {
        // Six-hour population failures must not block the cron.
      }
      return;
    }
    if (cron === "0 * * * *") {
      try {
        await refreshSigningKeyCheck(env);
      } catch {
        // Signing-key check failures must not block the hourly cron.
      }
      try {
        await enqueueHourlyReversalPopulation(env);
      } catch {
        // Hourly population failures must not block the hourly cron.
      }
      try {
        await runHourlyWatch(env);
      } catch {
        // Hourly watch failures must not block the hourly cron.
      }
      return;
    }
    await maybeRefreshSigningKeyCheck(env);
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
        await runMinuteInquiryBudget(env);
      } catch {
        // Inquiry budget failures must not block the minute cron.
      }
      try {
        await runDueTransferSteps(env);
      } catch {
        // Transfer saga failures must not block the minute cron.
      }
      await markExportLagIfDue(env);
      return;
    }
    if (cron === "0 6 * * *") {
      await checkR2BucketLock(env);
      try {
        await runReconciliation(env);
      } catch {
        // Reconciliation failures must not block the 06:00 cron.
      }
      try {
        await enqueueDailyReversalPopulation(env);
      } catch {
        // Daily population failures must not block the 06:00 cron.
      }
      try {
        await runDailyDigest(env);
      } catch {
        // Digest failures must not block the 06:00 cron.
      }
      await pingHeartbeat(env);
      try {
        await runHousekeeping(env);
      } catch {
        // Housekeeping failures must not block the 06:00 cron.
      }
      await sendDueAlerts(env);
    }
  },
};
