CREATE TABLE abo_recovery_fence (
  id INTEGER NOT NULL PRIMARY KEY CHECK (id = 1),
  active INTEGER NOT NULL CHECK (active IN (0, 1)),
  generation INTEGER NOT NULL,
  owner_token TEXT,
  lease_until TEXT,
  updated_at TEXT NOT NULL
);
