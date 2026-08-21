-- One entitlement row per installation (audit 5.9).
-- CREATE UNIQUE INDEX inspects existing rows and fails the migration if any
-- installation_id is duplicated, then enforces uniqueness going forward so
-- handleEntitle cannot silently multi-update a duplicate row set.
CREATE UNIQUE INDEX idx_entitlement_installation_id
  ON entitlement (installation_id);
