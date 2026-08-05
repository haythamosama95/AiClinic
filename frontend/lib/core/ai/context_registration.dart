import 'context_provider_port.dart';

typedef ContextKeyResolver = Future<Map<String, Object?>> Function(
  ContextProviderPort port, [
  Map<String, Object?>? arguments,
]);

/// First published context key (A5).
const visitChiefComplaintV1Key = 'visit.chief_complaint@v1';

/// Closed static map of context key → resolver function (Clarification Q2).
///
/// Existing registrations ignore [arguments]; the optional channel is for keys
/// that need request-scoped arguments (H3 / §6.7.2).
final Map<String, ContextKeyResolver> contextRegistration =
    <String, ContextKeyResolver>{
  visitChiefComplaintV1Key: (port, [arguments]) => port.fetchVisitChiefComplaint(),
};

/// Keys registered for the client contract suite (§13.5).
Set<String> get registeredContextKeys => contextRegistration.keys.toSet();
