export type CommandTone = 'lifecycle' | 'destructive' | 'probe' | 'enroll'

export interface CommandFailure {
  status: number
  error: string
  trigger: string
}

export function cardToneClass(tone: CommandTone): string {
  return `cmd-card--${tone}`
}

export function panelToneClass(tone: CommandTone): string {
  return `cmd-panel--${tone}`
}

export function journeyCommandTone(operation: {
  destructive?: boolean
  auth: string
}): CommandTone {
  if (operation.destructive) {
    return 'destructive'
  }
  if (operation.auth === 'aat') {
    return 'probe'
  }
  return 'lifecycle'
}

export function stage1CommandTone(operation: {
  id: string
  auth: string
}): CommandTone {
  if (operation.auth === 'aat') {
    return 'probe'
  }
  return 'lifecycle'
}

export function stage3CommandTone(operation: {
  id: string
  destructive?: boolean
  auth: string
}): CommandTone {
  if (operation.destructive) {
    return 'destructive'
  }
  if (operation.auth === 'aat') {
    return 'probe'
  }
  if (operation.id === 'enroll') {
    return 'enroll'
  }
  return 'lifecycle'
}
