-- Durable grace-admission queue + cap (audit 1.4). Same D1 as the platform
-- schema; drained by cron when the Quota DO is reachable again.
CREATE TABLE grace_admission_queue (
  grace_request_id TEXT PRIMARY KEY NOT NULL,
  installation_id TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  jti TEXT NOT NULL,
  request_reference TEXT NOT NULL,
  entitlement_json TEXT NOT NULL,
  usage_tokens INTEGER,
  usage_cost REAL,
  partial INTEGER,
  queued_at TEXT NOT NULL,
  reconcile_attempts INTEGER NOT NULL DEFAULT 0,
  reconcile_first_seen_at_ms INTEGER,
  status TEXT NOT NULL,
  UNIQUE (installation_id, idempotency_key),
  FOREIGN KEY (installation_id) REFERENCES installation (installation_id)
);
