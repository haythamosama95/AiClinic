import { useCallback, useEffect, useMemo, useState } from 'react'

const DEFAULT_ROUTE = 'home'

function parseHash(): string {
  const hash = window.location.hash
  if (!hash || hash === '#' || hash === '#/') return DEFAULT_ROUTE
  const path = hash.startsWith('#/') ? hash.slice(2) : hash.slice(1)
  const normalized = path.replace(/^\/+|\/+$/g, '')
  return normalized || DEFAULT_ROUTE
}

export function useHashRoute() {
  const [route, setRoute] = useState(() => parseHash())

  useEffect(() => {
    const onHashChange = () => setRoute(parseHash())
    window.addEventListener('hashchange', onHashChange)
    return () => window.removeEventListener('hashchange', onHashChange)
  }, [])

  const navigate = useCallback((next: string) => {
    window.location.hash = `#/${next.replace(/^\/+/, '')}`
  }, [])

  const segments = useMemo(() => route.split('/').filter(Boolean), [route])

  return { route, segments, navigate }
}
