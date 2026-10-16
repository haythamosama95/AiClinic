-- A5 follow-up (H3-R4): index for one ordered conversation query (§7.3).
CREATE INDEX idx_ai_request_conversation ON ai_request (conversation_id, turn_ordinal);
