ALTER TABLE grant_outcome RENAME TO grant_outcome_legacy;

CREATE TABLE grant_outcome_event (
  outcome_seq INTEGER PRIMARY KEY AUTOINCREMENT,
  attempt_id TEXT NOT NULL UNIQUE,
  grant_id TEXT NOT NULL,
  result TEXT NOT NULL,
  code TEXT,
  terminal INTEGER NOT NULL CHECK (terminal IN (0, 1)),
  abo_kid TEXT,
  abo_signature TEXT,
  receipt TEXT,
  term_ids TEXT,
  at TEXT NOT NULL
);

CREATE INDEX grant_outcome_event_grant_order
  ON grant_outcome_event (grant_id, outcome_seq);

INSERT INTO grant_outcome_event (
  attempt_id, grant_id, result, code, terminal, abo_kid, abo_signature,
  receipt, term_ids, at
)
SELECT 'legacy:' || grant_id, grant_id, result, NULL,
       CASE WHEN result IN ('applied', 'already_applied') THEN 1 ELSE 0 END,
       abo_kid, abo_signature, receipt, term_ids, at
FROM grant_outcome_legacy;

CREATE VIEW grant_outcome AS
WITH ranked AS (
  SELECT grant_id, result, abo_kid, abo_signature, receipt, term_ids, at,
         ROW_NUMBER() OVER (
           PARTITION BY grant_id
           ORDER BY CASE WHEN terminal = 1 THEN 0 ELSE 1 END,
                    CASE WHEN terminal = 1 THEN outcome_seq END ASC,
                    CASE WHEN terminal = 0 THEN outcome_seq END DESC
         ) AS effective_rank
  FROM grant_outcome_event
)
SELECT grant_id, result, abo_kid, abo_signature, receipt, term_ids, at
FROM ranked WHERE effective_rank = 1;

CREATE TRIGGER grant_outcome_event_abort_update
BEFORE UPDATE ON grant_outcome_event
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER grant_outcome_event_abort_delete
BEFORE DELETE ON grant_outcome_event
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;
