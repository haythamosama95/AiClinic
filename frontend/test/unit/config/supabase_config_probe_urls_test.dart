import 'package:ai_clinic/core/config/supabase_config.dart';
import '../../helpers/startup_test_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('probe URLs target Supabase CLI Kong routes not bare gateway root', () {
    final config = SupabaseConfig.fromDeploymentProfile(sampleDeploymentProfile());

    expect(config.authHealthUrl.path, '/auth/v1/health');
    expect(config.restProbeUrl.path, '/rest/v1/');
    expect(config.restProbeUrl.toString(), endsWith('/rest/v1/'));
    expect(config.url.path, isEmpty);
  });
}
