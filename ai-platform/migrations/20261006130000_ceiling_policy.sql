CREATE TABLE ceiling_policy (
  version INTEGER PRIMARY KEY NOT NULL,
  per_grant_max_days INTEGER NOT NULL,
  per_grant_max_allowance_months INTEGER NOT NULL,
  window_days INTEGER NOT NULL,
  window_max_days INTEGER NOT NULL,
  window_max_allowance_months INTEGER NOT NULL,
  max_paid_grace_days INTEGER NOT NULL,
  paid_cap_rule TEXT NOT NULL,
  set_by TEXT NOT NULL,
  assertion_sha256 TEXT NOT NULL
);

INSERT INTO ceiling_policy (
  version,
  per_grant_max_days,
  per_grant_max_allowance_months,
  window_days,
  window_max_days,
  window_max_allowance_months,
  max_paid_grace_days,
  paid_cap_rule,
  set_by,
  assertion_sha256
) VALUES (1, 31, 1, 90, 62, 2, 7, 'proportional', '', '');
