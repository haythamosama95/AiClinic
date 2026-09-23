-- M1 / A17: subscription price, display copy, and grace_days on plan;
-- withdraw credit_price. Forward-only (no down migration).
-- Non-grace NOT NULL columns carry SQLite-required backfill defaults so this
-- ALTER applies over an existing pre-A17 catalogue; operator create/update
-- still rejects empty/invalid values (FR-011).
ALTER TABLE plan ADD COLUMN price_cents INTEGER NOT NULL DEFAULT 0;
ALTER TABLE plan ADD COLUMN currency TEXT NOT NULL DEFAULT '';
ALTER TABLE plan ADD COLUMN display_name TEXT NOT NULL DEFAULT '';
ALTER TABLE plan ADD COLUMN description TEXT NOT NULL DEFAULT '';
ALTER TABLE plan ADD COLUMN grace_days INTEGER NOT NULL DEFAULT 7;

DROP TABLE credit_price;
