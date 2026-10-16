export type DurationScale = "staging";

export type DurationUnit = "month" | "day";

const MS_PER_DAY = 24 * 60 * 60 * 1000;
const STAGING_MS_PER_MONTH = 30 * 60 * 1000;
const STAGING_MS_PER_DAY = 60 * 1000;

function addMonthsUtc(start: Date, count: number): Date {
  const year = start.getUTCFullYear();
  const month = start.getUTCMonth();
  const day = start.getUTCDate();
  const hours = start.getUTCHours();
  const minutes = start.getUTCMinutes();
  const seconds = start.getUTCSeconds();
  const milliseconds = start.getUTCMilliseconds();

  let targetYear = year;
  let targetMonth = month + count;
  while (targetMonth > 11) {
    targetMonth -= 12;
    targetYear += 1;
  }
  while (targetMonth < 0) {
    targetMonth += 12;
    targetYear -= 1;
  }

  const lastDayOfTargetMonth = new Date(
    Date.UTC(targetYear, targetMonth + 1, 0),
  ).getUTCDate();
  const targetDay = Math.min(day, lastDayOfTargetMonth);

  return new Date(
    Date.UTC(
      targetYear,
      targetMonth,
      targetDay,
      hours,
      minutes,
      seconds,
      milliseconds,
    ),
  );
}

export function addDuration(
  startIso: string,
  unit: DurationUnit,
  count: number,
  scale?: DurationScale,
): string {
  const start = new Date(startIso);
  if (Number.isNaN(start.getTime())) {
    throw new RangeError(`Invalid ISO timestamp: ${startIso}`);
  }

  if (scale === "staging") {
    const deltaMs =
      unit === "month"
        ? count * STAGING_MS_PER_MONTH
        : count * STAGING_MS_PER_DAY;
    return new Date(start.getTime() + deltaMs).toISOString();
  }

  if (unit === "day") {
    return new Date(start.getTime() + count * MS_PER_DAY).toISOString();
  }

  return addMonthsUtc(start, count).toISOString();
}
