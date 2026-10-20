CREATE TABLE rebuild_checkpoint (
  id INTEGER NOT NULL PRIMARY KEY CHECK (id = 1),
  last_fact_seq INTEGER NOT NULL,
  payload_sha256 TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE rebuild_due_checkpoint (
  id INTEGER NOT NULL PRIMARY KEY CHECK (id = 1),
  last_fact_seq INTEGER NOT NULL,
  updated_at TEXT NOT NULL
);
