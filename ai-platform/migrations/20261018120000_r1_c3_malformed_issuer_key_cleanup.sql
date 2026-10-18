-- R1-C3: legacy issuer keys whose validity bounds are malformed (unparseable
-- or reversed) are revoked so they can never be treated as unrestricted.
-- Rows are only marked revoked: no replacement dates are guessed and revoked
-- kids are never revived (decision D-5). Operators inventory affected rows and
-- register replacement kids with valid bounds before deploying this cleanup.
UPDATE issuer_key
SET status = 'revoked'
WHERE status IN ('active', 'retiring')
  AND (
    julianday(not_before) IS NULL
    OR julianday(not_after) IS NULL
    OR julianday(not_before) >= julianday(not_after)
  );