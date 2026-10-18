-- R3-C5: fence batched work outcomes with an owner token, not only a lease time.
-- Give pre-migration live leases an unguessable token. Their old owners cannot
-- present it and the lease remains unavailable until its existing deadline.
ALTER TABLE work ADD COLUMN lease_token TEXT;

UPDATE work
SET lease_token = lower(hex(randomblob(16)))
WHERE lease_until IS NOT NULL;

CREATE UNIQUE INDEX work_lease_token_unique
  ON work (lease_token)
  WHERE lease_token IS NOT NULL;
