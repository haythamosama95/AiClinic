function maskToken(value: string): string {
  if (value.length <= 12) return '••••••••'
  return `${value.slice(0, 6)}…${value.slice(-4)}`
}

export function formatTokenPreview(value: string, revealed: boolean): string {
  if (!value) return 'Not loaded'
  return revealed ? value : maskToken(value)
}

export async function copyText(value: string): Promise<void> {
  await navigator.clipboard.writeText(value)
}
