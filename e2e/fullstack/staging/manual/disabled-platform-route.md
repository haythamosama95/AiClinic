# STG-A04 Disabled platform route

## STG-A04 Platform route disabled for 4 days; grant retries every 15 minutes

- [ ] Given the staging profile (`[env.staging]`) with `DURATION_SCALE` mapping 1 month to 30 minutes and 1 day to 1 minute, and the platform route disabled for 4 days after a payment; when the grant row retries every 15 minutes for 4 days via `scheduled()` (`abo/src/worker.ts`) and the platform returns; then AL-04 is raised hourly while the platform is down, the grant applies on return, and the term starts at activation so no paid days are lost.
