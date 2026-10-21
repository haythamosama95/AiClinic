import {
  canonicalize,
  CHANNEL_VERSIONS,
  grantIdComp,
  grantIdPaid,
  sha256Hex,
  ulid,
} from "vendor-contracts";
import {
  prepareRaiseAlert,
  type AlertEnv,
} from "../alert/index.js";
import { clockNowIso, clockNowMs, type ClockEnv } from "../clock.js";
import { insertFactLog } from "../records/append.js";
import type { JobOutcome } from "../scheduler/jobs.js";
import {
  parseStoredPaymobNotification,
  type ProviderRegistryEnv,
} from "../provider/registry.js";

const FIFTEEN_MINUTES_MS = 15 * 60 * 1000;
const ONE_DAY_MS = 24 * 60 * 60 * 1000;
const SEVEN_DAYS_MS = 7 * ONE_DAY_MS;

export type ReconciliationEnv = AlertEnv &
  ClockEnv &
  Pick<ProviderRegistryEnv, "PAYMOB_HMAC_SECRET"> & {
    DB: D1Database;
    R2: R2Bucket;
    PLATFORM: {
      listGrants(args: Record<string, unknown>): Promise<Record<string, unknown>>;
      getCoverage(
        args: Record<string, unknown>,
      ): Promise<Record<string, unknown>>;
      readCoverageEvents(
        args: Record<string, unknown>,
      ): Promise<Record<string, unknown>>;
    };
  };

type PlatformGrant = Record<string, unknown>;

async function newId(env: ReconciliationEnv): Promise<string> {
  const nowMs = await clockNowMs(env);
  const random = new Uint8Array(10);
  crypto.getRandomValues(random);
  return ulid(nowMs, random);
}

// R9-CRON1: a platform read that is refused or malformed is incomplete, not an empty result.
// Throwing it fails the reconciliation job, so the period stays pending and is retried.
class PlatformReadUnavailableError extends Error {
  constructor(source: string) {
    super(`platform_read_unavailable:${source}`);
    this.name = "PlatformReadUnavailable";
  }
}

// R9-AO4: a finding identity is (kind, subject). The first detection claims it, and the
// finding, its fact and its AL-10 alert are written in one D1 batch.
async function findingIdForIdentity(
  env: ReconciliationEnv,
  kind: string,
  subject: string,
): Promise<string | null> {
  const claimed = await env.DB.prepare(
    `SELECT finding_id FROM finding_identity WHERE kind = ? AND subject = ?`,
  )
    .bind(kind, subject)
    .first<{ finding_id: string }>();
  if (claimed !== null) {
    return claimed.finding_id;
  }
  // Rows restored by rebuild, or written before the registry, are claimed by the earliest
  // matching finding. Duplicates are retained and never deleted.
  const earliest = await env.DB.prepare(
    `SELECT finding_id FROM finding
     WHERE kind = ? AND subject = ?
     ORDER BY detected_at ASC, finding_id ASC
     LIMIT 1`,
  )
    .bind(kind, subject)
    .first<{ finding_id: string }>();
  if (earliest === null) {
    return null;
  }
  await env.DB.prepare(
    `INSERT OR IGNORE INTO finding_identity (kind, subject, finding_id)
     VALUES (?, ?, ?)`,
  )
    .bind(kind, subject, earliest.finding_id)
    .run();
  const winner = await env.DB.prepare(
    `SELECT finding_id FROM finding_identity WHERE kind = ? AND subject = ?`,
  )
    .bind(kind, subject)
    .first<{ finding_id: string }>();
  return winner?.finding_id ?? null;
}

// Ensures an unresolved finding has an AL-10 row. Existing delivery state is kept. A
// resolved finding is never reopened.
async function ensureFindingAlert(
  env: ReconciliationEnv,
  findingId: string,
): Promise<void> {
  const resolution = await env.DB.prepare(
    `SELECT 1 FROM finding_resolution WHERE finding_id = ?`,
  )
    .bind(findingId)
    .first();
  if (resolution !== null) {
    return;
  }
  await prepareRaiseAlert(env.DB, "AL-10", `AL-10:${findingId}`, findingId).run();
}

