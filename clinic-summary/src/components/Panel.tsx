import type { ReactNode } from "react";

interface PanelProps {
  title: string;
  description?: string;
  count?: number;
  countLabel?: string;
  children: ReactNode;
}

export function Panel({
  title,
  description,
  count,
  countLabel,
  children,
}: PanelProps) {
  return (
    <section className="flex flex-col overflow-hidden rounded-2xl border border-border bg-surface shadow-panel">
      <header className="border-b border-border px-5 py-4">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h2 className="font-display text-base font-semibold tracking-tight text-ink">
              {title}
            </h2>
            {description && (
              <p className="mt-0.5 text-sm text-muted">{description}</p>
            )}
          </div>
          {count !== undefined && (
            <div className="shrink-0 text-right">
              <p className="font-display text-2xl font-semibold tabular-nums text-brand">
                {count}
              </p>
              {countLabel && (
                <p className="text-xs font-medium uppercase tracking-wide text-muted">
                  {countLabel}
                </p>
              )}
            </div>
          )}
        </div>
      </header>
      <div className="flex-1 p-4">{children}</div>
    </section>
  );
}
