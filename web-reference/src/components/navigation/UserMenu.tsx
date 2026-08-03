import { Languages, LogOut, Moon, Sun, User } from 'lucide-react'
import { Avatar } from '@/components/avatar/Avatar'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/DropdownMenu'
import { useDirection } from '@/providers/DirectionProvider'
import { useTheme } from '@/providers/ThemeProvider'
import { cn } from '@/lib/cn'

export type UserMenuUser = {
  name: string
  email?: string
  role?: string
}

export type UserMenuProps = {
  user: UserMenuUser
  appVersion?: string
  className?: string
}

export function UserMenu({ user, appVersion = '0.1.0', className }: UserMenuProps) {
  const { resolvedTheme, toggleTheme } = useTheme()
  const { locale, setLocale } = useDirection()

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button
          type="button"
          className={cn(
            'focus-ring rounded-full outline-none transition-opacity hover:opacity-90',
            className,
          )}
          aria-label={`User menu for ${user.name}`}
        >
          <Avatar name={user.name} size="sm" showStatus status="online" />
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-56">
        <DropdownMenuLabel>
          <div className="flex flex-col gap-0.5">
            <span className="text-body-strong text-text-primary">{user.name}</span>
            {user.role ? (
              <span className="text-caption font-normal text-text-secondary">{user.role}</span>
            ) : null}
            {user.email ? (
              <span className="text-caption font-normal text-text-tertiary">{user.email}</span>
            ) : null}
          </div>
        </DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuItem
          icon={<User size={16} strokeWidth={1.5} />}
          onSelect={() => undefined}
        >
          Profile
        </DropdownMenuItem>
        <DropdownMenuItem
          icon={
            resolvedTheme === 'light' ? (
              <Moon size={16} strokeWidth={1.5} />
            ) : (
              <Sun size={16} strokeWidth={1.5} />
            )
          }
          onSelect={toggleTheme}
        >
          {resolvedTheme === 'light' ? 'Dark theme' : 'Light theme'}
        </DropdownMenuItem>
        <DropdownMenuItem
          icon={<Languages size={16} strokeWidth={1.5} />}
          onSelect={() => setLocale(locale === 'en' ? 'ar' : 'en')}
        >
          Language · {locale === 'en' ? 'English' : 'العربية'}
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem
          icon={<LogOut size={16} strokeWidth={1.5} />}
          destructive
          onSelect={() => undefined}
        >
          Sign out
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <p className="px-2 py-1 text-caption text-text-tertiary">v{appVersion}</p>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
