CREATE TABLE issuer_key (
  kid TEXT PRIMARY KEY NOT NULL,
  issuer TEXT NOT NULL,
  public_key TEXT NOT NULL,
  status TEXT NOT NULL,
  not_before TEXT NOT NULL,
  not_after TEXT NOT NULL,
  registered_by TEXT NOT NULL,
  assertion_sha256 TEXT NOT NULL
);

CREATE TABLE tenant_binding (
  org_id TEXT NOT NULL,
  installation_id TEXT NOT NULL,
  epoch INTEGER NOT NULL,
  status TEXT NOT NULL,
  retired_at TEXT,
  reason TEXT,
  created_at TEXT NOT NULL,
  PRIMARY KEY (org_id, epoch),
  FOREIGN KEY (installation_id) REFERENCES installation (installation_id)
);

CREATE UNIQUE INDEX tenant_binding_one_live_org ON tenant_binding (org_id)
  WHERE status IN ('active', 'held_for_transfer');

DROP TABLE IF EXISTS installation_key;

CREATE TABLE IF NOT EXISTS token_contract (
  ver TEXT PRIMARY KEY NOT NULL,
  added_at TEXT NOT NULL,
  retired_at TEXT,
  changed_by TEXT NOT NULL
);

UPDATE token_contract
SET retired_at = '2026-10-03T13:00:00.000Z'
WHERE ver = '1' AND retired_at IS NULL;

INSERT OR IGNORE INTO token_contract (ver, added_at, retired_at, changed_by)
VALUES ('2', '2026-10-03T13:00:00.000Z', NULL, 'migration');
