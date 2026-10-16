-- Bind durable request idempotency to the validated request shape.
-- Existing rows stay NULL and are treated as unverified by the admission path.
ALTER TABLE ai_request ADD COLUMN request_fingerprint TEXT;
