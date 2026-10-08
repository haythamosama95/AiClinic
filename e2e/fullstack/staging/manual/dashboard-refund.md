# STG-A16 Dashboard refund

## STG-A16 Dashboard refund as parent flags or a child transaction, folded into a reversal

- [ ] Given the staging profile (`[env.staging]`) with `DURATION_SCALE` mapping 1 month to 30 minutes and 1 day to 1 minute, and an active term funded by a Paymob payment; when the operator issues a dashboard refund as parent flags or a child transaction per `manual/dashboard-refund.md`, and the checkout sweep inquires via `scheduled()` (`abo/src/worker.ts`); then the refund is folded into a reversal (never a payment), inquiry confirms the reversal, AL-06 is raised, and lost-callback bounds in 05 §8 A16 are respected.
