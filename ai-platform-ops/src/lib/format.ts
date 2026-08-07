/** Pretty-print JSON text when valid; otherwise return unchanged. */
export function prettyBody(text: string): string {
  const trimmed = text.trim();
  if (!trimmed) {
    return text;
  }
  try {
    return JSON.stringify(JSON.parse(trimmed), null, 2);
  } catch {
    return text;
  }
}
