-- RM09 R3-C2 / R3-M2. Give checkout admission a durable timestamp and make
-- each outbound Paymob intention attempt addressable before the HTTP call.
ALTER TABLE checkout ADD COLUMN created_at TEXT;
-- Historical rows did not persist the coverage decision. Keep it unknown;
-- only newly admitted checkouts can store these values accurately.
ALTER TABLE checkout ADD COLUMN coverage_starts TEXT;
ALTER TABLE checkout ADD COLUMN projected_start TEXT;

-- checkout is append-only after creation. Temporarily remove only the update
-- guard for this schema backfill, then restore the identical guard before the
-- migration continues. D1 applies a migration transactionally.
DROP TRIGGER checkout_abort_update;

UPDATE checkout
SET created_at = COALESCE(
  (
    SELECT fl.created_at
    FROM fact_log fl
    WHERE fl."table" = 'checkout' AND fl.key = checkout.checkout_id
    ORDER BY fl.fact_seq ASC
    LIMIT 1
  ),
  (
    SELECT ce.at
    FROM checkout_event ce
    WHERE ce.checkout_id = checkout.checkout_id AND ce.kind = 'opened'
    ORDER BY ce.at ASC
    LIMIT 1
  ),
  -- Checkout expiry is created_at + 30 minutes. If both immutable records
  -- were lost at the historical insert/fact crash boundary, invert that
  -- persisted invariant rather than dropping the checkout from rate limits.
  strftime('%Y-%m-%dT%H:%M:%fZ', checkout.expires_at, '-30 minutes')
)
WHERE created_at IS NULL;

CREATE TRIGGER checkout_abort_update
BEFORE UPDATE ON checkout
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TABLE paymob_intention_attempt (
  checkout_id TEXT NOT NULL,
  attempt_no INTEGER NOT NULL CHECK (attempt_no > 0),
  state TEXT NOT NULL CHECK (
    state IN ('pending', 'created', 'abandoned_unconfirmed')
  ),
  lease_token TEXT NOT NULL,
  lease_until TEXT NOT NULL,
  special_reference TEXT NOT NULL UNIQUE,
  intention_id TEXT,
  order_id TEXT,
  client_secret TEXT,
  expires_at TEXT,
  started_at TEXT,
  finished_at TEXT,
  PRIMARY KEY (checkout_id, attempt_no),
  FOREIGN KEY (checkout_id) REFERENCES checkout(checkout_id),
  CHECK (
    (state = 'created' AND intention_id IS NOT NULL AND order_id IS NOT NULL
      AND client_secret IS NOT NULL AND expires_at IS NOT NULL)
    OR state <> 'created'
  )
);

CREATE INDEX paymob_intention_attempt_order_id
  ON paymob_intention_attempt (order_id)
  WHERE order_id IS NOT NULL;

-- Attempt state is mutable operational state. Preserve each state transition
-- as an immutable row so ledger replay never inserts multiple snapshots into
-- the attempt table's (checkout_id, attempt_no) primary key.
CREATE TABLE paymob_intention_attempt_event (
  event_key TEXT NOT NULL PRIMARY KEY,
  checkout_id TEXT NOT NULL,
  attempt_no INTEGER NOT NULL,
  state TEXT NOT NULL CHECK (
    state IN ('pending', 'created', 'abandoned_unconfirmed')
  ),
  lease_token TEXT NOT NULL,
  lease_until TEXT NOT NULL,
  special_reference TEXT NOT NULL,
  intention_id TEXT,
  order_id TEXT,
  client_secret TEXT,
  expires_at TEXT,
  started_at TEXT,
  finished_at TEXT,
  event_at TEXT NOT NULL,
  FOREIGN KEY (checkout_id) REFERENCES checkout(checkout_id)
);

CREATE INDEX paymob_intention_attempt_event_attempt
  ON paymob_intention_attempt_event (checkout_id, attempt_no, event_at, event_key);

CREATE TRIGGER paymob_intention_attempt_event_abort_update
BEFORE UPDATE ON paymob_intention_attempt_event
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

