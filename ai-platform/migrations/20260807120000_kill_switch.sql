-- I2: durable kill-switch rows (§7.3).
CREATE TABLE kill_switch (
  scope TEXT NOT NULL,
  target TEXT NOT NULL,
  active INTEGER NOT NULL,
  changed_at TEXT NOT NULL,
  changed_by TEXT NOT NULL,
  PRIMARY KEY (scope, target)
);
