-- R6-PT1: pin the exact source route generation and epoch included in an export.
CREATE TABLE transfer_route_manifest (
  transfer_id TEXT NOT NULL,
  grant_id TEXT NOT NULL,
  source_epoch INTEGER NOT NULL CHECK (source_epoch > 0),
  source_generation INTEGER NOT NULL CHECK (source_generation > 0),
  PRIMARY KEY (transfer_id, grant_id),
  FOREIGN KEY (transfer_id) REFERENCES transfer (transfer_id),
  FOREIGN KEY (grant_id) REFERENCES live_value_route (grant_id)
);

-- Keep ambiguous historical exports held for operator adjudication. These rows
-- contain only route/control identity and a bounded reason code.
CREATE TABLE transfer_route_quarantine (
  transfer_id TEXT NOT NULL,
  grant_id TEXT NOT NULL DEFAULT '',
  reason TEXT NOT NULL CHECK (reason IN (
    'invalid_export_package',
    'missing_origin_route',
    'route_not_at_authorized_source'
  )),
  created_at TEXT NOT NULL,
  PRIMARY KEY (transfer_id, grant_id),
  FOREIGN KEY (transfer_id) REFERENCES transfer (transfer_id)
);

-- A manifest is backfilled only when the retained DO export response and its
-- receipt exist and the exact source-side route remains moving for this transfer.
-- Epoch and generation come from that route row itself; no lagging claim ledger,
-- current binding guess, or destination-generation arithmetic is used.
INSERT OR IGNORE INTO transfer_route_manifest (
  transfer_id, grant_id, source_epoch, source_generation
)
SELECT t.transfer_id,
       json_extract(item.value, '$.origin_grant_id'),
       r.binding_epoch,
       r.generation
FROM transfer t
JOIN transfer_step s ON s.transfer_id = t.transfer_id AND s.step = 'transfer_out'
JOIN json_each(CASE WHEN json_valid(t.package) THEN t.package ELSE '[]' END) item
JOIN live_value_route r ON r.grant_id = json_extract(item.value, '$.origin_grant_id')
WHERE t.package IS NOT NULL AND json_valid(t.package)
  AND json_type(t.package) = 'array'
  AND json_valid(s.receipt)
  AND json_type(item.value, '$.origin_grant_id') = 'text'
  AND r.org_id = t.org_id
  AND r.installation_id = t.from_installation_id
  AND r.binding_epoch > 0
  AND r.state = 'moving'
  AND r.transfer_id = t.transfer_id
  AND r.generation > 0
  AND NOT EXISTS (
    SELECT 1 FROM transfer_step imported
    WHERE imported.transfer_id = t.transfer_id AND imported.step = 'transfer_in'
  );

-- Invalid packages or origins that cannot be tied to an exact moving source
-- route are quarantined. Missing manifest rows then fail closed at transfer-in.
INSERT OR IGNORE INTO transfer_route_quarantine (transfer_id, grant_id, reason, created_at)
SELECT t.transfer_id, '', 'invalid_export_package', s.applied_at
FROM transfer t
JOIN transfer_step s ON s.transfer_id = t.transfer_id AND s.step = 'transfer_out'
WHERE (t.package IS NULL OR NOT json_valid(t.package)
       OR json_type(CASE WHEN json_valid(t.package) THEN t.package ELSE 'null' END) <> 'array'
       OR NOT json_valid(s.receipt))
  AND NOT EXISTS (
    SELECT 1 FROM transfer_step imported
    WHERE imported.transfer_id = t.transfer_id AND imported.step = 'transfer_in'
  );

INSERT OR IGNORE INTO transfer_route_quarantine (transfer_id, grant_id, reason, created_at)
SELECT t.transfer_id, '', 'missing_origin_route', s.applied_at
FROM transfer t
JOIN transfer_step s ON s.transfer_id = t.transfer_id AND s.step = 'transfer_out'
JOIN json_each(CASE WHEN json_valid(t.package) AND json_type(t.package) = 'array'
                    THEN t.package ELSE '[]' END) item
WHERE COALESCE(json_type(item.value, '$.origin_grant_id'), '') <> 'text'
  AND NOT EXISTS (
    SELECT 1 FROM transfer_step imported
    WHERE imported.transfer_id = t.transfer_id AND imported.step = 'transfer_in'
  );

INSERT OR IGNORE INTO transfer_route_quarantine (transfer_id, grant_id, reason, created_at)
SELECT t.transfer_id,
       json_extract(item.value, '$.origin_grant_id'),
       'route_not_at_authorized_source',
       s.applied_at
FROM transfer t
JOIN transfer_step s ON s.transfer_id = t.transfer_id AND s.step = 'transfer_out'
JOIN json_each(CASE WHEN json_valid(t.package) AND json_type(t.package) = 'array'
                    THEN t.package ELSE '[]' END) item
WHERE json_type(item.value, '$.origin_grant_id') = 'text'
  AND NOT EXISTS (
    SELECT 1 FROM live_value_route r
    WHERE r.grant_id = json_extract(item.value, '$.origin_grant_id')
      AND r.org_id = t.org_id
      AND r.installation_id = t.from_installation_id
      AND r.binding_epoch > 0
      AND r.state = 'moving'
      AND r.transfer_id = t.transfer_id
      AND r.generation > 0
  )
  AND NOT EXISTS (
    SELECT 1 FROM transfer_step imported
    WHERE imported.transfer_id = t.transfer_id AND imported.step = 'transfer_in'
  );
