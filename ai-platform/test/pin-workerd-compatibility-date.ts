/**
 * Pin each Workers test harness to the compatibility date supported by its
 * locked workerd version. Miniflare 5 no longer exports
 * `supportedCompatibilityDate`, so callers supply the date recorded by their
 * package lockfile. This also lets ABO use its own older Workers runtime.
 */
export function pinWorkerdCompatibilityDate(
  supportedDate: string,
  requested?: string,
): string {
  const date = requested ?? supportedDate;
  if (date > supportedDate) {
    throw new Error(
      `Requested compatibilityDate "${date}" is newer than workerd "${supportedDate}". ` +
        `Miniflare may silently fall back to "${supportedDate}". ` +
        `Pin the harness to "${supportedDate}" or upgrade wrangler/workerd.`,
    );
  }
  return date;
}
