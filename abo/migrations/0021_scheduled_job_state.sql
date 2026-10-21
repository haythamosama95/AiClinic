-- R9-CRON1: per logical scheduled job state. Success, error, retry and lease are
-- recorded separately, and last_succeeded_period is the persisted due-period checkpoint.
-- Legacy scheduled_job_run rows were stamped before each run started, so they are
-- not evidence of success and are not migrated. The legacy table is left unused.
CREATE TABLE scheduled_job_state (
  job TEXT NOT NULL PRIMARY KEY,
  last_started_at TEXT,
  last_succeeded_at TEXT,
  last_succeeded_period TEXT,
  last_error_at TEXT,
  last_error_code TEXT,
  next_attempt_at TEXT,
  consecutive_failures INTEGER NOT NULL DEFAULT 0,
  lease_token TEXT,
  lease_until TEXT
);

-- R9-AO6: resumable position of the invalid-callback R2 sweep. The cutoff day is stored
-- so a new day restarts the listing from the beginning.
CREATE TABLE housekeeping_r2_cursor (
  scope TEXT NOT NULL PRIMARY KEY,
  cutoff_day TEXT NOT NULL,
  r2_cursor TEXT
);
