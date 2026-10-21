-- R9-AO7 / R6-O1: one accepted payout import per provider and exact file hash. An exact retry of
-- the same file resolves to the stored import instead of creating another. Existing rows are not
-- altered or deleted. If staging holds duplicate (provider_id, file_sha256) rows, this migration
-- fails closed and the duplicates must be adjudicated under D-5 before it is re-applied.
CREATE UNIQUE INDEX payout_import_provider_file
  ON payout_import (provider_id, file_sha256);
