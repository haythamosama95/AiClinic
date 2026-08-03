// Re-export shim. ProvisioningRules now lives in the settings feature domain
// (features/settings/domain/provisioning_rules.dart) since staff-account lifecycle
// management is a settings concern, not a setup-wizard concern (review §6.5).
// This shim keeps existing setup-feature imports resolving during the migration.
export 'package:ai_clinic/features/settings/domain/provisioning_rules.dart';
