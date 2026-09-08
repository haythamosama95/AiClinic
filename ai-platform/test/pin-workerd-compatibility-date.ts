import { supportedCompatibilityDate } from "miniflare";

/**
 * Local workerd cannot honor wrangler.toml's production
 * `compatibility_date = "2026-05-03"` and would silently fall back.
 * Pin workers-pool harnesses to the date workerd actually supports, and
 * throw if a caller requests a newer date.
 */
export function pinWorkerdCompatibilityDate(requested?: string): string {
  const date = requested ?? supportedCompatibilityDate;
  if (date > supportedCompatibilityDate) {
    throw new Error(
      `Requested compatibilityDate "${date}" is newer than workerd "${supportedCompatibilityDate}". ` +
        `Miniflare would silently fall back to "${supportedCompatibilityDate}". ` +
        `Pin the harness to "${supportedCompatibilityDate}" or upgrade wrangler/workerd.`,
    );
  }
  return date;
}
