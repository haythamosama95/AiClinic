import type { ReactNode } from 'react'
import { cn } from '@/lib/cn'
import { CommandBar } from '@/components/navigation/CommandBar'

export type AppShellProps = {
  sidebar: ReactNode
  topBar: ReactNode
  children: ReactNode
  commandBar?: ReactNode
  className?: string
  contentClassName?: string
  fullWidth?: boolean
}

export function AppShell({
  sidebar,
  topBar,
  children,
  commandBar,
  className,
  contentClassName,
  fullWidth = false,
}: AppShellProps) {
  return (
    <div className={cn('flex h-full min-h-0 bg-surface-canvas', className)}>
      {sidebar}
      <div className="flex min-w-0 flex-1 flex-col">
        {topBar}
        <main
          id="main"
          className={cn(
            'flex-1 overflow-y-auto',
            contentClassName,
          )}
        >
          <div
            className={cn(
              'mx-auto w-full py-6',
              fullWidth ? 'px-6 sm:px-8 lg:px-10' : 'max-w-6xl px-6',
            )}
          >
            {children}
          </div>
        </main>
      </div>
      {commandBar}
    </div>
  )
}

/** Convenience shell with built-in CommandBar portal */
export function AppShellWithCommand({
  sidebar,
  topBar,
  children,
  commandItems,
  className,
  contentClassName,
  fullWidth,
}: Omit<AppShellProps, 'commandBar'> & {
  commandItems?: React.ComponentProps<typeof CommandBar>['items']
  recentItems?: React.ComponentProps<typeof CommandBar>['recentItems']
}) {
  return (
    <AppShell
      sidebar={sidebar}
      topBar={topBar}
      className={className}
      contentClassName={contentClassName}
      fullWidth={fullWidth}
      commandBar={
        <CommandBar
          items={commandItems ?? []}
        />
      }
    >
      {children}
    </AppShell>
  )
}
