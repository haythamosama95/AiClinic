CREATE TABLE plan (
  name TEXT PRIMARY KEY NOT NULL,
  credit_budget INTEGER NOT NULL,
  request_quota INTEGER NOT NULL,
  max_cost_class TEXT NOT NULL,
  soft_threshold REAL NOT NULL,
  allowed_capabilities TEXT NOT NULL,
  status TEXT NOT NULL
);

CREATE TABLE credit_price (
  version TEXT PRIMARY KEY NOT NULL,
  price_per_credit REAL NOT NULL,
  currency TEXT NOT NULL,
  active_from TEXT NOT NULL,
  activated_by TEXT NOT NULL
);

ALTER TABLE entitlement ADD COLUMN credit_budget INTEGER NOT NULL DEFAULT 0;
ALTER TABLE entitlement ADD COLUMN max_cost_class TEXT NOT NULL DEFAULT '';
