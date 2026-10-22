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

type FeedPage = {
  after: number;
  events: Record<string, unknown>[];
  next_after: number;
  has_more: boolean;
};

// R7-A1 step 1: the lexicographic (binding_epoch, clinic_seq) order is enforced by the upsert
// predicate itself, so a stale writer cannot replace a newer snapshot between a read and a write.
const COVERAGE_UPSERT_SQL = `INSERT INTO coverage_view (org_id, binding_epoch, clinic_seq, snapshot)
     VALUES (?, ?, ?, ?)
     ON CONFLICT(org_id) DO UPDATE SET
       binding_epoch = excluded.binding_epoch,
       clinic_seq = excluded.clinic_seq,
       snapshot = excluded.snapshot
     WHERE excluded.binding_epoch > coverage_view.binding_epoch
       OR (excluded.binding_epoch = coverage_view.binding_epoch
           AND excluded.clinic_seq > coverage_view.clinic_seq)`;

// R7-A1 step 2: the ordinary cursor only moves forward. An explicit reset is owned by R9.
const FEED_CURSOR_UPSERT_SQL = `INSERT INTO feed_cursor (id, feed_seq) VALUES (1, ?)
     ON CONFLICT(id) DO UPDATE SET feed_seq = MAX(feed_cursor.feed_seq, excluded.feed_seq)`;

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

export function feedEventAccepted(event: Record<string, unknown>): boolean {
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

// Returns the ordered upsert for an accepted event, or null when the event is rejected.
function coverageUpsertStatement(
  env: CoverageViewEnv,
  event: Record<string, unknown>,
): D1PreparedStatement | null {
  if (!feedEventAccepted(event)) {
    return null;
  }
  const orgId = event.org_id;
  if (typeof orgId !== "string" || !Number.isInteger(event.feed_seq)) {
    return null;
  }
  if (validateCoverageSnapshot(event.snapshot).ok !== true) {
    return null;
  }
  return env.DB.prepare(COVERAGE_UPSERT_SQL).bind(
    orgId,
    event.binding_epoch,
    event.clinic_seq,
    JSON.stringify(event.snapshot),
  );
}

export async function refreshCoverageView(env: CoverageViewEnv): Promise<void> {
  let after = await readFeedCursor(env);

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

    // R7-A1 step 2: the page's validated upserts and its cursor move commit in one D1 batch.
    // A rejected event is never applied and the cursor does not pass it; the walk stops there.
    const statements: D1PreparedStatement[] = [];
    let lastAcceptedFeedSeq: number | null = null;
    let rejected = false;
    for (const event of page.events) {
      const statement = coverageUpsertStatement(env, event);
      if (statement === null) {
        rejected = true;
        break;
      }
      statements.push(statement);
      lastAcceptedFeedSeq = event.feed_seq as number;
    }

    let cursorTarget: number | null = null;
    if (rejected) {
      cursorTarget = lastAcceptedFeedSeq;
    } else if (page.events.length > 0) {
      cursorTarget = page.next_after;
    }
    if (cursorTarget !== null) {
      statements.push(
        env.DB.prepare(FEED_CURSOR_UPSERT_SQL).bind(cursorTarget),
      );
    }
    if (statements.length > 0) {
      await env.DB.batch(statements);
    }

    if (rejected || !page.has_more) {
      break;
    }
    after = page.next_after;
  }
}