async function insertFinding(
  env: ReconciliationEnv,
  kind: string,
  subject: string,
  detail: string,
): Promise<void> {
  const existingId = await findingIdForIdentity(env, kind, subject);
  if (existingId !== null) {
    await ensureFindingAlert(env, existingId);
    return;
  }
  const findingId = await newId(env);
  const detectedAt = await clockNowIso(env);
  const canonicalRow = {
    finding_id: findingId,
    kind,
    subject,
    detail,
    detected_at: detectedAt,
  };
  try {
    await env.DB.batch([
      // The identity insert is first. A concurrent claim makes the whole batch roll back,
      // so no second finding, fact or alert is written.
      env.DB.prepare(
        `INSERT INTO finding_identity (kind, subject, finding_id) VALUES (?, ?, ?)`,
      ).bind(kind, subject, findingId),
      env.DB.prepare(
        `INSERT INTO finding (finding_id, kind, subject, detail, detected_at)
         VALUES (?, ?, ?, ?, ?)`,
      ).bind(findingId, kind, subject, detail, detectedAt),
      await insertFactLog(env, "finding", findingId, canonicalRow, detectedAt),
      prepareRaiseAlert(env.DB, "AL-10", `AL-10:${findingId}`, findingId),
    ]);
  } catch (error) {
    const winnerId = await findingIdForIdentity(env, kind, subject);
    if (winnerId === null) {
      throw error;
    }
    await ensureFindingAlert(env, winnerId);
  }
}

async function parsePlatformGrants(
  env: ReconciliationEnv,
): Promise<PlatformGrant[]> {
  const envelope = await env.PLATFORM.listGrants({
    contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
  });
  if (envelope.result !== "ok" || typeof envelope.detail !== "string") {
    throw new PlatformReadUnavailableError("listGrants");
  }
  const parsed = JSON.parse(envelope.detail) as unknown;
  if (!Array.isArray(parsed)) {
    throw new PlatformReadUnavailableError("listGrants");
  }
  return parsed as PlatformGrant[];
}

async function paidGrantIdsFromPayments(
  env: ReconciliationEnv,
): Promise<Set<string>> {
  const rows = await env.DB.prepare(`SELECT payment_id FROM payment`).all<{
    payment_id: string;
  }>();
  const grantIds = new Set<string>();
  for (const row of rows.results ?? []) {
    grantIds.add(await grantIdPaid(row.payment_id));
  }
  return grantIds;
}

async function complimentaryActionGrantIds(
  env: ReconciliationEnv,
): Promise<Set<string>> {
  const rows = await env.DB.prepare(
    `SELECT action_id FROM operator_action`,
  ).all<{ action_id: string }>();
  const grantIds = new Set<string>();
  for (const row of rows.results ?? []) {
    grantIds.add(await grantIdComp(row.action_id));
  }
  return grantIds;
}

async function checkPaymentWithoutGrant(env: ReconciliationEnv): Promise<void> {
  const nowMs = await clockNowMs(env);
  const rows = await env.DB.prepare(
    `SELECT payment_id, confirmed_at FROM payment WHERE disposition = 'grant'`,
  ).all<{ payment_id: string; confirmed_at: string }>();

  for (const row of rows.results ?? []) {
    const grantId = await grantIdPaid(row.payment_id);
    const outcome = await env.DB.prepare(
      `SELECT result, at FROM grant_outcome WHERE grant_id = ?`,
    )
      .bind(grantId)
      .first<{ result: string; at: string }>();

    if (
      outcome !== null &&
      (outcome.result === "applied" || outcome.result === "already_applied")
    ) {
      const confirmedMs = Date.parse(row.confirmed_at);
      const outcomeMs = Date.parse(outcome.at);
      if (
        !Number.isNaN(confirmedMs) &&
        !Number.isNaN(outcomeMs) &&
        outcomeMs <= confirmedMs + FIFTEEN_MINUTES_MS
      ) {
        continue;
      }
    }

    const confirmedMs = Date.parse(row.confirmed_at);
    if (
      outcome === null &&
      !Number.isNaN(confirmedMs) &&
      nowMs < confirmedMs + FIFTEEN_MINUTES_MS
    ) {
      continue;
    }

    await insertFinding(
      env,
      "payment_without_grant",
      row.payment_id,
      grantId,
    );
  }
}

