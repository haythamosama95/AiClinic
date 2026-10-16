import { readFile } from "node:fs/promises";

// External heartbeat monitor (P8.1). Expected pings to HEARTBEAT_URL:
// - ABO minute (abo/src/worker.ts scheduled * * * * * → pingHeartbeat)
// - Platform 5-minute (ai-platform scheduled */5 * * * * → pingPlatformHeartbeat)
// - ABO daily digest (abo/src/worker.ts scheduled 0 6 * * * → pingHeartbeat)

const EXPECTED_PINGS = ["abo_minute", "platform_5min", "abo_daily_digest"];

async function main() {
  const fixturePath = process.argv[2];
  if (!fixturePath) {
    process.exit(1);
  }

  const fixture = JSON.parse(await readFile(fixturePath, "utf8"));
  const received = new Set(fixture.received_pings ?? []);

  for (const ping of EXPECTED_PINGS) {
    if (!received.has(ping)) {
      console.log("AL-21");
      return;
    }
  }
}

main().catch(() => {
  process.exit(1);
});
