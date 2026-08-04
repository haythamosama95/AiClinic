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

CREATE TABLE control_audit (
  audit_id TEXT PRIMARY KEY NOT NULL,
  operator_id TEXT NOT NULL,
  action TEXT NOT NULL,
  target TEXT NOT NULL,
  before_pointer TEXT,
  after_pointer TEXT,
  recorded_at TEXT NOT NULL
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
  status TEXT NOT NULL,
  FOREIGN KEY (installation_id) REFERENCES installation (installation_id)
);

CREATE TABLE installation (
  installation_id TEXT PRIMARY KEY NOT NULL,
  org_id TEXT NOT NULL,
  display_name TEXT NOT NULL,
  status TEXT NOT NULL,
  region TEXT NOT NULL,
  enrolled_at TEXT NOT NULL
);

CREATE TABLE installation_key (
  key_id TEXT PRIMARY KEY NOT NULL,
  installation_id TEXT NOT NULL,
  public_key TEXT NOT NULL,
  algorithm TEXT NOT NULL,
  valid_from TEXT NOT NULL,
  valid_until TEXT,
  revoked_at TEXT,
  FOREIGN KEY (installation_id) REFERENCES installation (installation_id)
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
  activated_by TEXT NOT NULL, canary_installation_ids TEXT,
  PRIMARY KEY (policy_id, version)
);

CREATE TABLE token_contract (
  ver TEXT PRIMARY KEY NOT NULL,
  added_at TEXT NOT NULL,
  retired_at TEXT,
  changed_by TEXT NOT NULL
);

CREATE TABLE usage_event (
  usage_event_id TEXT PRIMARY KEY NOT NULL,
  installation_id TEXT NOT NULL,
  period TEXT NOT NULL,
  request_id TEXT NOT NULL,
  quota_weight INTEGER NOT NULL,
  tokens INTEGER NOT NULL,
  cost REAL NOT NULL,
  recorded_at TEXT NOT NULL,
  FOREIGN KEY (installation_id) REFERENCES installation (installation_id),
  FOREIGN KEY (request_id) REFERENCES ai_request (request_id)
);

CREATE TABLE usage_rollup (
  rollup_id TEXT PRIMARY KEY NOT NULL,
  dimensions TEXT NOT NULL,
  request_count INTEGER NOT NULL,
  tokens INTEGER NOT NULL,
  cost REAL NOT NULL
);