async function checkGrantWithoutPayment(env: ReconciliationEnv): Promise<void> {
  const paidGrantIds = await paidGrantIdsFromPayments(env);
  const grants = await parsePlatformGrants(env);
  for (const grant of grants) {
    if (grant.source_kind !== "paid") {
      continue;
    }
    const grantId = String(grant.grant_id ?? "");
    if (grantId.length === 0 || paidGrantIds.has(grantId)) {
      continue;
    }
    await insertFinding(env, "grant_without_payment", grantId, "");
  }
}

async function checkGrantWithoutOperatorAction(
  env: ReconciliationEnv,
): Promise<void> {
  const authorisedGrantIds = await complimentaryActionGrantIds(env);
  const grants = await parsePlatformGrants(env);
  for (const grant of grants) {
    if (grant.source_kind !== "complimentary") {
      continue;
    }
    const grantId = String(grant.grant_id ?? "");
    if (grantId.length === 0 || authorisedGrantIds.has(grantId)) {
      continue;
    }
    await insertFinding(env, "grant_without_operator_action", grantId, "");
  }
}

async function checkTransferWithoutAuthorisation(
  env: ReconciliationEnv,
): Promise<void> {
  const grants = await parsePlatformGrants(env);
  for (const grant of grants) {
    if (grant.source_kind !== "transfer") {
      continue;
    }
    const grantId = String(grant.grant_id ?? "");
    const orgId = String(grant.org_id ?? "");
    if (grantId.length === 0) {
      continue;
    }

    const request = await env.DB.prepare(
      `SELECT 1 FROM grant_request
       WHERE grant_id = ? AND source_kind = 'transfer'`,
    )
      .bind(grantId)
      .first();
    if (request === null) {
      await insertFinding(
        env,
        "transfer_without_authorisation",
        grantId,
        orgId,
      );
      continue;
    }

    if (orgId.length === 0) {
      await insertFinding(
        env,
        "transfer_without_authorisation",
        grantId,
        "",
      );
      continue;
    }

    const action = await env.DB.prepare(
      `SELECT 1 FROM operator_action
       WHERE action = 'beginTransfer' AND subject = ?`,
    )
      .bind(orgId)
      .first();
    if (action === null) {
      await insertFinding(
        env,
        "transfer_without_authorisation",
        grantId,
        orgId,
      );
    }
  }
}

// R9-AO1: a stored void outcome is evidence only when it is an applied/already-applied
// receipt bound to this reversal. The receipt is written only after its signature verifies.
function outcomeReceiptBindsReversal(
  reversalId: string,
  result: string,
  receipt: string,
): boolean {
  if (result !== "applied" && result !== "already_applied") {
    return false;
  }
  const parsed = receiptObject(receipt);
  return parsed !== null && parsed.reversal_id === reversalId;
}

async function checkReversalNotApplied(env: ReconciliationEnv): Promise<void> {
  const rows = await env.DB.prepare(
    `SELECT reversal_id, effect FROM reversal WHERE is_full = 1`,
  ).all<{ reversal_id: string; effect: string }>();

  for (const row of rows.results ?? []) {
    // R9-AO1: only a genuine no-effect reversal is exempt. A requested tombstone is intent,
    // not proof of completion, so it needs the same verified outcome as every other effect.
    if (row.effect === "none") {
      continue;
    }
    const outcome = await env.DB.prepare(
      `SELECT result, receipt FROM reversal_outcome WHERE reversal_id = ?`,
    )
      .bind(row.reversal_id)
      .first<{ result: string; receipt: string }>();
    if (
      outcome !== null &&
      outcomeReceiptBindsReversal(row.reversal_id, outcome.result, outcome.receipt)
    ) {
      continue;
    }
    await insertFinding(
      env,
      "reversal_not_applied",
      row.reversal_id,
      row.effect,
    );
  }
}

