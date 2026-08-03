-- J1: additive lifecycle overlay columns on capability_grant (global-scope overlay rows).
ALTER TABLE capability_grant ADD COLUMN lifecycle_state TEXT;
ALTER TABLE capability_grant ADD COLUMN successor_id TEXT;
ALTER TABLE capability_grant ADD COLUMN deprecated_at TEXT;
ALTER TABLE capability_grant ADD COLUMN retire_after TEXT;
