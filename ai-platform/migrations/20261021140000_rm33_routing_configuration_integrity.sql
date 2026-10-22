-- RM33 (R8-ROUTE1): routing policy content integrity.
-- Forward-only. content_sha256 records the digest of the stored document bytes
-- so publication and serving can detect content drift. Nullable: existing rows
-- have no recorded digest and are intentionally not backfilled in this step.
ALTER TABLE routing_policy ADD COLUMN content_sha256 TEXT;
