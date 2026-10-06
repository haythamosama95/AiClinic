-- P3.9: mirror fallback admission + coverage feed consumer; drop grace queue.

CREATE TABLE fallback_admission (
  installation_id TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  term_id TEXT NOT NULL,
  request_id TEXT NOT NULL,
  weight INTEGER NOT NULL,
  admitted_at TEXT NOT NULL,
  state TEXT NOT NULL,
  PRIMARY KEY (installation_id, idempotency_key),
  FOREIGN KEY (installation_id) REFERENCES installation (installation_id)
);

CREATE INDEX fallback_admission_state ON fallback_admission (state);
CREATE UNIQUE INDEX fallback_admission_request_id ON fallback_admission (request_id);

CREATE TABLE feed_consumer (
  consumer TEXT PRIMARY KEY NOT NULL,
  last_pull_at TEXT,
  last_cursor INTEGER
);

DROP TABLE IF EXISTS grace_admission_queue;
