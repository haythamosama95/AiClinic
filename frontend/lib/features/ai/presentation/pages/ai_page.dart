import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/ai_shell_status_provider.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/shell/navigation/shell_route_meta.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/core/ai/ai_client_sdk.dart';
import 'package:ai_clinic/core/ai/context_required_self_heal.dart';
import 'package:ai_clinic/core/ai/context_provider_port.dart';
import 'package:ai_clinic/core/ai/discovery_client.dart';
import 'package:ai_clinic/core/ai/discovery_manifest_refresh_port.dart';
import 'package:ai_clinic/core/ai/https_submit_port.dart';
import 'package:ai_clinic/core/ai/supabase_aat_mint_port.dart';
import 'package:ai_clinic/core/ai/supabase_context_provider_port.dart';
import 'package:ai_clinic/core/ai/usage_summary_client.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability_reader.dart';
import 'package:ai_clinic/features/ai/availability/ai_status_snapshot.dart';
import 'package:ai_clinic/features/ai/degraded/ai_degraded_mode.dart';
import 'package:ai_clinic/features/ai/degraded/ai_degraded_view.dart';
import 'package:ai_clinic/features/ai/host/ai_feature_host_page.dart';
import 'package:ai_clinic/features/ai/surface/first_ai_feature_surface.dart';
import 'package:ai_clinic/features/ai/surface/provisional_prose_view.dart';
import 'package:ai_clinic/features/ai/surface/request_reference_view.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Production hub composition for the live visit-summary host (I3 / T8 spy target).
@immutable
class LiveVisitSummaryComposition {
  const LiveVisitSummaryComposition({
    required this.dependencies,
    required this.mintPort,
    required this.submitPort,
    this.discoveryFailureReference,
    this.discoveryFailureCode,
    this.contractVersionUnsupported = false,
  });

  final AiFeatureHostDependencies dependencies;
  final AatMintPort mintPort;
  final HttpsSubmitPort submitPort;
  final String? discoveryFailureReference;
  final TaxonomyCode? discoveryFailureCode;
  final bool contractVersionUnsupported;
}

/// Builds live-host dependencies with production mint/submit unless overridden.
@visibleForTesting
LiveVisitSummaryComposition buildLiveVisitSummaryComposition({
  required SupabaseClient client,
  required String visitId,
  AiAvailabilityReader? availabilityReader,
  PlatformReachabilityPort? reachabilityPort,
  AatMintPort? mintPortOverride,
  HttpsSubmitPort? submitPortOverride,
  DiscoveryClient? discoveryClientOverride,
  PlatformNetworkSpy? networkSpy,
  AiPersistenceProbe? persistenceProbe,
  AiExportProbe? exportProbe,
  ContextProviderPort? contextProviderOverride,
  ManifestRefreshPort? manifestRefreshPortOverride,
  bool? autoInvoke,
  int? maxTransportAttempts,
  Duration Function(int attemptAfterFailure)? transportBackoff,
  String platformBaseUrl = 'https://ai.example.workers.dev',
  bool staffIsAdministrator = false,
  Future<void> Function()? onStatusRefresh,
  UsageSummaryClient? usageSummaryClientOverride,
}) {
  final reader = availabilityReader ?? SupabaseAiAvailabilityReader(client: client);
  final reachability = reachabilityPort ?? HttpPlatformReachabilityPort();
  final mintPort = mintPortOverride ?? SupabaseAatMintPort(client: client);
  final submitPort = submitPortOverride ?? PlatformHttpsSubmitPort(platformBaseUrl: platformBaseUrl);

  final sdk = AiClientSdk(
    mintPort: mintPort,
    submitPort: submitPort,
    maxTransportAttempts: maxTransportAttempts ?? kDefaultMaxTransportAttempts,
    transportBackoff: transportBackoff,
  );

  final manifestRefreshPort = manifestRefreshPortOverride ??
      DiscoveryManifestRefreshPort(
        discoveryClient: discoveryClientOverride ?? DiscoveryClient(),
        mintPort: mintPort,
        platformBaseUrl: platformBaseUrl,
      );

  return LiveVisitSummaryComposition(
    dependencies: AiFeatureHostDependencies(
      availabilityReader: reader,
      reachabilityPort: reachability,
      sdk: sdk,
      contextProvider: contextProviderOverride ?? SupabaseContextProviderPort(client: client, visitId: visitId),
      manifestRefreshPort: manifestRefreshPort,
      visitId: visitId,
      requiredContextKeys: kFirstAiRequiredContextKeys,
      networkSpy: networkSpy,
      persistenceProbe: persistenceProbe,
      exportProbe: exportProbe,
      mintPort: mintPort,
      usageSummaryClient: usageSummaryClientOverride,
      autoInvoke: autoInvoke ?? true,
      staffIsAdministrator: staffIsAdministrator,
      onStatusRefresh: onStatusRefresh,
    ),
    mintPort: mintPort,
    submitPort: submitPort,
  );
}

