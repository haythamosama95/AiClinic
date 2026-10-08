# STG-A01 Paymob test card on staging offers

## STG-A01 Paymob test card for 1, 3, and 12 months

- [ ] Given the staging profile (`[env.staging]`) with `DURATION_SCALE` mapping 1 month to 30 minutes and 1 day to 1 minute, and the three console-published staging offers — Monthly (1 month, 30 minutes, grace about 7 minutes, 20 credits), Quarterly (3 months, 90 minutes, grace about 7 minutes, 60 credits), and Annual (12 months, 6 hours, grace about 7 minutes, 240 credits) — when the administrator completes checkout with a Paymob test card for each term length via `POST /v1/checkouts` → `handlePostCheckout` with the Paymob test integration (purchase chain cited, not executed here); then AI is active within about a minute, the payment appears in `GET /v1/payments`, the term is active with the full offer allowance, the admin desktop shows Active, and the desktop calls `public.request_ai_status_refresh()`.
