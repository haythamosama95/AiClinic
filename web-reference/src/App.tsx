import { useCallback, useMemo, useState } from 'react'
import { AppShell } from '@/components/layout/AppShell'
import { Breadcrumb } from '@/components/navigation/Breadcrumb'
import { AppSidebar } from '@/components/navigation/AppSidebar'
import { AppTopBar } from '@/components/navigation/AppTopBar'
import { buildDefaultCommandItems, CommandBar } from '@/components/navigation/CommandBar'
import {
    CLINIC_NAV_FOOTER,
    CLINIC_NAV_GROUPS,
    MOCK_BRANCHES,
    MOCK_NOTIFICATION_COUNT,
    MOCK_ORG,
    MOCK_USER,
} from '@/components/navigation/nav-model'
import { LoginPage } from '@/pages/auth/LoginPage'
import { breadcrumbLabel, resolveRoute } from '@/pages/app/routes'
import { useHashRoute } from '@/router/useHashRoute'
import { cn } from '@/lib/cn'

const SIDEBAR_COLLAPSED_KEY = 'aiclinic:sidebar-collapsed'
const BRANCH_KEY = 'aiclinic:branch'

function getInitialCollapsed(): boolean {
    if (typeof window === 'undefined') return false
    return localStorage.getItem(SIDEBAR_COLLAPSED_KEY) === 'true'
}

function getInitialBranchId(): string {
    if (typeof window === 'undefined') return MOCK_BRANCHES[0].id
    const stored = localStorage.getItem(BRANCH_KEY)
    if (stored && MOCK_BRANCHES.some((b) => b.id === stored)) return stored
    return MOCK_BRANCHES[0].id
}

export function App() {
    const { segments, navigate } = useHashRoute()
    const [collapsed, setCollapsed] = useState(getInitialCollapsed)
    const [branchId, setBranchId] = useState(getInitialBranchId)
    const [authenticated, setAuthenticated] = useState(false)

    const activeId = segments[0] ?? 'home'

    const currentBranch = MOCK_BRANCHES.find((b) => b.id === branchId) ?? MOCK_BRANCHES[0]
    const { content, fullWidth } = useMemo(
        () => resolveRoute(segments, navigate),
        [segments, navigate],
    )

    const toggleCollapsed = useCallback(() => {
        setCollapsed((prev) => {
            const next = !prev
            localStorage.setItem(SIDEBAR_COLLAPSED_KEY, String(next))
            return next
        })
    }, [])

    const handleBranchChange = useCallback((id: string) => {
        setBranchId(id)
        localStorage.setItem(BRANCH_KEY, id)
    }, [])

    const pageContext = useMemo(() => {
        if (activeId === 'dev') {
            return (
                <Breadcrumb
                    items={[
                        { label: 'Dev', onClick: () => navigate('dev') },
                        { label: breadcrumbLabel(segments) },
                    ]}
                />
            )
        }

        const navItem = [...CLINIC_NAV_GROUPS.flatMap((g) => g.items), ...CLINIC_NAV_FOOTER].find(
            (item) => item.id === activeId,
        )

        if (activeId === 'patients' && segments[1]) {
            return (
                <Breadcrumb
                    items={[
                        { label: 'Patients', onClick: () => navigate('patients') },
                        { label: breadcrumbLabel(segments) },
                    ]}
                />
            )
        }

        if (activeId === 'settings' && segments[1]) {
            return (
                <Breadcrumb
                    items={[
                        { label: 'Settings', onClick: () => navigate('settings') },
                        { label: breadcrumbLabel(segments) },
                    ]}
                />
            )
        }

        if (!navItem) return undefined

        return <Breadcrumb items={[{ label: navItem.label }]} />
    }, [activeId, navigate, segments])

    return (
        <div className="relative h-dvh bg-surface-canvas">
            <div
                className={cn(
                    'h-full transition-[filter] duration-[var(--duration-slow)] ease-[var(--ease-standard)]',
                    !authenticated && 'pointer-events-none select-none blur-md',
                )}
                aria-hidden={!authenticated}
            >
                <a
                    href="#main"
                    className="sr-only focus:not-sr-only focus:absolute focus:z-50 focus:m-4 focus:rounded-md focus:bg-action-primary focus:px-4 focus:py-2 focus:text-action-primary-fg"
                >
                    Skip to content
                </a>

                <AppShell
                    className="h-full"
                    fullWidth={fullWidth}
                    sidebar={
                        <AppSidebar
                            items={CLINIC_NAV_GROUPS}
                            footerItems={CLINIC_NAV_FOOTER}
                            activeId={activeId}
                            onNavigate={navigate}
                            collapsed={collapsed}
                            onToggleCollapsed={toggleCollapsed}
                            org={MOCK_ORG}
                            branch={currentBranch.name}
                        />
                    }
                    topBar={
                        <AppTopBar
                            pageContext={pageContext}
                            branches={MOCK_BRANCHES}
                            currentBranchId={branchId}
                            onBranchChange={handleBranchChange}
                            user={MOCK_USER}
                            notificationCount={MOCK_NOTIFICATION_COUNT}
                        />
                    }
                    commandBar={<CommandBar items={buildDefaultCommandItems(navigate)} />}
                >
                    {content}
                </AppShell>
            </div>

            {!authenticated ? <LoginPage onLogin={() => setAuthenticated(true)} /> : null}
        </div>
    )
}