/// Async composition: mint AAT, discover required keys, wire production ports.
Future<LiveVisitSummaryComposition> composeLiveVisitSummaryHost({
  required SupabaseClient client,
  required String visitId,
  AiAvailabilityReader? availabilityReader,
  PlatformReachabilityPort? reachabilityPort,
  AatMintPort? mintPortOverride,
  HttpsSubmitPort? submitPortOverride,
  DiscoveryClient? discoveryClientOverride,
  PlatformNetworkSpy? networkSpy,
  AiPersistenceProbe? persistenceProbe,
  AiExportProbe? exportProbe,
  ContextProviderPort? contextProviderOverride,
  ManifestRefreshPort? manifestRefreshPortOverride,
  int? maxTransportAttempts,
  Duration Function(int attemptAfterFailure)? transportBackoff,
  bool staffIsAdministrator = false,
  Future<void> Function()? onStatusRefresh,
}) async {
  final reader = availabilityReader ?? SupabaseAiAvailabilityReader(client: client);
  final reachability = reachabilityPort ?? HttpPlatformReachabilityPort();
  final discovery = discoveryClientOverride ?? DiscoveryClient();
  final mintPort = mintPortOverride ?? SupabaseAatMintPort(client: client);

  late final AiAvailability availability;
  try {
    availability = await reader.read();
  } on ContractVersionUnsupportedException {
    final submitPort = submitPortOverride ?? PlatformHttpsSubmitPort(platformBaseUrl: 'https://ai.invalid');
    return LiveVisitSummaryComposition(
      dependencies: AiFeatureHostDependencies(
        availabilityReader: reader,
        reachabilityPort: reachability,
        sdk: AiClientSdk(
          mintPort: mintPort,
          submitPort: submitPort,
          maxTransportAttempts: maxTransportAttempts ?? kDefaultMaxTransportAttempts,
          transportBackoff: transportBackoff,
        ),
        contextProvider: contextProviderOverride ?? SupabaseContextProviderPort(client: client, visitId: visitId),
        manifestRefreshPort: manifestRefreshPortOverride ??
            DiscoveryManifestRefreshPort(
              discoveryClient: discovery,
              mintPort: mintPort,
              platformBaseUrl: 'https://ai.invalid',
            ),
        visitId: visitId,
        requiredContextKeys: kFirstAiRequiredContextKeys,
        networkSpy: networkSpy,
        persistenceProbe: persistenceProbe,
        exportProbe: exportProbe,
        mintPort: mintPort,
        autoInvoke: false,
        staffIsAdministrator: staffIsAdministrator,
        onStatusRefresh: onStatusRefresh,
      ),
      mintPort: mintPort,
      submitPort: submitPort,
      contractVersionUnsupported: true,
    );
  }
  final baseUrl = availability.platformBaseUrl ?? '';
  final submitPort = submitPortOverride ??
      (baseUrl.isNotEmpty
          ? PlatformHttpsSubmitPort(platformBaseUrl: baseUrl)
          : PlatformHttpsSubmitPort(platformBaseUrl: 'https://ai.invalid'));

  var requiredKeys = kFirstAiRequiredContextKeys;
  var discoveryManifests = <Map<String, Object?>>[];
  String? discoveryFailureReference;
  TaxonomyCode? discoveryFailureCode;

  if (availability.available && baseUrl.isNotEmpty) {
    try {
      final aat = await mintPort.mint();
      final discoveryResult = await discovery.fetchCapabilities(platformBaseUrl: baseUrl, aat: aat);
      if (!discoveryResult.notModified) {
        discoveryManifests = discoveryResult.manifests;
        final discovered = requiredContextKeysFromManifests(discoveryResult.manifests, kFirstAiCapabilityId);
        if (discovered.isNotEmpty) {
          requiredKeys = discovered;
        }
      }
    } on ContractVersionUnsupportedException {
      return LiveVisitSummaryComposition(
        dependencies: AiFeatureHostDependencies(
          availabilityReader: reader,
          reachabilityPort: reachability,
          sdk: AiClientSdk(
            mintPort: mintPort,
            submitPort: submitPort,
            maxTransportAttempts: maxTransportAttempts ?? kDefaultMaxTransportAttempts,
            transportBackoff: transportBackoff,
          ),
          contextProvider: contextProviderOverride ?? SupabaseContextProviderPort(client: client, visitId: visitId),
          manifestRefreshPort: manifestRefreshPortOverride ??
              DiscoveryManifestRefreshPort(
                discoveryClient: discovery,
                mintPort: mintPort,
                platformBaseUrl: baseUrl.isNotEmpty ? baseUrl : 'https://ai.invalid',
              ),
          visitId: visitId,
          requiredContextKeys: requiredKeys,
          networkSpy: networkSpy,
          persistenceProbe: persistenceProbe,
          exportProbe: exportProbe,
          mintPort: mintPort,
          autoInvoke: false,
          staffIsAdministrator: staffIsAdministrator,
          onStatusRefresh: onStatusRefresh,
        ),
        mintPort: mintPort,
        submitPort: submitPort,
        contractVersionUnsupported: true,
      );
    } on DiscoveryAuthFailure catch (error) {
      discoveryFailureCode = error.code;
      discoveryFailureReference = error.responseBody['request_reference']?.toString();
    }
  }

  final sdk = AiClientSdk(
    mintPort: mintPort,
    submitPort: submitPort,
    maxTransportAttempts: maxTransportAttempts ?? kDefaultMaxTransportAttempts,
    transportBackoff: transportBackoff,
  );

  final manifestRefreshPort = manifestRefreshPortOverride ??
      DiscoveryManifestRefreshPort(
        discoveryClient: discovery,
        mintPort: mintPort,
        platformBaseUrl: baseUrl.isNotEmpty ? baseUrl : 'https://ai.invalid',
        initialManifests: discoveryManifests,
      );

  return LiveVisitSummaryComposition(
    dependencies: AiFeatureHostDependencies(
      availabilityReader: reader,
      reachabilityPort: reachability,
      sdk: sdk,
      contextProvider: contextProviderOverride ?? SupabaseContextProviderPort(client: client, visitId: visitId),
      manifestRefreshPort: manifestRefreshPort,
      visitId: visitId,
      requiredContextKeys: requiredKeys,
      networkSpy: networkSpy,
      persistenceProbe: persistenceProbe,
      exportProbe: exportProbe,
      mintPort: mintPort,
      autoInvoke: availability.available && discoveryFailureCode == null,
      staffIsAdministrator: staffIsAdministrator,
      onStatusRefresh: onStatusRefresh,
    ),
    mintPort: mintPort,
    submitPort: submitPort,
    discoveryFailureReference: discoveryFailureReference,
    discoveryFailureCode: discoveryFailureCode,
  );
}

