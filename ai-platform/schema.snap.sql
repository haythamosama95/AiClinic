CREATE TABLE ai_attempt (
  attempt_id TEXT PRIMARY KEY NOT NULL,
  request_id TEXT NOT NULL,
  attempt_no INTEGER NOT NULL,
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  outcome TEXT NOT NULL,
  latency_ms INTEGER NOT NULL,
  tokens_in INTEGER NOT NULL,
  tokens_out INTEGER NOT NULL,
  cost REAL NOT NULL,
  provider_request_id TEXT,
  error_code TEXT,
  FOREIGN KEY (request_id) REFERENCES ai_request (request_id)
);

CREATE TABLE ai_request (
  request_id TEXT PRIMARY KEY NOT NULL,
  
  request_reference TEXT NOT NULL,
  installation_id TEXT NOT NULL,
  actor_id TEXT NOT NULL,
  branch_id TEXT,
  capability_id TEXT NOT NULL,
  capability_version TEXT NOT NULL,
  prompt_artifact_hash TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  state TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  completed_at TEXT,
  terminal_error_code TEXT,
  trace_id TEXT NOT NULL,
  payload_pointer TEXT,
  routing_tier TEXT,
  routing_decision TEXT,
  conversation_id TEXT,
  turn_ordinal INTEGER,
  FOREIGN KEY (installation_id) REFERENCES installation (installation_id)
);

CREATE TABLE assertion_used (
  challenge_sha256 TEXT PRIMARY KEY NOT NULL,
  credential_id TEXT NOT NULL,
  used_at TEXT NOT NULL
);

CREATE TABLE capability_grant (
  grant_id TEXT PRIMARY KEY NOT NULL,
  scope TEXT NOT NULL,
  capability_id TEXT NOT NULL,
  capability_version TEXT NOT NULL,
  granted_at TEXT NOT NULL,
  revoked_at TEXT,
  changed_at TEXT NOT NULL,
  changed_by TEXT NOT NULL
, lifecycle_state TEXT, successor_id TEXT, deprecated_at TEXT, retire_after TEXT);

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

CREATE TABLE control_audit (
  audit_id TEXT PRIMARY KEY NOT NULL,
  operator_id TEXT NOT NULL,
  action TEXT NOT NULL,
  target TEXT NOT NULL,
  before_pointer TEXT,
  after_pointer TEXT,
  recorded_at TEXT NOT NULL
, actor TEXT, assertion_sha256 TEXT);

CREATE TABLE coverage_event (
  feed_seq INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  event_id TEXT NOT NULL UNIQUE,
  org_id TEXT NOT NULL,
  installation_id TEXT NOT NULL,
  binding_epoch INTEGER NOT NULL,
  clinic_seq INTEGER NOT NULL,
  kind TEXT NOT NULL,
  snapshot TEXT NOT NULL,
  at TEXT NOT NULL
);

CREATE TABLE coverage_mirror (
  installation_id TEXT PRIMARY KEY NOT NULL,
  org_id TEXT NOT NULL,
  binding_epoch INTEGER NOT NULL,
  clinic_seq INTEGER NOT NULL,
  state TEXT NOT NULL,
  suspended INTEGER NOT NULL,
  hard_stop_at TEXT,
  term_snapshot TEXT NOT NULL
);

CREATE TABLE credit_price (
  version TEXT PRIMARY KEY NOT NULL,
  price_per_credit REAL NOT NULL,
  currency TEXT NOT NULL,
  active_from TEXT NOT NULL,
  activated_by TEXT NOT NULL
);

CREATE TABLE entitlement (
  entitlement_id TEXT PRIMARY KEY NOT NULL,
  installation_id TEXT NOT NULL,
  plan TEXT NOT NULL,
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  request_quota INTEGER NOT NULL,
  token_budget INTEGER NOT NULL,
  cost_budget REAL NOT NULL,
  allowed_capabilities TEXT NOT NULL,
  soft_threshold REAL NOT NULL,
  status TEXT NOT NULL, credit_budget INTEGER NOT NULL DEFAULT 0, max_cost_class TEXT NOT NULL DEFAULT '',
  FOREIGN KEY (installation_id) REFERENCES installation (installation_id)
);

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

CREATE TABLE feed_consumer (
  consumer TEXT PRIMARY KEY NOT NULL,
  last_pull_at TEXT,
  last_cursor INTEGER
);

CREATE TABLE grant_ledger (
  grant_id TEXT PRIMARY KEY NOT NULL,
  origin_grant_id TEXT NOT NULL,
  org_id TEXT NOT NULL,
  installation_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  source_kind TEXT NOT NULL,
  operator_credential_id TEXT NOT NULL,
  envelope_sha256 TEXT NOT NULL,
  receipt TEXT NOT NULL,
  applied_at TEXT NOT NULL
);

CREATE TABLE grant_void (
  grant_id TEXT PRIMARY KEY NOT NULL,
  reason TEXT NOT NULL,
  source TEXT NOT NULL,
  evidence_sha256 TEXT NOT NULL,
  at TEXT NOT NULL
);

