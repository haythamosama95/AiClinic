function hexToRgb(hex: string): [number, number, number] {
  const normalized = hex.replace('#', '')
  const value =
    normalized.length === 3
      ? normalized
        .split('')
        .map((c) => c + c)
        .join('')
      : normalized
  const num = Number.parseInt(value, 16)
  return [(num >> 16) & 255, (num >> 8) & 255, num & 255]
}

function relativeLuminance([r, g, b]: [number, number, number]): number {
  const [rs, gs, bs] = [r, g, b].map((c) => {
    const s = c / 255
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4
  })
  return 0.2126 * rs + 0.7152 * gs + 0.0722 * bs
}

export function contrastRatio(foreground: string, background: string): number {
  const l1 = relativeLuminance(hexToRgb(foreground))
  const l2 = relativeLuminance(hexToRgb(background))
  const lighter = Math.max(l1, l2)
  const darker = Math.min(l1, l2)
  return (lighter + 0.05) / (darker + 0.05)
}

export function formatContrast(ratio: number): string {
  return `${ratio.toFixed(2)}:1`
}

export function meetsAA(ratio: number, large = false): boolean {
  return large ? ratio >= 3 : ratio >= 4.5
}