CREATE TRIGGER paymob_intention_attempt_event_abort_delete
BEFORE DELETE ON paymob_intention_attempt_event
BEGIN
  SELECT RAISE(ABORT, 'append_only');
END;

-- Preserve the old, already-created single-intention records as attempt 1.
-- The migration event key is intentionally distinct from request-time keys;
-- rebuild can recreate this same event from the legacy fact if it starts from
-- an empty D1 database.
INSERT INTO paymob_intention_attempt_event (
  event_key, checkout_id, attempt_no, state, lease_token, lease_until,
  special_reference, intention_id, order_id, client_secret, expires_at,
  started_at, finished_at, event_at
)
SELECT pi.checkout_id || ':1:created:legacy', pi.checkout_id, 1, 'created',
       'legacy', pi.expires_at, pi.special_reference, pi.intention_id,
       pi.order_id, pi.client_secret, pi.expires_at, c.created_at,
       c.created_at, COALESCE(c.created_at, pi.expires_at)
FROM paymob_intention pi
INNER JOIN checkout c ON c.checkout_id = pi.checkout_id
WHERE NOT EXISTS (
  SELECT 1 FROM paymob_intention_attempt_event e
  WHERE e.checkout_id = pi.checkout_id AND e.attempt_no = 1
);

INSERT INTO paymob_intention_attempt (
  checkout_id, attempt_no, state, lease_token, lease_until,
  special_reference, intention_id, order_id, client_secret, expires_at,
  started_at, finished_at
)
SELECT pi.checkout_id, 1, 'created', 'legacy', pi.expires_at,
       pi.special_reference, pi.intention_id, pi.order_id, pi.client_secret,
       pi.expires_at, c.created_at, c.created_at
FROM paymob_intention pi
INNER JOIN checkout c ON c.checkout_id = pi.checkout_id;

-- An old failed request never returned a redirect. Preserve it as an immutable
-- attempt event, then materialize attempt 1 below. The checkout event timestamp
-- is preferred; old rows without that event fall back to checkout creation.
INSERT INTO paymob_intention_attempt_event (
  event_key, checkout_id, attempt_no, state, lease_token, lease_until,
  special_reference, intention_id, order_id, client_secret, expires_at,
  started_at, finished_at, event_at
)
SELECT c.checkout_id || ':1:abandoned_unconfirmed:legacy', c.checkout_id, 1,
       'abandoned_unconfirmed', 'legacy', c.expires_at, c.reference,
       NULL, NULL, NULL, NULL, c.created_at,
       COALESCE(cs.last_event_at, (SELECT MAX(oe.at) FROM checkout_event oe
         WHERE oe.checkout_id = c.checkout_id AND oe.kind = 'open_failed'),
         c.created_at, c.expires_at),
       COALESCE(cs.last_event_at, (SELECT MAX(oe.at) FROM checkout_event oe
         WHERE oe.checkout_id = c.checkout_id AND oe.kind = 'open_failed'),
         c.created_at, c.expires_at)
FROM checkout c
INNER JOIN checkout_status cs ON cs.checkout_id = c.checkout_id
LEFT JOIN paymob_intention pi ON pi.checkout_id = c.checkout_id
WHERE cs.state = 'open_failed' AND pi.checkout_id IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM paymob_intention_attempt_event e
    WHERE e.checkout_id = c.checkout_id AND e.attempt_no = 1
  );

-- Keep the mutable projection available immediately after migration. It is
-- rebuilt from paymob_intention_attempt_event by rebuildAbo.
INSERT INTO paymob_intention_attempt (
  checkout_id, attempt_no, state, lease_token, lease_until,
  special_reference, started_at, finished_at
)
SELECT c.checkout_id, 1, 'abandoned_unconfirmed', 'legacy', c.expires_at,
       c.reference, c.created_at, c.created_at
FROM checkout c
INNER JOIN checkout_status cs ON cs.checkout_id = c.checkout_id
LEFT JOIN paymob_intention pi ON pi.checkout_id = c.checkout_id
WHERE cs.state = 'open_failed' AND pi.checkout_id IS NULL;
