-- RM28 recovery can reconstruct a provider-created intention from immutable
-- order/correlation facts, but the provider secret is deliberately not
-- exported. Keep the operational attempt in the existing created state while
-- allowing that one field to remain NULL after recovery.
CREATE TABLE paymob_intention_attempt_replacement (
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
      AND expires_at IS NOT NULL)
    OR state <> 'created'
  )
);

INSERT INTO paymob_intention_attempt_replacement (
  checkout_id, attempt_no, state, lease_token, lease_until, special_reference,
  intention_id, order_id, client_secret, expires_at, started_at, finished_at
)
SELECT checkout_id, attempt_no, state, lease_token, lease_until, special_reference,
       intention_id, order_id, client_secret, expires_at, started_at, finished_at
FROM paymob_intention_attempt;

DROP TABLE paymob_intention_attempt;
ALTER TABLE paymob_intention_attempt_replacement RENAME TO paymob_intention_attempt;

CREATE INDEX paymob_intention_attempt_order_id
  ON paymob_intention_attempt (order_id)
  WHERE order_id IS NOT NULL;
