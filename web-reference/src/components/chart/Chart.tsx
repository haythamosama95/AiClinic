import { cn } from '@/lib/cn'

/** Categorical palette from design tokens — teal + neutrals + status hues */
export const chartPalette = [
  'var(--action-primary)',
  'var(--status-info-fg)',
  'var(--status-success-fg)',
  'var(--status-warning-fg)',
  'var(--text-tertiary)',
  'var(--action-ai)',
] as const

export type ChartSeries = {
  label: string
  data: number[]
  color?: string
}

export type AppChartProps = {
  type: 'line' | 'area' | 'bar' | 'stacked-bar' | 'donut' | 'sparkline'
  series: ChartSeries[]
  labels?: string[]
  height?: number
  className?: string
  'aria-label'?: string
}

function normalizeData(data: number[], width: number, height: number, padding = 8) {
  const max = Math.max(...data, 1)
  const min = Math.min(...data, 0)
  const range = max - min || 1
  const innerW = width - padding * 2
  const innerH = height - padding * 2

  return data.map((v, i) => ({
    x: padding + (i / Math.max(data.length - 1, 1)) * innerW,
    y: padding + innerH - ((v - min) / range) * innerH,
    value: v,
  }))
}

function Sparkline({ data, color, width = 80, height = 24 }: { data: number[]; color: string; width?: number; height?: number }) {
  const points = normalizeData(data, width, height, 2)
  const path = points.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x} ${p.y}`).join(' ')

  return (
    <svg width={width} height={height} aria-hidden>
      <path d={path} fill="none" stroke={color} strokeWidth={1.5} strokeLinecap="round" />
    </svg>
  )
}

function LineChart({ series, labels, height, ariaLabel }: { series: ChartSeries[]; labels?: string[]; height: number; ariaLabel: string }) {
  const width = 400
  const padding = 24

  return (
    <div>
      <svg
        width="100%"
        viewBox={`0 0 ${width} ${height}`}
        role="img"
        aria-label={ariaLabel}
        className="text-border-subtle"
      >
        {[0.25, 0.5, 0.75].map((pct) => (
          <line
            key={pct}
            x1={padding}
            x2={width - padding}
            y1={padding + (height - padding * 2) * pct}
            y2={padding + (height - padding * 2) * pct}
            stroke="currentColor"
            strokeWidth={0.5}
            opacity={0.5}
          />
        ))}
        {series.map((s, si) => {
          const points = normalizeData(s.data, width, height, padding)
          const path = points.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x} ${p.y}`).join(' ')
          const color = s.color ?? chartPalette[si % chartPalette.length]
          return (
            <g key={s.label}>
              <path d={path} fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" />
              {points.map((p, i) => (
                <circle key={i} cx={p.x} cy={p.y} r={3} fill={color} />
              ))}
            </g>
          )
        })}
      </svg>
      <table className="sr-only">
        <caption>{ariaLabel}</caption>
        <thead>
          <tr>
            <th>Label</th>
            {labels?.map((l) => <th key={l}>{l}</th>)}
          </tr>
        </thead>
        <tbody>
          {series.map((s) => (
            <tr key={s.label}>
              <th>{s.label}</th>
              {s.data.map((v, i) => (
                <td key={i}>{v}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
      <div className="mt-2 flex flex-wrap gap-4">
        {series.map((s, i) => (
          <div key={s.label} className="flex items-center gap-1.5 text-caption text-text-secondary">
            <span
              className="size-2 rounded-full"
              style={{ backgroundColor: s.color ?? chartPalette[i % chartPalette.length] }}
            />
            {s.label}
          </div>
        ))}
      </div>
    </div>
  )
}

function BarChart({ series, height, stacked, ariaLabel }: { series: ChartSeries[]; height: number; stacked?: boolean; ariaLabel: string }) {
  const width = 400
  const padding = 24
  const count = series[0]?.data.length ?? 0
  const barGroupWidth = (width - padding * 2) / count
  const max = stacked
    ? Math.max(...Array.from({ length: count }, (_, i) => series.reduce((s, ser) => s + (ser.data[i] ?? 0), 0)), 1)
    : Math.max(...series.flatMap((s) => s.data), 1)

  return (
    <div>
      <svg width="100%" viewBox={`0 0 ${width} ${height}`} role="img" aria-label={ariaLabel}>
        {Array.from({ length: count }).map((_, i) => {
          const x = padding + i * barGroupWidth + barGroupWidth * 0.15
          const w = barGroupWidth * 0.7 / (stacked ? 1 : series.length)
          let yOffset = height - padding

          return (
            <g key={i}>
              {series.map((s, si) => {
                const value = s.data[i] ?? 0
                const barH = ((value / max) * (height - padding * 2))
                yOffset -= barH
                const color = s.color ?? chartPalette[si % chartPalette.length]
                const bx = stacked ? x : x + si * w
                const by = stacked ? yOffset : height - padding - barH
                return (
                  <rect
                    key={s.label}
                    x={bx}
                    y={by}
                    width={w}
                    height={barH}
                    fill={color}
                    rx={2}
                  />
                )
              })}
            </g>
          )
        })}
      </svg>
    </div>
  )
}

function DonutChart({ series, height, ariaLabel }: { series: ChartSeries[]; height: number; ariaLabel: string }) {
  const data = series[0]?.data ?? []
  const labels = series.map((s) => s.label)
  const total = data.reduce((a, b) => a + b, 0) || 1
  const cx = height / 2
  const cy = height / 2
  const r = height / 2 - 16
  const inner = r * 0.55
  let angle = -90

  const slices = data.map((value, i) => {
    const pct = value / total
    const sweep = pct * 360
    const start = angle
    angle += sweep
    const color = chartPalette[i % chartPalette.length]
    const startRad = (start * Math.PI) / 180
    const endRad = ((start + sweep) * Math.PI) / 180
    const x1 = cx + r * Math.cos(startRad)
    const y1 = cy + r * Math.sin(startRad)
    const x2 = cx + r * Math.cos(endRad)
    const y2 = cy + r * Math.sin(endRad)
    const large = sweep > 180 ? 1 : 0
    const d = `M ${cx} ${cy} L ${x1} ${y1} A ${r} ${r} 0 ${large} 1 ${x2} ${y2} Z`
    return { d, color, label: labels[i], value }
  })

  return (
    <div className="flex items-center gap-6">
      <svg width={height} height={height} role="img" aria-label={ariaLabel}>
        {slices.map((s) => (
          <path key={s.label} d={s.d} fill={s.color} />
        ))}
        <circle cx={cx} cy={cy} r={inner} fill="var(--surface-default)" />
      </svg>
      <ul className="space-y-1 text-caption text-text-secondary">
        {slices.map((s) => (
          <li key={s.label} className="flex items-center gap-2">
            <span className="size-2 rounded-full" style={{ backgroundColor: s.color }} />
            {s.label}: <span className="tabular-nums">{s.value}</span>
          </li>
        ))}
      </ul>
    </div>
  )
}

export function AppChart({
  type,
  series,
  labels,
  height = 200,
  className,
  'aria-label': ariaLabel = 'Chart',
}: AppChartProps) {
  if (type === 'sparkline' && series[0]) {
    return (
      <Sparkline
        data={series[0].data}
        color={series[0].color ?? chartPalette[0]}
      />
    )
  }

  return (
    <div className={cn('rounded-lg border border-border-default bg-surface-default p-4', className)}>
      {type === 'line' || type === 'area' ? (
        <LineChart series={series} labels={labels} height={height} ariaLabel={ariaLabel} />
      ) : null}
      {type === 'bar' ? (
        <BarChart series={series} height={height} ariaLabel={ariaLabel} />
      ) : null}
      {type === 'stacked-bar' ? (
        <BarChart series={series} height={height} stacked ariaLabel={ariaLabel} />
      ) : null}
      {type === 'donut' ? (
        <DonutChart series={series} height={height} ariaLabel={ariaLabel} />
      ) : null}
    </div>
  )
}

export { Sparkline as ChartSparkline }
