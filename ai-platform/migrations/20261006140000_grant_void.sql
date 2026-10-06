CREATE TABLE grant_void (
  grant_id TEXT PRIMARY KEY NOT NULL,
  reason TEXT NOT NULL,
  source TEXT NOT NULL,
  evidence_sha256 TEXT NOT NULL,
  at TEXT NOT NULL
);

CREATE TRIGGER grant_void_no_update
BEFORE UPDATE ON grant_void
BEGIN
  SELECT RAISE(ABORT, 'grant_void is append-only');
END;

CREATE TRIGGER grant_void_no_delete
BEFORE DELETE ON grant_void
BEGIN
  SELECT RAISE(ABORT, 'grant_void is append-only');
END;
