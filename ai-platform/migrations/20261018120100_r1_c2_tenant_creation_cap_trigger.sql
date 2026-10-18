-- R1-C2: the authoritative first-tenant-creation cap (50 epoch-1 bindings in
-- the 24 hours before the new row's created_at, strict > cutoff). The trigger
-- runs inside the same transaction as the insert, so a rejected insert rolls
-- back the whole installation+binding batch. Timestamps use the code's
-- normalized UTC millisecond format.
CREATE TRIGGER tenant_creation_cap_guard
BEFORE INSERT ON tenant_binding
WHEN NEW.epoch = 1
BEGIN
  SELECT RAISE(ABORT, 'tenant_creation_cap')
  WHERE (
    SELECT COUNT(*)
    FROM tenant_binding
    WHERE epoch = 1
      AND created_at > strftime('%Y-%m-%dT%H:%M:%fZ', NEW.created_at, '-24 hours')
  ) >= 50;
END;