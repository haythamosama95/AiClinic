# Bootstrap ceremony

Launch requires two active operator credentials.

1. **Bootstrap the first credential.** With an empty `operator_credential` table, register the first operator credential through the console bootstrap path. No approving assertion is required while the registry is empty.

2. **Register a second credential.** An existing active credential approves the registration. The new credential enters `pending` status and becomes active after a 24-hour delay (`activates_at`).

Both credentials must be active before `launch-check` passes the operator-credential condition.