async function checkPayoutUnmatched(env: ReconciliationEnv): Promise<void> {
  const rows = await env.DB.prepare(
    `SELECT import_id, line_no, kind, gross_minor, payment_id
     FROM payout_line WHERE kind = 'payment'`,
  ).all<{
    import_id: string;
    line_no: number;
    kind: string;
    gross_minor: number;
    payment_id: string | null;
  }>();

  for (const row of rows.results ?? []) {
    if (row.payment_id !== null) {
      const payment = await env.DB.prepare(
        `SELECT amount_minor FROM payment WHERE payment_id = ?`,
      )
        .bind(row.payment_id)
        .first<{ amount_minor: number }>();
      if (payment !== null && row.gross_minor === payment.amount_minor) {
        continue;
      }
    }
    await insertFinding(
      env,
      "payout_unmatched",
      `${row.import_id}:${row.line_no}`,
      row.payment_id ?? "",
    );
  }
}

function periodEndMs(period: string): number {
  const [yearStr, monthStr] = period.split("-");
  const year = Number(yearStr);
  const month = Number(monthStr);
  return Date.UTC(year, month, 0, 23, 59, 59, 999);
}

async function checkPaymentNotInPayout(env: ReconciliationEnv): Promise<void> {
  const imports = await env.DB.prepare(
    `SELECT period FROM payout_import`,
  ).all<{ period: string }>();
  const periods = new Set((imports.results ?? []).map((row) => row.period));
  if (periods.size === 0) {
    return;
  }

  const payoutPayments = new Set<string>();
  const paymentPayoutPeriods = new Map<string, Set<string>>();
  const payoutRows = await env.DB.prepare(
    `SELECT pl.payment_id, pi.period
     FROM payout_line pl
     INNER JOIN payout_import pi ON pi.import_id = pl.import_id
     WHERE pl.kind = 'payment' AND pl.payment_id IS NOT NULL`,
  ).all<{ payment_id: string; period: string }>();
  for (const row of payoutRows.results ?? []) {
    payoutPayments.add(`${row.period}:${row.payment_id}`);
    const periods = paymentPayoutPeriods.get(row.payment_id) ?? new Set<string>();
    periods.add(row.period);
    paymentPayoutPeriods.set(row.payment_id, periods);
  }

  const payments = await env.DB.prepare(
    `SELECT payment_id, paid_at FROM payment`,
  ).all<{ payment_id: string; paid_at: string }>();

  for (const payment of payments.results ?? []) {
    const paidMs = Date.parse(payment.paid_at);
    if (Number.isNaN(paidMs)) {
      continue;
    }
    for (const period of periods) {
      const endMs = periodEndMs(period);
      if (paidMs > endMs - SEVEN_DAYS_MS) {
        continue;
      }
      if (payoutPayments.has(`${period}:${payment.payment_id}`)) {
        continue;
      }
      const earlierPeriods = paymentPayoutPeriods.get(payment.payment_id);
      if (earlierPeriods !== undefined) {
        let appearedInEarlierPeriod = false;
        for (const earlierPeriod of earlierPeriods) {
          if (earlierPeriod < period) {
            appearedInEarlierPeriod = true;
            break;
          }
        }
        if (appearedInEarlierPeriod) {
          continue;
        }
      }
      await insertFinding(
        env,
        "payment_not_in_payout",
        payment.payment_id,
        period,
      );
    }
  }
}

type PayoutReversalEvidence = {
  import_id: string;
  line_no: number;
  kind: string;
  payment_id: string | null;
  reversal_ref: string | null;
  amount_minor: number | null;
};

async function payoutLineAlreadyLinked(
  env: ReconciliationEnv,
  importId: string,
  lineNo: number,
): Promise<boolean> {
  const link = await env.DB.prepare(
    `SELECT 1 FROM payout_reversal_link WHERE import_id = ? AND line_no = ?`,
  )
    .bind(importId, lineNo)
    .first();
  return link !== null;
}

