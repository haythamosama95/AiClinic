import {
  CHANNEL_VERSIONS,
  validateCoverageSnapshot,
  validateFeedEvent,
} from "vendor-contracts";

export type CoverageViewEnv = {
  DB: D1Database;
  PLATFORM: {
    readCoverageEvents(
      args: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
  };
};

type CoveragePair = {
  binding_epoch: number;
  clinic_seq: number;
};

type FeedPage = {
  after: number;
  events: Record<string, unknown>[];
  next_after: number;
  has_more: boolean;
};

function isNewerPair(candidate: CoveragePair, stored: CoveragePair | null): boolean {
  if (stored === null) {
    return true;
  }
  if (candidate.binding_epoch !== stored.binding_epoch) {
    return candidate.binding_epoch > stored.binding_epoch;
  }
  return candidate.clinic_seq > stored.clinic_seq;
}

function parseFeedPage(detail: unknown): FeedPage | null {
  if (typeof detail !== "string" || detail.length === 0) {
    return null;
  }
  try {
    const parsed = JSON.parse(detail) as Record<string, unknown>;
    const events = parsed.events;
    if (!Array.isArray(events)) {
      return null;
    }
    const after = parsed.after;
    const nextAfter = parsed.next_after;
    const hasMore = parsed.has_more;
    if (!Number.isInteger(after) || !Number.isInteger(nextAfter)) {
      return null;
    }
    if (typeof hasMore !== "boolean") {
      return null;
    }
    return {
      after: after as number,
      events: events as Record<string, unknown>[],
      next_after: nextAfter as number,
      has_more: hasMore,
    };
  } catch {
    return null;
  }
}

async function readFeedCursor(env: CoverageViewEnv): Promise<number> {
  const row = await env.DB.prepare(
    `SELECT feed_seq FROM feed_cursor WHERE id = 1`,
  ).first<{ feed_seq: number }>();
  return row?.feed_seq ?? 0;
}

async function writeFeedCursor(env: CoverageViewEnv, feedSeq: number): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO feed_cursor (id, feed_seq) VALUES (1, ?)
     ON CONFLICT(id) DO UPDATE SET feed_seq = excluded.feed_seq`,
  )
    .bind(feedSeq)
    .run();
}

async function loadStoredPair(
  env: CoverageViewEnv,
  orgId: string,
): Promise<CoveragePair | null> {
  const row = await env.DB.prepare(
    `SELECT binding_epoch, clinic_seq FROM coverage_view WHERE org_id = ?`,
  )
    .bind(orgId)
    .first<CoveragePair>();
  return row ?? null;
}

function feedEventAccepted(event: Record<string, unknown>): boolean {
  if (validateFeedEvent(event).ok === true) {
    return true;
  }
  if (typeof event.org_id !== "string" || event.org_id.length === 0) {
    return false;
  }
  if (
    !Number.isInteger(event.binding_epoch) ||
    !Number.isInteger(event.clinic_seq) ||
    !Number.isInteger(event.feed_seq)
  ) {
    return false;
  }
  return validateCoverageSnapshot(event.snapshot).ok === true;
}

async function applyFeedEvent(
  env: CoverageViewEnv,
  event: Record<string, unknown>,
): Promise<void> {
  if (!feedEventAccepted(event)) {
    return;
  }
  const orgId = event.org_id;
  if (typeof orgId !== "string") {
    return;
  }
  const candidate: CoveragePair = {
    binding_epoch: event.binding_epoch as number,
    clinic_seq: event.clinic_seq as number,
  };
  const stored = await loadStoredPair(env, orgId);
  if (!isNewerPair(candidate, stored)) {
    return;
  }
  const snapshot = event.snapshot;
  if (validateCoverageSnapshot(snapshot).ok !== true) {
    return;
  }
  await env.DB.prepare(
    `INSERT INTO coverage_view (org_id, binding_epoch, clinic_seq, snapshot)
     VALUES (?, ?, ?, ?)
     ON CONFLICT(org_id) DO UPDATE SET
       binding_epoch = excluded.binding_epoch,
       clinic_seq = excluded.clinic_seq,
       snapshot = excluded.snapshot`,
  )
    .bind(
      orgId,
      candidate.binding_epoch,
      candidate.clinic_seq,
      JSON.stringify(snapshot),
    )
    .run();
}

export async function refreshCoverageView(env: CoverageViewEnv): Promise<void> {
  let after = await readFeedCursor(env);
  let lastFeedSeq = after;

  for (;;) {
    const envelope = await env.PLATFORM.readCoverageEvents({
      contract_version: CHANNEL_VERSIONS.vendorEntrypoint,
      after,
      limit: 200,
    });
    if (envelope.result !== "ok") {
      break;
    }
    const page = parseFeedPage(envelope.detail);
    if (page === null) {
      break;
    }
    for (const event of page.events) {
      const feedSeq = event.feed_seq;
      if (typeof feedSeq === "number" && Number.isInteger(feedSeq)) {
        lastFeedSeq = feedSeq;
      }
      await applyFeedEvent(env, event);
    }
    if (page.events.length > 0) {
      lastFeedSeq = page.next_after;
    }
    if (!page.has_more) {
      break;
    }
    after = page.next_after;
  }

  await writeFeedCursor(env, lastFeedSeq);
}
