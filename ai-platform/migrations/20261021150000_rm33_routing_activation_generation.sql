-- RM33 (R8-ROLLBACK1): routing activation generation and predecessor record.
-- Forward-only. generation fences promote/rollback transitions. The predecessor
-- record names the version a rollback may restore only when predecessor_state
-- is 'known'. Existing policies are seeded as 'unknown': their historical
-- predecessor is not recoverable from publication time and is never guessed.
CREATE TABLE routing_policy_activation (
  policy_id TEXT PRIMARY KEY,
  generation INTEGER NOT NULL DEFAULT 0,
  active_version TEXT,
  predecessor_version TEXT,
  predecessor_state TEXT NOT NULL DEFAULT 'unknown'
    CHECK (predecessor_state IN ('unknown', 'none', 'known'))
);

INSERT INTO routing_policy_activation
  (policy_id, generation, active_version, predecessor_version, predecessor_state)
SELECT p.policy_id,
       0,
       (SELECT a.version FROM routing_policy a
         WHERE a.policy_id = p.policy_id AND a.status = 'active' LIMIT 1),
       NULL,
       'unknown'
FROM (SELECT DISTINCT policy_id FROM routing_policy) p;
