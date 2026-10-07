# Research: P5.1 issuer key custody

## 1. R-3 Vault plus signing in SQL

**Decision:** Issuer signing is Vault plus signing in SQL. `vault.create_secret` stores the Ed25519 private key. `vault.decrypted_secrets` returns it inside the definer body. `pgsodium.crypto_sign_detached` signs. `pgsodium.crypto_sign_verify_detached` checks the signature. The Edge Function signer is not used.

**Rationale:** On the local Supabase database the spike ran as one transaction and rolled it back. Extensions present: `pgsodium` 3.1.8 and `supabase_vault` 0.3.1. `pgsodium.crypto_sign_new_keypair` returns `public` and `secret` (`bytea`). `vault.create_secret(text, text, text)` stored `encode(secret, 'base64')`. The decrypted value matched the original secret. A detached signature over a UTF-8 message was 64 bytes and verified with the public key. That is the K-2 signing path FR-001 requires.

**Named fallback:** 01 §7 row R-3 and 06 §6 OQ-4 name a single-purpose Edge Function signer that holds no `service_role`. That fallback is not taken. The spike passed, and OQ-4 uses the fallback only with the owner's approval after a failed spike.

**Alternatives considered:** The Edge Function signer was not implemented. It adds a deployable the constitution check does not need once SQL signing works.
