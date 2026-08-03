import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { scrollToDevSection } from '@/components/showcase/DevSectionLink'

const DEFAULT_ROUTE = 'home'

function parseRouteHash(hash: string): string | null {
  if (!hash || hash === '#' || hash === '#/') return DEFAULT_ROUTE
  if (!hash.startsWith('#/')) return null
  const normalized = hash.slice(2).replace(/^\/+|\/+$/g, '')
  return normalized || DEFAULT_ROUTE
}

export function useHashRoute() {
  const [route, setRoute] = useState(() => parseRouteHash(window.location.hash) ?? DEFAULT_ROUTE)
  const routeRef = useRef(route)
  routeRef.current = route

  useEffect(() => {
    const onHashChange = () => {
      const parsed = parseRouteHash(window.location.hash)
      if (parsed !== null) {
        setRoute(parsed)
        return
      }

      const sectionId = window.location.hash.slice(1)
      window.history.replaceState(null, '', `#/${routeRef.current}`)
      if (sectionId) {
        requestAnimationFrame(() => {
          scrollToDevSection(sectionId)
        })
      }
    }
    window.addEventListener('hashchange', onHashChange)
    return () => window.removeEventListener('hashchange', onHashChange)
  }, [])

  const navigate = useCallback((next: string) => {
    window.location.hash = `#/${next.replace(/^\/+/, '')}`
  }, [])

  const segments = useMemo(() => route.split('/').filter(Boolean), [route])

  return { route, segments, navigate }
}
