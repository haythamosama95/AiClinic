import { CHANNEL_VERSIONS } from "vendor-contracts";
import { env } from "./env";
import { gatewayObjectJson } from "./gateway-object";

/**
 * Harness-only teardown guards for GatewayObject (quota DO) storage.
 *
 * Port of the `abo` cross-worker fix (`abo/test/system/cross-worker-harness.ts`
 * `drainPlatformDurableObjects` / `settlePlatformDurableObjectAlarms`): DO
 * coverage alarms are armed on WALL CLOCK (min 5 s deferral, see
 * `syncAlarm` in `src/quota-do/coverage.ts`). When a test ends with pending
 * outbox rows or an in-flight alarm handler, the isolated-storage stack frame
 * pop leaves a live SQLite `-journal` behind and the NEXT test's frame push
 * fails ("Failed to push isolated storage stack frame ... Expected .sqlite,
 * got ....sqlite-journal"), poisoning every subsequent test in the file.
 *
 * The drain runs from the shared workers-pool setup (`test/setup-isolate-
 * config-cache.ts`) global `afterEach` — covering the workers-config run
 * (`vitest.workers.config.ts`) and both version-matrix configs — and from the
 * e2e `setup.ts` global `afterEach` (harness-only, no test semantics change):
 * every write below happens inside the current test's isolated-storage frame
 * and is rolled back when the frame pops.
 */

/** `syncAlarm` never arms a DO alarm sooner than 5 s wall clock. */
const MIN_ALARM_DEFERRAL_MS = 5_000;
/** Buffer on top of the minimum deferral so a just-fired handler can finish. */
const SETTLE_BUFFER_MS = 200;
/** Trailing settle so the flushed DO's SQLite journal checkpoints cleanly. */
const TRAILING_SETTLE_MS = 500;
/** Bound the per-hook cost; a test scenario touches at most a few DOs. */
const MAX_DRAINED_INSTALLATIONS = 24;

type InstallationRow = {
  installation_id: string;
  org_id: string;
};

/**
 * Conservative abo-style settle: wait out the minimum wall-clock alarm
 * deferral so any GatewayObject alarm that was armed (or is already firing)
 * during the test completes before isolated storage is popped. Exported for
 * targeted use by stage suites; the default drain below disarms pending
 * alarms eagerly instead of paying this cost on every test.
 */
export async function settleGatewayObjectAlarms(): Promise<void> {
  await new Promise((resolve) =>
    setTimeout(resolve, MIN_ALARM_DEFERRAL_MS + SETTLE_BUFFER_MS),
  );
}

async function listInstallationRows(): Promise<InstallationRow[]> {
  const rows = new Map<string, string>();
  const ingest = async (sql: string): Promise<void> => {
    try {
      const result = await env.DB.prepare(sql).all<{
        installation_id: string;
        org_id: string;
      }>();
      for (const row of result.results ?? []) {
        if (row.installation_id && row.org_id) {
          rows.set(row.installation_id, row.org_id);
        }
      }
    } catch {
      // Table may not exist before migrations run (early boot tests).
    }
  };

  await ingest(`SELECT installation_id, org_id FROM installation`);
  await ingest(`SELECT installation_id, org_id FROM tenant_binding`);
  return [...rows.entries()].map(([installation_id, org_id]) => ({
    installation_id,
    org_id,
  }));
}

/**
 * Flush the GatewayObject outbox for one installation. `refresh_coverage_
 * snapshot` drains every pending outbox row (coverage events, grant ledger,
 * voids, usage adjustments, alerts) and re-syncs the alarm via
 * `shipCoverageOutboxInLock`, which calls `deleteAlarm()` when nothing is
 * pending. Awaiting the RPC also serializes behind any in-flight alarm
 * handler (`blockConcurrencyWhile`), so by return time the DO is quiescent.
 */
async function flushInstallationOutbox(row: InstallationRow): Promise<void> {
  await gatewayObjectJson(row.installation_id, {
    kind: "refresh_coverage_snapshot",
    installationId: row.installation_id,
    orgId: row.org_id,
    vendorContractVersion: CHANNEL_VERSIONS.platformDo,
  });
}

/**
 * Drain every GatewayObject touched by the finished test so no DO alarm or
 * scheduled outbox work stays armed across the isolated-storage frame pop.
 * Best-effort: never fails the test it runs after.
 */
export async function drainGatewayObjects(): Promise<void> {
  // Defensive: drain is a no-op when this workers-pool runtime does not bind
  // the platform storage (e.g. a variant config without DB/DO). Never fails
  // the test it runs after.
  const bindings = env as { DB?: unknown; DO?: unknown };
  if (bindings.DB === undefined || bindings.DO === undefined) {
    return;
  }
  const installations = await listInstallationRows();
  if (installations.length === 0) {
    return;
  }

  for (const row of installations.slice(0, MAX_DRAINED_INSTALLATIONS)) {
    try {
      await flushInstallationOutbox(row);
    } catch {
      // Best-effort settle before isolated storage pop.
    }
  }

  await new Promise((resolve) => setTimeout(resolve, TRAILING_SETTLE_MS));
}