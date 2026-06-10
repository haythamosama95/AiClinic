import 'bootstrap_field_options.dart';

/// Preset values for local development bootstrap (debug-only UI).
abstract final class BootstrapDummyData {
  static const organizationName = 'Demo Clinic';
  static const currencyCode = BootstrapCurrencyOptions.defaultCode;
  static const timezone = BootstrapTimezoneOptions.defaultZone;
  static const branchName = 'Main Branch';
  static const branchCode = 'MAIN';
  static const branchAddress = '123 Demo Street, Cairo';
  static const branchPhone = '+20 100 000 0000';
  static const branchMapsUrl = 'https://maps.example.com/demo-clinic-main';
}
