import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/service_catalog/application/service_catalog_rpc_messages.dart';
import 'package:flutter_test/flutter_test.dart';

RpcFailure _failure({required String code, String message = 'backend message'}) {
  return RpcFailure(RpcResult(success: false, errorCode: code, errorMessage: message));
}

void main() {
  group('serviceCatalogMessageForRpc', () {
    test('STALE_SERVICE returns reload message', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'STALE_SERVICE')),
        'This service was updated elsewhere. Reload and try again.',
      );
    });

    test('STALE_SERVICE_BRANCH returns branch reload message', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'STALE_SERVICE_BRANCH')),
        'Branch configuration was updated elsewhere. Reload and try again.',
      );
    });

    test('DUPLICATE_NAME returns duplicate name message', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'DUPLICATE_NAME')),
        'A service with this name already exists in your organization.',
      );
    });

    test('INVALID_PRICE returns price format message', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'INVALID_PRICE')),
        'Price must be a non-negative amount with at most two decimal places.',
      );
    });

    test('BRANCH_NOT_IN_ORG returns organization branch message', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'BRANCH_NOT_IN_ORG')),
        'One or more selected branches are not in your organization.',
      );
    });

    test('BRANCH_NOT_ASSIGNED returns assignment message', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'BRANCH_NOT_ASSIGNED')),
        'Configure branch settings only for branches where the service is assigned.',
      );
    });

    test('PROMO_EXCEEDS_PRICE returns promotion cap message', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'PROMO_EXCEEDS_PRICE')),
        'Promotion price cannot exceed the effective price. Lower the promotion or raise the default/override price.',
      );
    });

    test('PROMO_INCOMPLETE returns incomplete promotion message', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'PROMO_INCOMPLETE')),
        'Promotion requires a price and both start and end dates.',
      );
    });

    test('PROMO_DATE_RANGE returns date range message', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'PROMO_DATE_RANGE')),
        'Promotion start date must be on or before the end date.',
      );
    });

    test('INVALID_COPY_TARGET returns copy target message', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'INVALID_COPY_TARGET')),
        'Source and target branches must differ and belong to your organization.',
      );
    });

    test('NOT_FOUND returns not found message', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'NOT_FOUND')),
        'The requested service was not found.',
      );
    });

    test('FORBIDDEN returns permission message', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'FORBIDDEN')),
        'You do not have permission to perform this catalog action.',
      );
    });

    test('RPC_NOT_APPLIED returns retry message', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'RPC_NOT_APPLIED')),
        'The catalog action could not be applied. Please try again.',
      );
    });

    test('RPC_NOT_CONFIGURED returns administrator message', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'RPC_NOT_CONFIGURED')),
        'Service catalog is not configured correctly. Contact your administrator.',
      );
    });

    test('AUTH_ERROR returns session message', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'AUTH_ERROR')),
        'Your session has expired or is invalid. Sign in again and retry.',
      );
    });

    test('UNEXPECTED_RESPONSE returns refresh guidance', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'UNEXPECTED_RESPONSE')),
        'Catalog data from the server was incomplete. Please refresh and try again.',
      );
    });

    test('INVALID_INPUT passes through non-empty backend message', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'INVALID_INPUT', message: 'Service name is required.')),
        'Service name is required.',
      );
    });

    test('INVALID_INPUT with empty message uses catalog fallback', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'INVALID_INPUT', message: '')),
        'The catalog input was invalid. Check the form and try again.',
      );
    });

    test('SERVICE_NOT_ELIGIBLE passes through non-empty backend message', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'SERVICE_NOT_ELIGIBLE', message: 'Branch is inactive.')),
        'Branch is inactive.',
      );
    });

    test('SERVICE_NOT_ELIGIBLE with empty message uses eligibility fallback', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'SERVICE_NOT_ELIGIBLE', message: '')),
        'This service is not eligible at the selected branch.',
      );
    });

    test('unknown code falls back to backend message', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'CUSTOM_ERROR', message: 'Custom backend detail.')),
        'Custom backend detail.',
      );
    });

    test('unknown code with empty message uses generic fallback', () {
      expect(
        serviceCatalogMessageForRpc(_failure(code: 'CUSTOM_ERROR', message: '')),
        'Something went wrong. Please try again.',
      );
    });

    test('unknown code with default RpcFailure message', () {
      final failure = RpcFailure(const RpcResult(success: false));
      expect(serviceCatalogMessageForRpc(failure), 'The clinic service rejected this request.');
    });

    test('all known codes produce non-empty strings', () {
      const knownCodes = [
        'STALE_SERVICE',
        'STALE_SERVICE_BRANCH',
        'DUPLICATE_NAME',
        'INVALID_PRICE',
        'BRANCH_NOT_IN_ORG',
        'BRANCH_NOT_ASSIGNED',
        'PROMO_EXCEEDS_PRICE',
        'PROMO_INCOMPLETE',
        'PROMO_DATE_RANGE',
        'INVALID_COPY_TARGET',
        'SERVICE_NOT_ELIGIBLE',
        'NOT_FOUND',
        'FORBIDDEN',
        'INVALID_INPUT',
        'RPC_NOT_APPLIED',
        'RPC_NOT_CONFIGURED',
        'AUTH_ERROR',
        'UNEXPECTED_RESPONSE',
      ];

      for (final code in knownCodes) {
        expect(
          serviceCatalogMessageForRpc(_failure(code: code)),
          isNotEmpty,
          reason: 'code=$code should produce non-empty message',
        );
      }
    });
  });
}
