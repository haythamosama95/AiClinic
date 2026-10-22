import { env } from "cloudflare:test";
import { beforeAll, describe, expect, it, vi } from "vitest";
import {
  al19KillSwitchAlertKey,
  deliverDurableAlert,
  insertDoRebuildMismatchAlert,
  listIncompleteUnsentPlatformAlerts,
  pingPlatformHeartbeat,
  persistCommittedAlertBody,
  persistDurableAlertBody,
  raiseAl11GrantFromOutbox,
  raiseAl12GrantFromOutbox,
  raiseAl17FromOutbox,
  raiseAl11Transfer,
  raiseAl19FromOutbox,
  retryUnsentPlatformAlerts,
  stableAlertJson,
} from "../src/alert/index";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import tokenContractMigrationSql from "../migrations/20260803120000_token_contract.sql?raw";
import issuerKeyTenantBindingMigrationSql from "../migrations/20261003130000_issuer_key_tenant_binding.sql?raw";
import operatorCredentialMigrationSql from "../migrations/20261003120000_operator_credential_and_platform_alert.sql?raw";
import rm31AlertDeliverySql from "../migrations/20261021130000_rm31_alert_delivery.sql?raw";
import { applySqlStatements } from "./split-sql-statements";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    DB: D1Database;
  }
}

beforeAll(async () => {
  await applySqlStatements(env.DB, migrationSql);
  await applySqlStatements(env.DB, tokenContractMigrationSql);
  await applySqlStatements(env.DB, issuerKeyTenantBindingMigrationSql);
  await applySqlStatements(env.DB, operatorCredentialMigrationSql);
  await applySqlStatements(env.DB, rm31AlertDeliverySql);
});

function mailEnv(send: ReturnType<typeof vi.fn>) {
  return {
    DB: env.DB,
    ALERT_EMAIL_TO: "ops@clinic.test",
    HEARTBEAT_URL: "https://heartbeat.test/ping",
    SEND_EMAIL: { send },
  };
}

function callsFor(send: ReturnType<typeof vi.fn>, marker: string) {
  return send.mock.calls.filter((call) =>
    String((call[0] as { text: string }).text).includes(marker),
  );
}

async function alertRow(alertKey: string) {
  return env.DB.prepare(
    `SELECT code, send_state, body_state, body_json, lease_token, resolved_at
     FROM platform_alert WHERE alert_key = ?`,
  )
    .bind(alertKey)
    .first<{
      code: string;
      send_state: string;
      body_state: string;
      body_json: string | null;
      lease_token: string | null;
      resolved_at: string | null;
    }>();
}

