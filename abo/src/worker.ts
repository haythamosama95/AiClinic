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
import {
  checkContractVersion,
  clinicErrorResponse,
} from "./clinic-api/version.js";
import { handleOps as dispatchOps, runDueTransferSteps, verifyOpsAccess } from "./ops/index.js";
import { handleOpsShell } from "./ops/browser/shell.js";
import { refreshCoverageView } from "./coverage/view.js";
import { markExportLagIfDue, sendDueAlerts } from "./alert/index.js";
import { checkR2BucketLock } from "./alert/lock.js";
import { isAboRecoveryActive } from "./recovery-fence.js";
import { runDailyDigest } from "./digest/run.js";
import { runHousekeeping } from "./housekeeping/run.js";
import {
  boundedErrorCode,
  recordUngatedOutcome,
  runDueScheduledJobs,
  type Cadence,
  type ClaimOptions,
  type ScheduledJobDefinition,
} from "./scheduler/jobs.js";
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
  // R9-CRON1 / RT2: per-stream heartbeat URLs. HEARTBEAT_URL remains the fallback for a stream
  // whose own URL is unset, so existing deployments keep working.
  HEARTBEAT_URL: string;
  HEARTBEAT_URL_MINUTE?: string;
  HEARTBEAT_URL_DIGEST?: string;
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
  PAYMOB_ALLOW_LOCAL_HTTP?: string;
  PAYMOB_STUB?: Fetcher;
  ABO_GRANT_KEY: string;
  PLATFORM_PUBLIC_KEYS: string;
  ACCESS_TEAM_DOMAIN: string;
  ACCESS_AUD: string;
  PLATFORM: {
    countLedgerRows(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
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
    recoverStrandedTerm(
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
    readLaunchState(
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
    armKillSwitch(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    disarmKillSwitch(
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

const MINUTE_PROCESSING_JOB = "minute_processing";

// R9-CRON1: due daily, hourly and six-hourly jobs. Each cron runs its own cadence. The minute
// cron retries only attempts that failed, were deferred, or were abandoned. It never starts a
// never-attempted period. The digest success heartbeat is pinged only after the digest is
// acknowledged as sent.
const SCHEDULED_JOBS: ReadonlyArray<ScheduledJobDefinition<Env>> = [
  {
    job: "reversal_population_six_hour",
    cadence: "six_hour",
    run: async (env) => {
      await enqueueSixHourReversalPopulation(env);
      return "succeeded";
    },
  },
  {
    job: "reversal_population_hourly",
    cadence: "hourly",
    run: async (env) => {
      await enqueueHourlyReversalPopulation(env);
      return "succeeded";
    },
  },
  {
    job: "hourly_watch",
    cadence: "hourly",
    run: (env) => runHourlyWatch(env),
  },
  {
    job: "r2_lock_check",
    cadence: "daily",
    run: (env) => checkR2BucketLock(env),
  },
  {
    job: "reconciliation",
    cadence: "daily",
    run: (env) => runReconciliation(env),
  },
  {
    job: "reversal_population_daily",
    cadence: "daily",
    run: async (env) => {
      await enqueueDailyReversalPopulation(env);
      return "succeeded";
    },
  },
  {
    job: "digest",
    cadence: "daily",
    run: (env) => runDailyDigest(env),
    onSucceeded: (env) => pingHeartbeat(env, "digest"),
  },
  {
    job: "housekeeping",
    cadence: "daily",
    run: (env) => runHousekeeping(env),
  },
];

async function runCronJobs(
  env: Env,
  cadences: ReadonlyArray<Cadence>,
  options?: ClaimOptions,
): Promise<void> {
  await runDueScheduledJobs(
    env,
    SCHEDULED_JOBS.filter((definition) => cadences.includes(definition.cadence)),
    options,
  );
}

// R9-CRON1: each minute step is isolated. A failing step is recorded and the remaining steps
// still run. The minute row records the last success and the last failure.
async function runMinuteProcessing(env: Env): Promise<void> {
  const steps: ReadonlyArray<readonly [string, () => Promise<unknown>]> = [
    ["export_lag", () => markExportLagIfDue(env)],
    ["fact_export", () => exportFacts(env)],
    ["alert_dispatch", () => sendDueAlerts(env)],
    ["coverage_view", () => refreshCoverageView(env)],
    ["inquiry_budget", () => runMinuteInquiryBudget(env)],
    ["transfer_steps", () => runDueTransferSteps(env)],
    ["export_lag", () => markExportLagIfDue(env)],
  ];
  let failed = false;
  for (const [name, step] of steps) {
    try {
      await step();
    } catch (error) {
      failed = true;
      console.error(
        JSON.stringify({
          event: "minute_step_failed",
          step: name,
          code: boundedErrorCode(error),
        }),
      );
    }
  }
  try {
    await recordUngatedOutcome(
      env,
      MINUTE_PROCESSING_JOB,
      failed ? "failed" : "succeeded",
      "minute_step_failed",
    );
  } catch {
    // Recording must not block the minute heartbeat.
  }
}

// R9-CRON1 / RT2: each stream pings its own configured URL. A stream whose URL is unset uses
// HEARTBEAT_URL, so one stream's observation never stands in for another's configured URL
// when both are set.
function heartbeatUrlFor(env: Env, stream: "minute" | "digest"): string {
  const own =
    stream === "minute" ? env.HEARTBEAT_URL_MINUTE : env.HEARTBEAT_URL_DIGEST;
  return typeof own === "string" && own.length > 0 ? own : env.HEARTBEAT_URL;
}

async function pingHeartbeat(
  env: Env,
  stream: "minute" | "digest",
): Promise<void> {
  try {
    await fetch(heartbeatUrlFor(env, stream));
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
    return clinicErrorResponse("not_found", 404, versionGate.version);
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
    if (await isAboRecoveryActive(env)) {
      return new Response("abo_recovery_in_progress", { status: 503 });
    }
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

    // R2-P4 / 01 §3.8 D-2: exactly `GET /ops` (no trailing slash) serves the
    // source-bundled console HTML shell after host validation. Access JWT
    // verification happens inside the handler; the contract-version gate does
    // not run for this one path because a browser navigation cannot send the
    // version header. Every other `/ops/*` path keeps the version and auth
    // rules handled by `dispatchOps`.
    if (host === env.OPS_HOST && request.method === "GET" && path === "/ops") {
      return handleOpsShell(request, env);
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
    if (await isAboRecoveryActive(env)) return;
    const cron = controller.cron;
    if (cron === "0 */6 * * *") {
      await runCronJobs(env, ["six_hour"]);
      return;
    }
    if (cron === "0 * * * *") {
      try {
        await refreshSigningKeyCheck(env);
      } catch {
        // Signing-key check failures must not block the hourly cron.
      }
      await runCronJobs(env, ["hourly"]);
      return;
    }
    await maybeRefreshSigningKeyCheck(env);
    if (cron === "* * * * *") {
      await runMinuteProcessing(env);
      // Minute cron retries only attempts that did not succeed (retryOnly). A never-attempted
      // period is left to its own scheduled tick, but FV-P3 flags it as scheduled_period_missed
      // after a 5-minute grace window without starting it. The period lease keeps each period to
      // one completion.
      await runCronJobs(env, ["six_hour", "hourly", "daily"], { retryOnly: true });
      // F7(ii): the minute stream pings unconditionally, after the minute work. It is a cron
      // liveness signal only. The digest success stream is pinged separately from the digest.
      await pingHeartbeat(env, "minute");
      return;
    }
    if (cron === "0 6 * * *") {
      await runCronJobs(env, ["daily"]);
      try {
        await sendDueAlerts(env);
      } catch {
        // Alert dispatch failures are retried by the next minute cron.
      }
    }
  },
};
