DELETE FROM ai_attempt;
DELETE FROM usage_event;
DELETE FROM ai_request;
DELETE FROM grace_admission_queue;
DELETE FROM entitlement;
DELETE FROM installation_key;
DELETE FROM installation;
DELETE FROM capability_grant;
DELETE FROM control_audit;
DELETE FROM kill_switch;
DELETE FROM platform_counter;
DELETE FROM routing_policy;
DELETE FROM usage_rollup;
DELETE FROM token_contract;
INSERT INTO token_contract (ver, added_at, retired_at, changed_by)
VALUES ('1', datetime('now'), NULL, 'platform-reset');
