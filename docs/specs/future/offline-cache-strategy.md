# Offline / Cache Strategy (Future)

**Status**: Deferred — document intent now; implement when prioritized.

## Problem

The app is fully online. When the clinic LAN is unavailable (router reboot,
cable disconnect, server maintenance), every RPC call fails with a raw
socket exception and the entire UI becomes unusable.

## Proposed Approach

### Phase 1 — Friendly error handling (V1-current)

- Catch `SocketException` and `TimeoutException` in the RPC invoker layer
- Map them to user-friendly messages via `UserErrorMapper`
- Show a "Network unavailable — check your LAN connection" message
- Allow retrying the operation

### Phase 2 — Read-only cache (future)

- Use `drift` (SQLite) as a local cache for patient list and detail data
- Cache is populated on every successful RPC response
- When network is unavailable, display cached data with a stale-data indicator
- Cache invalidation on reconnection via Supabase realtime or manual refresh

### Phase 3 — Offline mutations (future)

- Implement a sync queue (`drift` table) for mutations made while offline
- Mutations are queued locally and applied when connectivity returns
- Conflict resolution: server timestamp wins; user is prompted on conflicts
- Indicator showing pending sync count

## Cache Invalidation Strategy

- **TTL-based**: Cached patient list expires after 5 minutes
- **Event-driven**: Supabase realtime channel for `patients` table changes
- **Manual**: Pull-to-refresh or explicit "Sync now" button
- **On reconnection**: Full re-fetch of active views

## Technical Considerations

- `drift` for local SQLite (already well-supported on Windows desktop)
- Separate cache DB from app state to allow clearing without sign-out
- Cache is per-organization (use org ID as DB namespace)
- PHI in local cache: must be encrypted at rest on shared workstations

## Decision Log

| Date | Decision |
|------|----------|
| 2026-05-24 | Deferred full offline support. Phase 1 error handling implemented. |
