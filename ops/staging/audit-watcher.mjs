import { readFile } from "node:fs/promises";

// Hourly audit-log watcher (P8.1). Classifies audit-read entries:
// deploy, secret, d1_export, access_policy. Fixture mode does not read the token.

const ALERT_CLASSES = new Set(["deploy", "secret", "d1_export", "access_policy"]);

async function main() {
  const fixturePath = process.argv[2];
  if (!fixturePath) {
    process.exit(1);
  }

  const fixture = JSON.parse(await readFile(fixturePath, "utf8"));
  const events = fixture.events ?? [];

  for (const event of events) {
    if (ALERT_CLASSES.has(event.class)) {
      console.log("AL-21");
    }
  }
}

main().catch(() => {
  process.exit(1);
});