describe("R9-PAL1 alert delivery durability", () => {
  it("R9-PAL1 AL-11 body is persisted before send and a failed email is retried once with the same body", async () => {
    const alertKey = "AL-11:r9-pal1-grant-1";
    const body = {
      code: "AL-11",
      org_id: "org-r9-pal1-1",
      operation: { op: "grant", params: { duration: 30 } },
    };
    const send = vi.fn().mockRejectedValueOnce(new Error("mail down"));
    await raiseAl11GrantFromOutbox(mailEnv(send), alertKey, body);

    const failed = await alertRow(alertKey);
    expect(failed?.send_state).toBe("unsent");
    expect(failed?.body_state).toBe("stored");
    expect(failed?.body_json).toBe(stableAlertJson(body));
    expect(failed?.lease_token).toBeNull();

    await retryUnsentPlatformAlerts(mailEnv(send));
    expect(callsFor(send, "org-r9-pal1-1")).toHaveLength(2);
    expect(send.mock.calls[1]?.[0]).toMatchObject({
      subject: "AL-11",
      text: stableAlertJson(body),
    });
    expect((await alertRow(alertKey))?.send_state).toBe("sent");
  });

  it("R9-PAL1 AL-12, AL-19 and do_rebuild_mismatch failures each retry through the same dispatcher", async () => {
    const send = vi.fn().mockResolvedValue(undefined);

    send.mockRejectedValueOnce(new Error("mail down"));
    await raiseAl12GrantFromOutbox(mailEnv(send), "AL-12:r9-pal1-grant-2", {
      code: "AL-12",
      org_id: "org-r9-pal1-2",
    });
    send.mockRejectedValueOnce(new Error("mail down"));
    await raiseAl19FromOutbox(mailEnv(send), "AL-19:suspend:org-r9-pal1-2:9", {
      code: "AL-19",
      org_id: "org-r9-pal1-2",
    });
    await insertDoRebuildMismatchAlert(
      env.DB,
      "inst-r9-pal1-2",
      new Date().toISOString(),
      "r9_pal1",
    );
    expect(callsFor(send, "org-r9-pal1-2")).toHaveLength(2);
    expect(callsFor(send, "inst-r9-pal1-2")).toHaveLength(0);

    await retryUnsentPlatformAlerts(mailEnv(send));
    // Two failed first attempts (AL-12, AL-19) plus one successful retry each.
    expect(callsFor(send, "org-r9-pal1-2")).toHaveLength(4);
    expect(callsFor(send, "inst-r9-pal1-2")).toHaveLength(1);
    expect(callsFor(send, "inst-r9-pal1-2")[0]?.[0]).toMatchObject({
      subject: "do_rebuild_mismatch",
    });
    expect((await alertRow("AL-12:r9-pal1-grant-2"))?.send_state).toBe("sent");
    expect((await alertRow("AL-19:suspend:org-r9-pal1-2:9"))?.send_state).toBe("sent");
    expect((await alertRow("do-rebuild:inst-r9-pal1-2:r9_pal1"))?.send_state).toBe("sent");

    await retryUnsentPlatformAlerts(mailEnv(send));
    expect(callsFor(send, "org-r9-pal1-2")).toHaveLength(4);
    expect(callsFor(send, "inst-r9-pal1-2")).toHaveLength(1);
  });

  it("R9-PAL1 transfer AL-11 failure is retried once by the dispatcher with the stored body", async () => {
    const send = vi.fn().mockRejectedValueOnce(new Error("mail down"));
    await raiseAl11Transfer(mailEnv(send), "transfer-r9-pal1-1", "org-r9-pal1-transfer");
    expect((await alertRow("AL-11:transfer:transfer-r9-pal1-1"))?.send_state).toBe("unsent");

    await retryUnsentPlatformAlerts(mailEnv(send));
    expect(callsFor(send, "transfer-r9-pal1-1")).toHaveLength(2);
    expect((await alertRow("AL-11:transfer:transfer-r9-pal1-1"))?.send_state).toBe("sent");
  });

  it("R9-PAL1 an existing alert key with a different stored body is an explicit conflict, not an overwrite", async () => {
    const alertKey = "AL-19:resume:org-r9-pal1-conflict:4";
    const now = new Date().toISOString();
    await persistDurableAlertBody(
      env.DB,
      { alertKey, code: "AL-19", body: { code: "AL-19", reason: "first" }, nowIso: now },
      { countRepeat: false },
    );
    await expect(
      persistDurableAlertBody(
        env.DB,
        { alertKey, code: "AL-19", body: { code: "AL-19", reason: "second" }, nowIso: now },
        { countRepeat: false },
      ),
    ).rejects.toThrow(`alert_body_conflict:${alertKey}`);
    expect((await alertRow(alertKey))?.body_json).toBe(
      stableAlertJson({ code: "AL-19", reason: "first" }),
    );
  });

  it("R9-PAL1 replaying the same persisted body after a crash before outbox delete does not conflict", async () => {
    const alertKey = "AL-11:r9-pal1-replay-1";
    const body = { code: "AL-11", org_id: "org-r9-pal1-replay" };
    const now = new Date().toISOString();
    await persistDurableAlertBody(
      env.DB,
      { alertKey, code: "AL-11", body, nowIso: now },
      { countRepeat: false },
    );
    await expect(
      persistDurableAlertBody(
        env.DB,
        { alertKey, code: "AL-11", body: { org_id: "org-r9-pal1-replay", code: "AL-11" }, nowIso: now },
        { countRepeat: false },
      ),
    ).resolves.toBeUndefined();
  });

  it("R9-PAL1 an acknowledged one-shot is not sent again by the ordinary retry dispatcher", async () => {
    const alertKey = "AL-11:r9-pal1-sent-once";
    const send = vi.fn().mockResolvedValue(undefined);
    await raiseAl11GrantFromOutbox(mailEnv(send), alertKey, {
      code: "AL-11",
      org_id: "org-r9-pal1-sent",
    });
    expect(callsFor(send, "org-r9-pal1-sent")).toHaveLength(1);
    await retryUnsentPlatformAlerts(mailEnv(send));
    await retryUnsentPlatformAlerts(mailEnv(send));
    expect(callsFor(send, "org-r9-pal1-sent")).toHaveLength(1);
  });

  it("R9-PAL1 a row held under a live lease is not sent by a concurrent dispatcher and is sent after the lease expires", async () => {
    const alertKey = "AL-19:suspend:org-r9-pal1-lease:12";
    const now = new Date().toISOString();
    await persistDurableAlertBody(
      env.DB,
      { alertKey, code: "AL-19", body: { code: "AL-19", org_id: "org-r9-pal1-lease" }, nowIso: now },
      { countRepeat: false },
    );
    const future = new Date(Date.now() + 60_000).toISOString();
    await env.DB.prepare(
      `UPDATE platform_alert SET lease_token = 'other-owner', lease_expires_at = ? WHERE alert_key = ?`,
    )
      .bind(future, alertKey)
      .run();

    const send = vi.fn().mockResolvedValue(undefined);
    await expect(deliverDurableAlert(mailEnv(send), alertKey)).resolves.toBe(false);
    expect(callsFor(send, "org-r9-pal1-lease")).toHaveLength(0);

    const past = new Date(Date.now() - 60_000).toISOString();
    await env.DB.prepare(
      `UPDATE platform_alert SET lease_expires_at = ? WHERE alert_key = ?`,
    )
      .bind(past, alertKey)
      .run();
    await expect(deliverDurableAlert(mailEnv(send), alertKey)).resolves.toBe(true);
    expect(callsFor(send, "org-r9-pal1-lease")).toHaveLength(1);
  });

  it("R9-PAL1 legacy body-less unsent rows stay unsent and are never reconstructed or sent", async () => {
    const alertKey = "AL-13:legacy-r9-pal1:bootstrap";
    const now = new Date().toISOString();
    await env.DB.prepare(
      `INSERT INTO platform_alert
         (alert_key, code, severity, first_at, last_at, count, send_state, next_send_at, resolved_at)
       VALUES (?, 'AL-13', 'high', ?, ?, 1, 'unsent', NULL, NULL)`,
    )
      .bind(alertKey, now, now)
      .run();

    const send = vi.fn().mockResolvedValue(undefined);
    await retryUnsentPlatformAlerts(mailEnv(send));
    expect(callsFor(send, "legacy-r9-pal1")).toHaveLength(0);
    const row = await alertRow(alertKey);
    expect(row?.send_state).toBe("unsent");
    expect(row?.body_state).toBe("incomplete");
    expect(row?.body_json).toBeNull();
  });

  it("R9-PAL1 a recurring AL-17 condition that becomes active again after resolution is sent again", async () => {
    const alertKey = "AL-17:clinic:org-r9-pal1-recur";
    const body = { code: "AL-17", org_id: "org-r9-pal1-recur" };
    const send = vi.fn().mockResolvedValue(undefined);

    await raiseAl17FromOutbox(mailEnv(send), alertKey, body);
    expect(callsFor(send, "org-r9-pal1-recur")).toHaveLength(1);

    await env.DB.prepare(
      `UPDATE platform_alert SET resolved_at = ? WHERE alert_key = ?`,
    )
      .bind(new Date().toISOString(), alertKey)
      .run();

    await raiseAl17FromOutbox(mailEnv(send), alertKey, body);
    expect(callsFor(send, "org-r9-pal1-recur")).toHaveLength(2);
    expect((await alertRow(alertKey))?.resolved_at).toBeNull();
  });

  // Level note: the outbox ship loop (coverage.ts shipCoverageOutboxInLock)
  // needs Durable Object storage, which this harness does not model. These
  // tests drive the same persist-then-deliver steps that the outbox branch uses.
  it("R9-PAL1 crash after the D1 alert insert and before the outbox delete retries once with the same body", async () => {
    const alertKey = "AL-11:r9-pal1-crash-1";
    const body = { code: "AL-11", org_id: "org-r9-pal1-crash" };
    const now = new Date().toISOString();
    // Crash point: body is persisted, the outbox row is not deleted, nothing is sent.
    await persistCommittedAlertBody(
      env.DB,
      { alertKey, code: "AL-11", body, nowIso: now },
      { countRepeat: false },
    );

    // Restart replays the same outbox row with the same body.
    const replayed = await persistCommittedAlertBody(
      env.DB,
      { alertKey, code: "AL-11", body: { org_id: "org-r9-pal1-crash", code: "AL-11" }, nowIso: now },
      { countRepeat: false },
    );
    expect(replayed).toBe(true);

    let failures = 1;
    const send = vi.fn(async (message: { text: string }) => {
      if (message.text.includes("org-r9-pal1-crash") && failures > 0) {
        failures -= 1;
        throw new Error("mail down");
      }
    });
    await retryUnsentPlatformAlerts(mailEnv(send));
    await retryUnsentPlatformAlerts(mailEnv(send));

    const attempts = callsFor(send, "org-r9-pal1-crash");
    expect(attempts).toHaveLength(2);
    expect(attempts[0]?.[0]).toMatchObject({ text: stableAlertJson(body) });
    expect(attempts[1]?.[0]).toMatchObject({ text: stableAlertJson(body) });
    expect((await alertRow(alertKey))?.send_state).toBe("sent");
  });

  it("R9-PAL1 conflicting alert body on a shipped outbox row is skipped and the next row still ships", async () => {
    const conflictKey = "AL-19:resume:org-r9-pal1-outbox-conflict:7";
    const now = new Date().toISOString();
    await persistDurableAlertBody(
      env.DB,
      { alertKey: conflictKey, code: "AL-19", body: { code: "AL-19", reason: "stored-first" }, nowIso: now },
      { countRepeat: false },
    );

    // Outbox row 1 carries a different body for the same key: skipped, not thrown.
    const conflicted = await persistCommittedAlertBody(
      env.DB,
      { alertKey: conflictKey, code: "AL-19", body: { code: "AL-19", reason: "different" }, nowIso: now },
      { countRepeat: false },
    );
    expect(conflicted).toBe(false);

    // Outbox row 2 still ships.
    const nextKey = "AL-11:r9-pal1-outbox-next";
    const next = await persistCommittedAlertBody(
      env.DB,
      { alertKey: nextKey, code: "AL-11", body: { code: "AL-11", org_id: "org-r9-pal1-outbox-next" }, nowIso: now },
      { countRepeat: false },
    );
    expect(next).toBe(true);
    const send = vi.fn().mockResolvedValue(undefined);
    await expect(deliverDurableAlert(mailEnv(send), nextKey)).resolves.toBe(true);
    expect(callsFor(send, "org-r9-pal1-outbox-next")).toHaveLength(1);

    // The stored body is never overwritten, and the conflict is recorded for the operator.
    expect((await alertRow(conflictKey))?.body_json).toBe(
      stableAlertJson({ code: "AL-19", reason: "stored-first" }),
    );
    const record = await alertRow(`alert_body_conflict:${conflictKey}`);
    expect(record?.code).toBe("alert_body_conflict");
    await retryUnsentPlatformAlerts(mailEnv(send));
    expect(callsFor(send, "alert_body_conflict")).toHaveLength(1);
    expect(callsFor(send, "alert_body_conflict")[0]?.[0]).toMatchObject({
      text: expect.stringContaining(conflictKey),
    });
  });

  it("R9-PAL1 kill-switch arm disarm arm produces distinct alert keys", async () => {
    const transitions: Array<{ action: "arm" | "disarm"; changed_at: string }> = [
      { action: "arm", changed_at: "2026-10-22T10:00:00.000Z" },
      { action: "disarm", changed_at: "2026-10-22T10:00:01.000Z" },
      { action: "arm", changed_at: "2026-10-22T10:00:02.000Z" },
    ];
    const target = "inst-r9-pal1-ks";
    const keys = transitions.map((transition) =>
      al19KillSwitchAlertKey("installation", target, transition),
    );
    expect(new Set(keys).size).toBe(3);

    const send = vi.fn().mockResolvedValue(undefined);
    for (const [index, transition] of transitions.entries()) {
      await raiseAl19FromOutbox(mailEnv(send), keys[index] ?? "", {
        code: "AL-19",
        action: transition.action,
        scope: "installation",
        target,
        changed_at: transition.changed_at,
      });
    }
    // Each transition is notified; none is suppressed by an earlier one.
    expect(callsFor(send, target)).toHaveLength(3);
    for (const key of keys) {
      expect((await alertRow(key))?.send_state).toBe("sent");
    }
  });

  it("R9-PAL1 listIncompleteUnsentPlatformAlerts returns only legacy body-less unsent rows", async () => {
    const now = new Date().toISOString();
    const legacyUnsentKey = "AL-13:legacy-r9-pal1-list:bootstrap";
    const legacySentKey = "AL-13:legacy-r9-pal1-list-sent:bootstrap";
    const storedKey = "AL-11:r9-pal1-list-stored";
    await env.DB.prepare(
      `INSERT INTO platform_alert
         (alert_key, code, severity, first_at, last_at, count, send_state, next_send_at, resolved_at)
       VALUES (?, 'AL-13', 'high', ?, ?, 1, 'unsent', NULL, NULL)`,
    )
      .bind(legacyUnsentKey, now, now)
      .run();
    await env.DB.prepare(
      `INSERT INTO platform_alert
         (alert_key, code, severity, first_at, last_at, count, send_state, next_send_at, resolved_at)
       VALUES (?, 'AL-13', 'high', ?, ?, 1, 'sent', NULL, NULL)`,
    )
      .bind(legacySentKey, now, now)
      .run();
    await persistDurableAlertBody(
      env.DB,
      { alertKey: storedKey, code: "AL-11", body: { code: "AL-11", org_id: "org-r9-pal1-list" }, nowIso: now },
      { countRepeat: false },
    );

    const rows = await listIncompleteUnsentPlatformAlerts(env.DB);
    const keys = rows.map((row) => row.alert_key);
    expect(keys).toContain(legacyUnsentKey);
    expect(keys).not.toContain(legacySentKey);
    expect(keys).not.toContain(storedKey);
    for (const key of keys) {
      const row = await alertRow(key);
      expect(row?.body_state).toBe("incomplete");
      expect(row?.send_state).toBe("unsent");
    }
  });
});

describe("R9-RT2 platform heartbeat stream", () => {
  it("R9-RT2 platform_5min pings HEARTBEAT_URL_PLATFORM and uses HEARTBEAT_URL only while it is unset", async () => {
    const fetchSpy = vi
      .spyOn(globalThis, "fetch")
      .mockResolvedValue(new Response("ok", { status: 200 }));
    try {
      await pingPlatformHeartbeat({
        ...mailEnv(vi.fn()),
        HEARTBEAT_URL_PLATFORM: "https://heartbeat.test/platform",
      });
      expect(fetchSpy).toHaveBeenLastCalledWith("https://heartbeat.test/platform");

      await pingPlatformHeartbeat(mailEnv(vi.fn()));
      expect(fetchSpy).toHaveBeenLastCalledWith("https://heartbeat.test/ping");
    } finally {
      fetchSpy.mockRestore();
    }
  });
});
