ALTER TABLE paymob_intention ADD COLUMN return_url TEXT NOT NULL DEFAULT '';
ALTER TABLE paymob_intention ADD COLUMN notify_url TEXT NOT NULL DEFAULT '';