CREATE TABLE installation (
  installation_id TEXT PRIMARY KEY NOT NULL,
  org_id TEXT NOT NULL,
  display_name TEXT NOT NULL,
  status TEXT NOT NULL,
  region TEXT NOT NULL,
  enrolled_at TEXT NOT NULL
);

CREATE TABLE invoice (
  installation_id TEXT NOT NULL,
  period TEXT NOT NULL,
  credits_consumed INTEGER NOT NULL,
  credit_price_version TEXT NOT NULL,
  total REAL NOT NULL,
  status TEXT NOT NULL,
  issued_at TEXT NOT NULL,
  PRIMARY KEY (installation_id, period)
);

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

CREATE TABLE kill_switch (
  scope TEXT NOT NULL,
  target TEXT NOT NULL,
  active INTEGER NOT NULL,
  changed_at TEXT NOT NULL,
  changed_by TEXT NOT NULL,
  PRIMARY KEY (scope, target)
);

CREATE TABLE operator_credential (
  credential_id TEXT PRIMARY KEY NOT NULL,
  operator_email TEXT NOT NULL,
  public_key_cose TEXT NOT NULL,
  alg TEXT NOT NULL,
  status TEXT NOT NULL,
  activates_at TEXT NOT NULL,
  approved_by TEXT,
  revoked_by TEXT
);

CREATE TABLE plan (
  name TEXT PRIMARY KEY NOT NULL,
  credit_budget INTEGER NOT NULL,
  request_quota INTEGER NOT NULL,
  max_cost_class TEXT NOT NULL,
  soft_threshold REAL NOT NULL,
  allowed_capabilities TEXT NOT NULL,
  status TEXT NOT NULL
);

CREATE TABLE plan_version (
  plan_id TEXT NOT NULL,
  version INTEGER NOT NULL,
  display_name TEXT NOT NULL,
  capabilities TEXT NOT NULL,
  max_cost_class TEXT NOT NULL,
  concurrency_limit INTEGER NOT NULL,
  max_allowance_per_month INTEGER NOT NULL,
  status TEXT NOT NULL,
  published_by TEXT NOT NULL,
  assertion_sha256 TEXT NOT NULL,
  PRIMARY KEY (plan_id, version)
);

CREATE TABLE platform_alert (
  alert_key TEXT PRIMARY KEY NOT NULL,
  code TEXT NOT NULL,
  severity TEXT NOT NULL,
  first_at TEXT NOT NULL,
  last_at TEXT NOT NULL,
  count INTEGER NOT NULL,
  send_state TEXT NOT NULL,
  next_send_at TEXT,
  resolved_at TEXT
);

CREATE TABLE platform_counter (
  counter_id TEXT PRIMARY KEY NOT NULL,
  dimension_set TEXT NOT NULL,
  time_bucket TEXT NOT NULL,
  count INTEGER NOT NULL
);

CREATE TABLE routing_policy (
  policy_id TEXT NOT NULL,
  version TEXT NOT NULL,
  content_pointer TEXT NOT NULL,
  active_from TEXT NOT NULL,
  activated_by TEXT NOT NULL, canary_installation_ids TEXT, status TEXT NOT NULL DEFAULT 'published',
  PRIMARY KEY (policy_id, version)
);

CREATE TABLE service_key (
  kid TEXT PRIMARY KEY NOT NULL,
  service TEXT NOT NULL,
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

CREATE TABLE token_contract (
  ver TEXT PRIMARY KEY NOT NULL,
  added_at TEXT NOT NULL,
  retired_at TEXT,
  changed_by TEXT NOT NULL
);

CREATE TABLE transfer (
  transfer_id TEXT PRIMARY KEY NOT NULL,
  org_id TEXT NOT NULL,
  from_installation_id TEXT NOT NULL,
  to_installation_id TEXT NOT NULL,
  reason TEXT NOT NULL,
  assertion_sha256 TEXT NOT NULL,
  package TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE transfer_step (
  transfer_id TEXT NOT NULL,
  step TEXT NOT NULL,
  receipt TEXT NOT NULL,
  applied_at TEXT NOT NULL,
  PRIMARY KEY (transfer_id, step),
  FOREIGN KEY (transfer_id) REFERENCES transfer (transfer_id)
);

CREATE TABLE "usage_event" (
  usage_event_id TEXT PRIMARY KEY NOT NULL,
  installation_id TEXT NOT NULL,
  term_id TEXT NOT NULL,
  request_id TEXT,
  quota_weight INTEGER NOT NULL,
  tokens INTEGER NOT NULL,
  cost REAL NOT NULL,
  recorded_at TEXT NOT NULL,
  FOREIGN KEY (installation_id) REFERENCES installation (installation_id),
  FOREIGN KEY (request_id) REFERENCES ai_request (request_id) ON DELETE SET NULL
);

CREATE TABLE usage_rollup (
  rollup_id TEXT PRIMARY KEY NOT NULL,
  dimensions TEXT NOT NULL,
  request_count INTEGER NOT NULL,
  tokens INTEGER NOT NULL,
  cost REAL NOT NULL
, quota_weight INTEGER NOT NULL DEFAULT 0);
