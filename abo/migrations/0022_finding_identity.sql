-- R9-AO4: one canonical finding per (kind, subject). Existing immutable findings are kept.
-- The representative is the earliest detected finding for each identity, ordered by
-- detected_at and then finding_id. Duplicate findings, facts and resolutions are retained.
CREATE TABLE finding_identity (
  kind TEXT NOT NULL,
  subject TEXT NOT NULL,
  finding_id TEXT NOT NULL,
  PRIMARY KEY (kind, subject)
);

CREATE UNIQUE INDEX finding_identity_finding_id ON finding_identity (finding_id);

INSERT INTO finding_identity (kind, subject, finding_id)
SELECT f.kind, f.subject, f.finding_id
FROM finding f
WHERE f.finding_id = (
  SELECT f2.finding_id
  FROM finding f2
  WHERE f2.kind = f.kind AND f2.subject = f.subject
  ORDER BY f2.detected_at ASC, f2.finding_id ASC
  LIMIT 1
);
