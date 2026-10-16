/** Production retry delay: wall-clock sleep via `setTimeout`. */
export function wallClockSleeper(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}
