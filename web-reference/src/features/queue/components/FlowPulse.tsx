import { motion, useReducedMotion } from 'motion/react'

type FlowPulseProps = {
  /** 0–1 severity based on max wait time */
  severity: number
  patientCount: number
}

function severityColor(severity: number): string {
  if (severity >= 0.75) return 'var(--status-danger-fg)'
  if (severity >= 0.5) return 'var(--status-warning-fg)'
  return 'var(--action-primary)'
}

export function FlowPulse({ severity, patientCount }: FlowPulseProps) {
  const reducedMotion = useReducedMotion()
  const color = severityColor(severity)
  const fillPercent = Math.min(100, Math.max(8, severity * 100))

  return (
    <div
      className="mb-3"
      role="meter"
      aria-valuenow={Math.round(severity * 100)}
      aria-valuemin={0}
      aria-valuemax={100}
      aria-label="Queue wait severity"
    >
      <div className="mb-1 flex items-center justify-between">
        <span className="queue-heading text-[10px] font-semibold uppercase tracking-widest text-text-secondary">
          Flow Pulse
        </span>
        <span className="queue-mono text-[10px] text-text-secondary">{patientCount} waiting</span>
      </div>
      <div className="relative h-1 overflow-hidden rounded-full bg-border-default">
        <motion.div
          className="absolute inset-y-0 left-0 rounded-full"
          style={{ backgroundColor: color, width: `${fillPercent}%` }}
          initial={false}
          animate={
            reducedMotion
              ? { opacity: 1 }
              : { opacity: [0.7, 1, 0.7], scaleY: [1, 1.3, 1] }
          }
          transition={
            reducedMotion
              ? { duration: 0 }
              : { duration: 2.5, repeat: Infinity, ease: 'easeInOut' }
          }
        />
        {!reducedMotion && (
          <motion.div
            className="absolute inset-y-0 w-8 rounded-full opacity-40"
            style={{
              background: `linear-gradient(90deg, transparent, ${color}, transparent)`,
            }}
            animate={{ left: ['-10%', '110%'] }}
            transition={{ duration: 3, repeat: Infinity, ease: 'linear' }}
          />
        )}
      </div>
    </div>
  )
}
