-- RM24: durable fallback JTI and request binding for outage admissions.
ALTER TABLE fallback_admission ADD COLUMN jti TEXT;
ALTER TABLE fallback_admission ADD COLUMN actor_id TEXT;
ALTER TABLE fallback_admission ADD COLUMN branch_id TEXT;
ALTER TABLE fallback_admission ADD COLUMN capability_id TEXT;
ALTER TABLE fallback_admission ADD COLUMN request_fingerprint TEXT;
ALTER TABLE fallback_admission ADD COLUMN plan_snapshot TEXT;

CREATE UNIQUE INDEX fallback_admission_installation_jti
  ON fallback_admission (installation_id, jti)
  WHERE jti IS NOT NULL;

CREATE INDEX fallback_admission_installation_state
  ON fallback_admission (installation_id, state);
