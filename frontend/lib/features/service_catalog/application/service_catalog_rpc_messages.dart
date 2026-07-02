import 'package:ai_clinic/core/rpc/rpc_result.dart';

/// User-facing Service Catalog RPC error messages (015).
String serviceCatalogMessageForRpc(RpcFailure failure) {
  return switch (failure.code) {
    'STALE_SERVICE' => 'This service was updated elsewhere. Reload and try again.',
    'STALE_SERVICE_BRANCH' => 'Branch configuration was updated elsewhere. Reload and try again.',
    'DUPLICATE_NAME' => 'A service with this name already exists in your organization.',
    'INVALID_PRICE' => 'Price must be a non-negative amount with at most two decimal places.',
    'BRANCH_NOT_IN_ORG' => 'One or more selected branches are not in your organization.',
    'BRANCH_NOT_ASSIGNED' => 'Configure branch settings only for branches where the service is assigned.',
    'PROMO_EXCEEDS_PRICE' =>
      'Promotion price cannot exceed the effective price. Lower the promotion or raise the default/override price.',
    'PROMO_INCOMPLETE' => 'Promotion requires a price and both start and end dates.',
    'PROMO_DATE_RANGE' => 'Promotion start date must be on or before the end date.',
    'INVALID_COPY_TARGET' => 'Source and target branches must differ and belong to your organization.',
    'SERVICE_NOT_ELIGIBLE' =>
      failure.message.isNotEmpty ? failure.message : 'This service is not eligible at the selected branch.',
    'NOT_FOUND' => 'The requested service was not found.',
    'FORBIDDEN' => 'You do not have permission to perform this catalog action.',
    'INVALID_INPUT' =>
      failure.message.isNotEmpty ? failure.message : 'The catalog input was invalid. Check the form and try again.',
    'RPC_NOT_APPLIED' => 'The catalog action could not be applied. Please try again.',
    'RPC_NOT_CONFIGURED' => 'Service catalog is not configured correctly. Contact your administrator.',
    'AUTH_ERROR' => 'Your session has expired or is invalid. Sign in again and retry.',
    'UNEXPECTED_RESPONSE' => 'Catalog data from the server was incomplete. Please refresh and try again.',
    _ => failure.message.isNotEmpty ? failure.message : 'Something went wrong. Please try again.',
  };
}
