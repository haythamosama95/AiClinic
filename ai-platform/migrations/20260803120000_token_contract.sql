-- J4: platform-global accepted AAT ver set (token_contract).
CREATE TABLE token_contract (
  ver TEXT PRIMARY KEY NOT NULL,
  added_at TEXT NOT NULL,
  retired_at TEXT,
  changed_by TEXT NOT NULL
);

INSERT INTO token_contract (ver, added_at, retired_at, changed_by)
VALUES ('1', '2026-08-03T00:00:00.000Z', NULL, 'seed');
