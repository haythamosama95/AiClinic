-- J3 review: explicit routing-policy activation status so publish is non-serving,
-- canary is cohort-scoped, promote is global-active, and rollback restores prior.
-- Also unique live installation/plan grants to prevent activate duplicate-grant races.
ALTER TABLE routing_policy ADD COLUMN status TEXT NOT NULL DEFAULT 'published';

UPDATE routing_policy
SET status = 'canary'
WHERE canary_installation_ids IS NOT NULL;

UPDATE routing_policy
SET status = 'active'
WHERE canary_installation_ids IS NULL
  AND active_from = (
    SELECT MAX(rp.active_from)
    FROM routing_policy AS rp
    WHERE rp.policy_id = routing_policy.policy_id
      AND rp.canary_installation_ids IS NULL
  );

CREATE UNIQUE INDEX IF NOT EXISTS idx_capability_grant_live_installation
  ON capability_grant(scope, capability_id)
  WHERE revoked_at IS NULL AND scope LIKE 'installation:%';

CREATE UNIQUE INDEX IF NOT EXISTS idx_capability_grant_live_plan
  ON capability_grant(scope, capability_id)
  WHERE revoked_at IS NULL AND scope LIKE 'plan:%';
