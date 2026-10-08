# STG-A03 Blocked notify URL

## STG-A03 Blocked notify URL; sweep inquires at +2, +5, +10, and +20 minutes

- [ ] Given the staging profile (`[env.staging]`) with `DURATION_SCALE` mapping 1 month to 30 minutes and 1 day to 1 minute, and a checkout where the provider notification is lost or delayed by a blocked notify URL; when the checkout sweep runs via `scheduled()` (`abo/src/worker.ts`); then the sweep inquires at +2, +5, +10, and +20 minutes, provisions the payment, and raises AL-03.
