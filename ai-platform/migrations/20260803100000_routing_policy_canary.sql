-- J3: additive canary_installation_ids on routing_policy for cohort-scoped policy activation.
ALTER TABLE routing_policy ADD COLUMN canary_installation_ids TEXT;