/// Test entry that mirrors production hub wiring without the `/ai` page chrome.
@visibleForTesting
class LiveVisitSummaryHostWidget extends StatefulWidget {
  const LiveVisitSummaryHostWidget({super.key, required this.visitId, this.composition});

  final String visitId;
  final LiveVisitSummaryComposition? composition;

  @override
  State<LiveVisitSummaryHostWidget> createState() => _LiveVisitSummaryHostWidgetState();
}

class _LiveVisitSummaryHostWidgetState extends State<LiveVisitSummaryHostWidget> {
  LiveVisitSummaryComposition? _composition;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.composition != null) {
      _composition = widget.composition;
      _loading = false;
    } else {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final container = ProviderScope.containerOf(context);
    final client = container.read(supabaseClientProvider);
    final composition = await composeLiveVisitSummaryHost(client: client, visitId: widget.visitId);
    if (mounted) {
      setState(() {
        _composition = composition;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _composition == null) {
      return const Center(child: Text(key: Key('live_host_loading'), 'Loading live host…'));
    }
    return liveVisitSummaryHostBody(visitId: widget.visitId, composition: _composition!);
  }
}

/// Shared live-host body for production page and widget-test entry (I3 composition).
@visibleForTesting
Widget liveVisitSummaryHostBody({
  required String visitId,
  required LiveVisitSummaryComposition composition,
  AiStatusSnapshot? liveStatus,
}) {
  if (composition.contractVersionUnsupported) {
    return const AiDegradedView(
      mode: AiDegradedMode.appUpdate,
      child: Text('Clinical workflows remain available.'),
    );
  }

  // §5.4 / FR-012: discovery installation_suspended hides AI features and instructs admin.
  if (composition.discoveryFailureCode == TaxonomyCode.installationSuspended) {
    return AiDegradedView(
      mode: AiDegradedMode.installationSuspended,
      child: const Text('Clinical workflows remain available.'),
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (composition.discoveryFailureReference != null)
        RequestReferenceView(requestReference: composition.discoveryFailureReference!),
      AiFeatureHostPage(
        key: ValueKey(visitId),
        dependencies: composition.dependencies,
        embedded: true,
        liveStatus: liveStatus,
      ),
    ],
  );
}

/// R7-UI1: immutable composition identity for the live visit host.
///
/// Any change to the authenticated user, the active organization, the
/// administrator role or the selected visit yields a different identity, so the
/// keyed host (and the dependencies it composed) is disposed before the new
/// label is shown.
@visibleForTesting
@immutable
class LiveVisitHostIdentity {
  const LiveVisitHostIdentity({
    required this.userId,
    required this.organizationId,
    required this.staffIsAdministrator,
    required this.visitId,
  });

  final String? userId;
  final String? organizationId;
  final bool staffIsAdministrator;
  final String visitId;

  @override
  bool operator ==(Object other) =>
      other is LiveVisitHostIdentity &&
      other.userId == userId &&
      other.organizationId == organizationId &&
      other.staffIsAdministrator == staffIsAdministrator &&
      other.visitId == visitId;

  @override
  int get hashCode => Object.hash(userId, organizationId, staffIsAdministrator, visitId);
}

/// Derives the live-host identity from the current auth context (not cached billing claims).
@visibleForTesting
LiveVisitHostIdentity liveVisitHostIdentityFor({
  required AuthSessionContext? authContext,
  required String visitId,
}) {
  return LiveVisitHostIdentity(
    userId: authContext?.staffProfile.staffMemberId,
    organizationId: authContext?.organizationId,
    staffIsAdministrator: authContext?.staffProfile.role == StaffRole.administrator,
    visitId: visitId,
  );
}

/// Clinic AI hub — exposes implemented AI capabilities and design-system widgets.
class AiPage extends ConsumerStatefulWidget {
  const AiPage({super.key});

  @override
  ConsumerState<AiPage> createState() => _AiPageState();
}

class _AiPageState extends ConsumerState<AiPage> {
  final _visitIdController = TextEditingController();
  var _suggestionVisible = true;
  var _aiMode = true;
  AiDegradedMode _demoDegradedMode = AiDegradedMode.unreachable;
  ProposedActionState _proposedState = ProposedActionState.proposed;
  String? _activeVisitId;

  @override
  void dispose() {
    _visitIdController.dispose();
    super.dispose();
  }

  void _loadVisitSummaryHost() {
    final visitId = _visitIdController.text.trim();
    setState(() => _activeVisitId = visitId.isEmpty ? null : visitId);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final authContext = ref.watch(authSessionProvider).context;
    final isAdministrator = authContext?.staffProfile.role == StaffRole.administrator;
    final l10n = AppLocalizations.of(context)!;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPageHeader(title: ShellRouteMeta.titleFor('ai'), description: ShellRouteMeta.descriptionFor('ai')),
        if (isAdministrator) ...[
          const SizedBox(height: AppSpacing.space4),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space4),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_outlined),
                  const SizedBox(width: AppSpacing.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.aiBillingOffersTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.space1),
                        Text(l10n.aiBillingOffersDescription),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space3),
                  AppButton(
                    key: const Key('ai_billing_entry'),
                    onPressed: () =>
                        context.push(AppRoutes.aiAdministratorBilling),
                    child: Text(l10n.aiBillingBrowsePlans),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.space8),
        _AiFeatureSection(
          title: 'Visit summary',
          description:
              'First AI capability (`clinic.visit_summary`): availability gate, '
              'streaming provisional prose, accept/discard, and degraded modes.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: AppFormField(
                      id: 'ai-visit-id',
                      label: 'Visit ID',
                      child: AppTextInput(
                        id: 'ai-visit-id',
                        controller: _visitIdController,
                        placeholder: 'UUID of a visit with a chief complaint',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space3),
                  AppButton(onPressed: _loadVisitSummaryHost, child: const Text('Load surface')),
                ],
              ),
              const SizedBox(height: AppSpacing.space4),
              if (_activeVisitId == null)
                Text(
                  'Enter a visit ID to open the live feature host. '
                  'Non-enrolled clinics hide the live affordance.',
                  style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                )
              else
                // R7-UI1: keyed by the full identity so an A->B visit change (or user/org/role
                // change) disposes the old host and its composed dependencies before B is shown.
                _LiveVisitSummaryHost(
                  key: ValueKey(
                    liveVisitHostIdentityFor(authContext: authContext, visitId: _activeVisitId!),
                  ),
                  visitId: _activeVisitId!,
                  staffIsAdministrator: isAdministrator,
                ),
              const SizedBox(height: AppSpacing.space6),
              const AppSectionHeader(
                title: 'Surface primitives',
                description: 'Provisional draft styling and support request reference.',
              ),
              const SizedBox(height: AppSpacing.space3),
              const ProvisionalProseView(
                text:
                    'Patient presents with headache for two days. No fever. '
                    'Advise hydration and follow-up if symptoms worsen.',
              ),
              const SizedBox(height: AppSpacing.space3),
              const RequestReferenceView(requestReference: 'req-demo-visit-summary'),
              const SizedBox(height: AppSpacing.space3),
              Wrap(
                spacing: AppSpacing.space2,
                runSpacing: AppSpacing.space2,
                children: [
                  AppButton(key: kAiAcceptKey, onPressed: () {}, child: const Text('Accept')),
                  AppButton(
                    key: kAiDiscardKey,
                    variant: AppButtonVariant.secondary,
                    onPressed: () {},
                    child: const Text('Discard'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space8),
        _AiFeatureSection(
          title: 'Degraded modes',
          description: 'Normal-state banners when AI is unreachable, over quota, or otherwise unavailable.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: AppSpacing.space2,
                runSpacing: AppSpacing.space2,
                children: [
                  for (final mode in AiDegradedMode.values)
                    if (mode != AiDegradedMode.ready && mode != AiDegradedMode.nonEnrolled)
                      AppButton(
                        variant: _demoDegradedMode == mode ? AppButtonVariant.primary : AppButtonVariant.secondary,
                        onPressed: () => setState(() => _demoDegradedMode = mode),
                        child: Text(mode.name),
                      ),
                ],
              ),
              const SizedBox(height: AppSpacing.space4),
              AiDegradedView(
                mode: _demoDegradedMode,
                onRetry: _demoDegradedMode == AiDegradedMode.providerUnavailable
                    ? () => setState(() => _demoDegradedMode = AiDegradedMode.ready)
                    : null,
                child: const Text('Clinical workflows remain available.'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space8),
        _AiFeatureSection(
          title: 'AI mode toggle',
          description: 'Switch between standard clinic UI and AI-assisted mode.',
          child: AppAiModeToggle(value: _aiMode, onChanged: (value) => setState(() => _aiMode = value)),
        ),
        const SizedBox(height: AppSpacing.space8),
        const _AiFeatureSection(
          title: 'Thinking indicator',
          description: 'Pulse shown while the assistant is working.',
          child: AppThinkingIndicator(),
        ),
        const SizedBox(height: AppSpacing.space8),
        _AiFeatureSection(
          title: 'Message bubbles',
          description: 'User and assistant turns for conversational AI surfaces.',
          child: SizedBox(
            width: 480,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppAiMessageBubble(
                  role: AiMessageRole.user,
                  timestamp: '2:14 PM',
                  child: Text('Which patients need follow-up this week?'),
                ),
                const SizedBox(height: AppSpacing.space4),
                AppAiMessageBubble(
                  role: AiMessageRole.assistant,
                  timestamp: '2:14 PM',
                  onCopy: () {},
                  child: const Text(
                    'Three patients have follow-ups due: Layla Hassan, '
                    'Omar Farouk, and Nadia El-Sayed.',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space8),
        _AiFeatureSection(
          title: 'Inline suggestion',
          description: 'Accept or dismiss an advisory AI suggestion.',
          child: _suggestionVisible
              ? AppAiSuggestion(
                  message: "AI can draft a SOAP note from today's visit summary.",
                  onAccept: () => setState(() => _suggestionVisible = false),
                  onDismiss: () => setState(() => _suggestionVisible = false),
                )
              : AppButton(
                  variant: AppButtonVariant.secondary,
                  onPressed: () => setState(() => _suggestionVisible = true),
                  child: const Text('Show suggestion again'),
                ),
        ),
        const SizedBox(height: AppSpacing.space8),
        _AiFeatureSection(
          title: 'Proposed action',
          description: 'Human-gated AI action card — approve runs the validated path.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.space2,
                runSpacing: AppSpacing.space2,
                children: [
                  for (final state in ProposedActionState.values)
                    AppButton(
                      variant: _proposedState == state ? AppButtonVariant.primary : AppButtonVariant.secondary,
                      onPressed: () => setState(() => _proposedState = state),
                      child: Text(state.name),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.space4),
              SizedBox(
                width: 448,
                child: AppProposedActionCard(
                  title: 'Book appointment',
                  summary: 'Schedule a follow-up for Layla Hassan with Dr. Ahmed on Jul 8 at 10:00 AM.',
                  state: _proposedState,
                  errorMessage: _proposedState == ProposedActionState.failed
                      ? 'Doctor is not available at the selected time.'
                      : null,
                  fields: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppFormField(
                        id: 'ai-pa-patient',
                        label: 'Patient',
                        child: const AppTextInput(id: 'ai-pa-patient', readOnly: true, initialValue: 'Layla Hassan'),
                      ),
                      const SizedBox(height: AppSpacing.space3),
                      AppFormField(
                        id: 'ai-pa-date',
                        label: 'Date',
                        child: const AppTextInput(id: 'ai-pa-date', initialValue: 'Jul 8, 2026'),
                      ),
                      const SizedBox(height: AppSpacing.space3),
                      AppFormField(
                        id: 'ai-pa-time',
                        label: 'Time',
                        child: const AppTextInput(id: 'ai-pa-time', initialValue: '10:00 AM'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space8),
        const _AiFeatureSection(
          title: 'AI panel',
          description: 'Chat panel with thinking and streaming mock flow.',
          child: SizedBox(height: 420, width: 480, child: AppAiPanel(scope: 'Downtown branch')),
        ),
        const SizedBox(height: AppSpacing.space8),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedHeight) {
          return SingleChildScrollView(child: body);
        }
        return body;
      },
    );
  }
}

class _AiFeatureSection extends StatelessWidget {
  const _AiFeatureSection({required this.title, required this.description, required this.child});

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSectionHeader(title: title, description: description),
            const SizedBox(height: AppSpacing.space4),
            child,
          ],
        ),
      ),
    );
  }
}

/// Live [AiFeatureHostPage] composed from clinic Supabase + platform reachability.
class _LiveVisitSummaryHost extends ConsumerStatefulWidget {
  const _LiveVisitSummaryHost({required this.visitId, required this.staffIsAdministrator});

  final String visitId;
  final bool staffIsAdministrator;

  @override
  ConsumerState<_LiveVisitSummaryHost> createState() => _LiveVisitSummaryHostState();
}

class _LiveVisitSummaryHostState extends ConsumerState<_LiveVisitSummaryHost> {
  LiveVisitSummaryComposition? _composition;
  var _loading = true;
  // R7-UI1: generation of the latest composition load; a superseded load must not install state.
  var _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(_LiveVisitSummaryHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Normally the parent key remounts this state on identity change; in-place changes
    // still drop the old composition and recompose under the new inputs.
    if (oldWidget.visitId != widget.visitId ||
        oldWidget.staffIsAdministrator != widget.staffIsAdministrator) {
      setState(() {
        _composition = null;
        _loading = true;
      });
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    // Capture every input before the first await so a later identity change cannot leak into this load.
    final generation = ++_loadGeneration;
    final visitId = widget.visitId;
    final staffIsAdministrator = widget.staffIsAdministrator;
    final client = ref.read(supabaseClientProvider);
    final onStatusRefresh = ref.read(aiShellStatusRefreshProvider);
    final composition = await composeLiveVisitSummaryHost(
      client: client,
      visitId: visitId,
      staffIsAdministrator: staffIsAdministrator,
      onStatusRefresh: onStatusRefresh,
    );
    // Mounted guard plus generation/visit checks: a disposed or superseded A load cannot install into B.
    if (!mounted || generation != _loadGeneration || visitId != widget.visitId) {
      return;
    }
    setState(() {
      _composition = composition;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // R7-T1: the open host receives the one shell status, but only for the identity it was
    // composed for; any other identity yields an empty snapshot and the reader fallback.
    final identity = aiStatusIdentityFor(ref.watch(authSessionProvider));
    final shellStatus = ref.watch(aiShellStatusNotifierProvider);
    final liveStatus = identity != null && shellStatus.identity == identity
        ? shellStatus
        : AiStatusSnapshot.empty;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.appColors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Live host for visit ${widget.visitId}',
              style: AppTypography.bodySm(context).copyWith(color: context.appColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.space3),
            if (_loading || _composition == null)
              const Center(child: Text(key: Key('live_host_loading'), 'Loading live host…'))
            else
              liveVisitSummaryHostBody(
                visitId: widget.visitId,
                composition: _composition!,
                liveStatus: liveStatus,
              ),
          ],
        ),
      ),
    );
  }
}
