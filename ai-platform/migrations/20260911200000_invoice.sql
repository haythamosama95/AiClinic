CREATE TABLE invoice (
  installation_id TEXT NOT NULL,
  period TEXT NOT NULL,
  credits_consumed INTEGER NOT NULL,
  credit_price_version TEXT NOT NULL,
  total REAL NOT NULL,
  status TEXT NOT NULL,
  issued_at TEXT NOT NULL,
  PRIMARY KEY (installation_id, period)
);
