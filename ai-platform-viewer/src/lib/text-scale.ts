export const TEXT_SCALE_BASE_PX = 16
export const TEXT_SCALE_STEP_PX = 1
export const TEXT_SCALE_MIN_LEVEL = -2
export const TEXT_SCALE_MAX_LEVEL = 4
export const TEXT_SCALE_DEFAULT_LEVEL = 2

export function rootFontSizePx(level: number): string {
  const clamped = Math.min(
    TEXT_SCALE_MAX_LEVEL,
    Math.max(TEXT_SCALE_MIN_LEVEL, level),
  )
  return `${TEXT_SCALE_BASE_PX + clamped * TEXT_SCALE_STEP_PX}px`
}

export function canIncreaseTextScale(level: number): boolean {
  return level < TEXT_SCALE_MAX_LEVEL
}

export function canDecreaseTextScale(level: number): boolean {
  return level > TEXT_SCALE_MIN_LEVEL
}