// R9-AO2: exact match on normalized identity, payment, kind and amount. Only reversals recorded from
// the provider path carry an identity row, so manual reversals never match. Unrelated partial
// refunds carry a different identity and cannot satisfy a chargeback. Ambiguity matches nothing.
async function matchingProviderReversal(
  env: ReconciliationEnv,
  evidence: PayoutReversalEvidence,
): Promise<string | null> {
  if (
    evidence.payment_id === null ||
    evidence.reversal_ref === null ||
    evidence.amount_minor === null
  ) {
    return null;
  }
  const matches = await env.DB.prepare(
    `SELECT r.reversal_id
     FROM reversal_provider_identity rpi
     INNER JOIN reversal r ON r.reversal_id = rpi.reversal_id
     WHERE rpi.reversal_ref = ?
       AND r.payment_id = ?
       AND r.kind = ?
       AND r.amount_minor = ?
     ORDER BY r.reversal_id
     LIMIT 2`,
  )
    .bind(evidence.reversal_ref, evidence.payment_id, evidence.kind, evidence.amount_minor)
    .all<{ reversal_id: string }>();
  const found = matches.results ?? [];
  return found.length === 1 ? found[0]!.reversal_id : null;
}

// R9-AO2: the link is immutable and written once per payout line, however often reconciliation
// re-examines it. It records a match only; it never creates a reversal or a void.
async function linkPayoutReversal(
  env: ReconciliationEnv,
  importId: string,
  lineNo: number,
  reversalId: string,
): Promise<void> {
  const nowIso = await clockNowIso(env);
  try {
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO payout_reversal_link (import_id, line_no, reversal_id) VALUES (?, ?, ?)`,
      ).bind(importId, lineNo, reversalId),
      await insertFactLog(
        env,
        "payout_reversal_link",
        `${importId}:${lineNo}`,
        { import_id: importId, line_no: lineNo, reversal_id: reversalId },
        nowIso,
      ),
    ]);
  } catch (error) {
    // A concurrent run linked this line first; that link is the answer.
    if (!(await payoutLineAlreadyLinked(env, importId, lineNo))) {
      throw error;
    }
  }
}

async function checkUnrecordedReversal(env: ReconciliationEnv): Promise<void> {
  const rows = await env.DB.prepare(
    `SELECT pl.import_id, pl.line_no, pl.kind, pl.payment_id,
            plr.reversal_ref, plr.amount_minor
     FROM payout_line pl
     LEFT JOIN payout_line_reversal plr
       ON plr.import_id = pl.import_id AND plr.line_no = pl.line_no
     WHERE pl.kind IN ('refund', 'chargeback')`,
  ).all<PayoutReversalEvidence>();

  for (const row of rows.results ?? []) {
    if (await payoutLineAlreadyLinked(env, row.import_id, row.line_no)) {
      continue;
    }
    const reversalId = await matchingProviderReversal(env, row);
    if (reversalId !== null) {
      await linkPayoutReversal(env, row.import_id, row.line_no, reversalId);
      continue;
    }
    // Historical payout rows with no retained evidence have no identity and stay unmatched (D-5).
    await insertFinding(
      env,
      "unrecorded_reversal",
      `${row.import_id}:${row.line_no}`,
      row.payment_id ?? "",
    );
  }
}

async function checkCallbackWithoutConfirmation(
  env: ReconciliationEnv,
): Promise<void> {
  const rows = await env.DB.prepare(
    `SELECT notification_id, checkout_id, body_r2_key, hmac_valid
     FROM notification WHERE hmac_valid = 1`,
  ).all<{
    notification_id: string;
    checkout_id: string | null;
    body_r2_key: string;
    hmac_valid: number;
  }>();

  for (const row of rows.results ?? []) {
    const object = await env.R2.get(row.body_r2_key);
    if (object === undefined || object === null) {
      continue;
    }
    const body = await object.text();
    const parsed = body.startsWith("{")
      ? await parseStoredPaymobNotification(env as ProviderRegistryEnv, body)
      : { authentic: false, events: [] as [] };
    if (!parsed.authentic) {
      continue;
    }
    const succeeded = parsed.events.some(
      (event) => event.kind === "payment_succeeded",
    );
    if (!succeeded) {
      continue;
    }
    const checkoutId = row.checkout_id;
    if (checkoutId === null || checkoutId.length === 0) {
      await insertFinding(
        env,
        "callback_without_confirmation",
        row.notification_id,
        "",
      );
      continue;
    }
    const payment = await env.DB.prepare(
      `SELECT confirmation_inquiry_id FROM payment WHERE checkout_id = ?`,
    )
      .bind(checkoutId)
      .first<{ confirmation_inquiry_id: string }>();
    if (
      payment !== null &&
      payment.confirmation_inquiry_id.length > 0
    ) {
      continue;
    }
    await insertFinding(
      env,
      "callback_without_confirmation",
      row.notification_id,
      checkoutId,
    );
  }
}

// Returns each org with a recent valid feed event, keyed to the epoch/sequence evidence of its
// latest such event (R9-AO3 keeps this evidence when a local view is missing).
async function clinicsWithRecentCoverageEvents(
  env: ReconciliationEnv,
): Promise<Map<string, string>> {
  const nowMs = await clockNowMs(env);
  const cutoffMs = nowMs - ONE_DAY_MS;
  const orgIds = new Map<string, string>();
  let after = 0;
  let hasMore = true;

  while (hasMore) {
    const envelope = await env.PLATFORM.readCoverageEvents({
      contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
      after,
      limit: 200,
    });
    if (envelope.result !== "ok" || typeof envelope.detail !== "string") {
      throw new PlatformReadUnavailableError("readCoverageEvents");
    }
    const page = JSON.parse(envelope.detail) as {
      events?: Array<Record<string, unknown>>;
      next_after?: number;
      has_more?: boolean;
    };
    for (const event of page.events ?? []) {
      const at = event.at;
      const orgId = event.org_id;
      if (typeof at !== "string" || typeof orgId !== "string") {
        continue;
      }
      const eventMs = Date.parse(at);
      if (!Number.isNaN(eventMs) && eventMs >= cutoffMs && eventMs <= nowMs) {
        orgIds.set(
          orgId,
          JSON.stringify({
            binding_epoch: event.binding_epoch ?? null,
            clinic_seq: event.clinic_seq ?? null,
          }),
        );
      }
    }
    if (typeof page.next_after === "number") {
      after = page.next_after;
    }
    hasMore = page.has_more === true;
  }

  return orgIds;
}

function canonicalEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) {
    return false;
  }
  for (let index = 0; index < left.length; index += 1) {
    if (left[index] !== right[index]) {
      return false;
    }
  }
  return true;
}

function receiptObject(value: unknown): Record<string, unknown> | null {
  if (typeof value === "string") {
    try {
      const parsed = JSON.parse(value) as unknown;
      if (parsed !== null && typeof parsed === "object" && !Array.isArray(parsed)) {
        return parsed as Record<string, unknown>;
      }
      return null;
    } catch {
      return null;
    }
  }
  if (value !== null && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return null;
}

async function checkFeedDivergence(env: ReconciliationEnv): Promise<void> {
  const orgIds = await clinicsWithRecentCoverageEvents(env);
  for (const [orgId, eventEvidence] of orgIds) {
    const stored = await env.DB.prepare(
      `SELECT snapshot FROM coverage_view WHERE org_id = ?`,
    )
      .bind(orgId)
      .first<{ snapshot: string }>();
    if (stored === null) {
      // R9-AO3: an org established by a recent valid event must have its local view. A missing
      // copy is a divergence, not a valid no-coverage state. The live read is not copied here.
      await insertFinding(env, "feed_divergence", orgId, eventEvidence);
      continue;
    }

    const coverage = await env.PLATFORM.getCoverage({
      contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
      org_id: orgId,
    });
    // R9-AO4 F4: a definitive no-binding answer is a complete check with no
    // divergence to report. Any other non-ok result stays incomplete.
    if (
      coverage.result === "rejected" &&
      coverage.code === "coverage_not_found"
    ) {
      continue;
    }
    if (coverage.result !== "ok" || typeof coverage.detail !== "string") {
      throw new PlatformReadUnavailableError("getCoverage");
    }
    const detail = JSON.parse(coverage.detail) as {
      snapshot?: Record<string, unknown>;
    };
    const liveSnapshot = detail.snapshot ?? {};
    const storedSnapshot = JSON.parse(stored.snapshot) as Record<string, unknown>;
    if (
      canonicalEqual(
        canonicalize(storedSnapshot),
        canonicalize(liveSnapshot),
      )
    ) {
      continue;
    }
    await insertFinding(env, "feed_divergence", orgId, "");
  }
}

async function checkReceiptMismatch(env: ReconciliationEnv): Promise<void> {
  const grants = await parsePlatformGrants(env);
  const grantsById = new Map<string, PlatformGrant>();
  for (const grant of grants) {
    const grantId = String(grant.grant_id ?? "");
    if (grantId.length > 0) {
      grantsById.set(grantId, grant);
    }
  }

  // R9-AO3: LEFT JOIN so an applied outcome whose request copy is missing is examined. Only an
  // explicitly known transfer request is excluded; a missing request is never a transfer.
  const rows = await env.DB.prepare(
    `SELECT go.grant_id, go.result, go.receipt, gr.source_kind
     FROM grant_outcome go
     LEFT JOIN grant_request gr ON gr.grant_id = go.grant_id
     WHERE go.result IN ('applied', 'already_applied')
       AND (gr.source_kind IS NULL OR gr.source_kind != 'transfer')`,
  ).all<{
    grant_id: string;
    result: string;
    receipt: string;
    source_kind: string | null;
  }>();

  for (const row of rows.results ?? []) {
    if (row.source_kind === null) {
      await insertFinding(env, "receipt_mismatch", row.grant_id, "missing_grant_request");
      continue;
    }
    const platformGrant = grantsById.get(row.grant_id);
    if (platformGrant === undefined) {
      await insertFinding(env, "receipt_mismatch", row.grant_id, "");
      continue;
    }
    const aboReceipt = receiptObject(row.receipt);
    const platformReceipt = receiptObject(platformGrant.receipt);
    if (aboReceipt === null || platformReceipt === null) {
      await insertFinding(env, "receipt_mismatch", row.grant_id, "");
      continue;
    }
    if (
      !canonicalEqual(
        canonicalize(aboReceipt),
        canonicalize(platformReceipt),
      )
    ) {
      await insertFinding(env, "receipt_mismatch", row.grant_id, "");
    }
  }
}

// R9-CRON1: each check is isolated. One failing check does not stop the others, and any
// failure makes the job outcome failed so its period stays pending.
const RECONCILIATION_CHECKS: ReadonlyArray<
  readonly [string, (env: ReconciliationEnv) => Promise<void>]
> = [
  ["payment_without_grant", checkPaymentWithoutGrant],
  ["grant_without_payment", checkGrantWithoutPayment],
  ["grant_without_operator_action", checkGrantWithoutOperatorAction],
  ["transfer_without_authorisation", checkTransferWithoutAuthorisation],
  ["reversal_not_applied", checkReversalNotApplied],
  ["payout_unmatched", checkPayoutUnmatched],
  ["payment_not_in_payout", checkPaymentNotInPayout],
  ["unrecorded_reversal", checkUnrecordedReversal],
  ["callback_without_confirmation", checkCallbackWithoutConfirmation],
  ["feed_divergence", checkFeedDivergence],
  ["receipt_mismatch", checkReceiptMismatch],
];

// R9-AO4: an unresolved finding whose AL-10 row is missing gets one.
async function repairUnalertedFindings(env: ReconciliationEnv): Promise<void> {
  const rows = await env.DB.prepare(
    `SELECT f.finding_id
     FROM finding f
     LEFT JOIN finding_resolution fr ON fr.finding_id = f.finding_id
     LEFT JOIN alert a ON a.alert_key = 'AL-10:' || f.finding_id
     WHERE fr.finding_id IS NULL AND a.alert_key IS NULL
     ORDER BY f.finding_id`,
  ).all<{ finding_id: string }>();
  for (const row of rows.results ?? []) {
    await ensureFindingAlert(env, row.finding_id);
  }
}

export async function runReconciliation(
  env: ReconciliationEnv,
): Promise<JobOutcome> {
  let outcome: JobOutcome = "succeeded";
  for (const [name, check] of RECONCILIATION_CHECKS) {
    try {
      await check(env);
    } catch (error) {
      outcome = "failed";
      console.error(
        JSON.stringify({
          event: "reconciliation_check_failed",
          check: name,
          code: error instanceof Error ? error.name : "non_error_throw",
        }),
      );
    }
  }
  try {
    await repairUnalertedFindings(env);
  } catch {
    outcome = "failed";
  }
  return outcome;
}
