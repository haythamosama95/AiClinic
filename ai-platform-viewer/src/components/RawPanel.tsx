interface RawPanelProps {
  title: string
  value: string
}

export function RawPanel({ title, value }: RawPanelProps) {
  return (
    <div className="raw-panel">
      <h4 className="raw-panel__title">{title}</h4>
      <textarea
        className="raw-panel__output"
        readOnly
        spellCheck={false}
        value={value}
        aria-label={`${title} raw`}
      />
    </div>
  )
}
