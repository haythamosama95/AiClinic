import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/clinic-management/application/clinic_management_rpc_messages.dart';
import 'package:flutter_test/flutter_test.dart';

RpcFailure _failure({required String code, String message = 'backend message'}) {
  return RpcFailure(RpcResult(success: false, errorCode: code, errorMessage: message));
}

void main() {
  group('organizationMessageForRpc', () {
    test('FORBIDDEN returns permission message', () {
      expect(
        organizationMessageForRpc(_failure(code: 'FORBIDDEN')),
        'You do not have permission to update organization settings.',
      );
    });

    test('ORG_NOT_FOUND returns support message', () {
      expect(
        organizationMessageForRpc(_failure(code: 'ORG_NOT_FOUND')),
        'Your clinic organization could not be found. Contact support.',
      );
    });

    test('INVALID_INPUT passes through backend message', () {
      expect(
        organizationMessageForRpc(_failure(code: 'INVALID_INPUT', message: 'Name is required')),
        'Name is required',
      );
    });

    test('RPC_NOT_APPLIED passes through backend message', () {
      expect(
        organizationMessageForRpc(_failure(code: 'RPC_NOT_APPLIED', message: 'Migration missing')),
        'Migration missing',
      );
    });

    test('unknown code falls back to connectivity message', () {
      expect(
        organizationMessageForRpc(_failure(code: 'UNEXPECTED_ERROR')),
        'Unable to save organization settings. Check connectivity and try again.',
      );
    });

    test('all known codes produce non-empty strings', () {
      const knownCodes = ['FORBIDDEN', 'ORG_NOT_FOUND', 'INVALID_INPUT', 'RPC_NOT_APPLIED'];

      for (final code in knownCodes) {
        expect(
          organizationMessageForRpc(_failure(code: code)),
          isNotEmpty,
          reason: 'code=$code should produce non-empty message',
        );
      }
    });
  });

  group('branchMessageForRpc', () {
    test('LAST_ACTIVE_BRANCH passes through backend message', () {
      expect(
        branchMessageForRpc(_failure(code: 'LAST_ACTIVE_BRANCH', message: 'Keep one branch active.')),
        'Keep one branch active.',
      );
    });

    test('DUPLICATE_CODE returns duplicate code message', () {
      expect(
        branchMessageForRpc(_failure(code: 'DUPLICATE_CODE')),
        'Another branch already uses this code. Choose a different code.',
      );
    });

    test('FORBIDDEN returns permission message', () {
      expect(
        branchMessageForRpc(_failure(code: 'FORBIDDEN')),
        'You do not have permission to manage branches.',
      );
    });

    test('BRANCH_NOT_FOUND returns refresh message', () {
      expect(
        branchMessageForRpc(_failure(code: 'BRANCH_NOT_FOUND')),
        'That branch was not found. Refresh the list and try again.',
      );
    });

    test('BRANCH_STILL_ACTIVE returns deactivate-first message', () {
      expect(
        branchMessageForRpc(_failure(code: 'BRANCH_STILL_ACTIVE')),
        'Deactivate the branch before deleting it.',
      );
    });

    test('BRANCH_ALREADY_DELETED returns already-deleted message', () {
      expect(
        branchMessageForRpc(_failure(code: 'BRANCH_ALREADY_DELETED')),
        'That branch has already been deleted.',
      );
    });

    test('INVALID_INPUT passes through backend message', () {
      expect(
        branchMessageForRpc(_failure(code: 'INVALID_INPUT', message: 'Code too long')),
        'Code too long',
      );
    });

    test('RPC_NOT_APPLIED passes through backend message', () {
      expect(
        branchMessageForRpc(_failure(code: 'RPC_NOT_APPLIED', message: 'RPC not configured')),
        'RPC not configured',
      );
    });

    test('unknown code falls back to connectivity message', () {
      expect(
        branchMessageForRpc(_failure(code: 'NETWORK_ERROR')),
        'Unable to complete the branch action. Check connectivity and try again.',
      );
    });

    test('all known codes produce non-empty strings', () {
      const knownCodes = [
        'LAST_ACTIVE_BRANCH',
        'DUPLICATE_CODE',
        'FORBIDDEN',
        'BRANCH_NOT_FOUND',
        'BRANCH_STILL_ACTIVE',
        'BRANCH_ALREADY_DELETED',
        'INVALID_INPUT',
        'RPC_NOT_APPLIED',
      ];

      for (final code in knownCodes) {
        expect(
          branchMessageForRpc(_failure(code: code)),
          isNotEmpty,
          reason: 'code=$code should produce non-empty message',
        );
      }
    });
  });

  group('permissionMessageForRpc', () {
    test('FORBIDDEN returns administrator-only message', () {
      expect(
        permissionMessageForRpc(_failure(code: 'FORBIDDEN')),
        'Only clinic administrators can change role permissions.',
      );
    });

    test('INVALID_PERMISSION passes through backend message', () {
      expect(
        permissionMessageForRpc(_failure(code: 'INVALID_PERMISSION', message: 'Unknown permission key')),
        'Unknown permission key',
      );
    });

    test('PERMISSION_NOT_FOUND returns refresh message', () {
      expect(
        permissionMessageForRpc(_failure(code: 'PERMISSION_NOT_FOUND')),
        'That permission row could not be found. Refresh the page and try again.',
      );
    });

    test('INVALID_INPUT passes through backend message', () {
      expect(
        permissionMessageForRpc(_failure(code: 'INVALID_INPUT', message: 'Role is required')),
        'Role is required',
      );
    });

    test('RPC_NOT_APPLIED passes through backend message', () {
      expect(
        permissionMessageForRpc(_failure(code: 'RPC_NOT_APPLIED', message: 'Not applied')),
        'Not applied',
      );
    });

    test('unknown code falls back to connectivity message', () {
      expect(
        permissionMessageForRpc(_failure(code: 'CUSTOM_ERROR')),
        'Unable to update role permissions. Check connectivity and try again.',
      );
    });

    test('all known codes produce non-empty strings', () {
      const knownCodes = [
        'FORBIDDEN',
        'INVALID_PERMISSION',
        'PERMISSION_NOT_FOUND',
        'INVALID_INPUT',
        'RPC_NOT_APPLIED',
      ];

      for (final code in knownCodes) {
        expect(
          permissionMessageForRpc(_failure(code: code)),
          isNotEmpty,
          reason: 'code=$code should produce non-empty message',
        );
      }
    });
  });

  group('staffMessageForRpc', () {
    test('FORBIDDEN returns permission message', () {
      expect(
        staffMessageForRpc(_failure(code: 'FORBIDDEN')),
        'You do not have permission to manage staff.',
      );
    });

    test('STAFF_NOT_FOUND returns refresh message', () {
      expect(
        staffMessageForRpc(_failure(code: 'STAFF_NOT_FOUND')),
        'That staff member was not found. Refresh the list and try again.',
      );
    });

    test('STAFF_STILL_ACTIVE returns deactivate-first message', () {
      expect(
        staffMessageForRpc(_failure(code: 'STAFF_STILL_ACTIVE')),
        'Deactivate the staff member before deleting them.',
      );
    });

    test('STAFF_ALREADY_DELETED returns already-deleted message', () {
      expect(
        staffMessageForRpc(_failure(code: 'STAFF_ALREADY_DELETED')),
        'That staff member has already been deleted.',
      );
    });

    test('CROSS_ORG_DENIED returns cross-org message', () {
      expect(
        staffMessageForRpc(_failure(code: 'CROSS_ORG_DENIED')),
        'That staff member is outside your clinic organization.',
      );
    });

    test('INVALID_BRANCH returns invalid branch message', () {
      expect(
        staffMessageForRpc(_failure(code: 'INVALID_BRANCH')),
        'One or more selected branches are invalid or inactive.',
      );
    });

    test('corner case: LAST_ADMINISTRATOR with empty message uses default fallback', () {
      expect(
        staffMessageForRpc(_failure(code: 'LAST_ADMINISTRATOR', message: '')),
        'Cannot deactivate the last active administrator.',
      );
    });

    test('corner case: LAST_ADMINISTRATOR preserves non-empty backend message', () {
      expect(
        staffMessageForRpc(_failure(code: 'LAST_ADMINISTRATOR', message: 'Custom last-admin detail.')),
        'Custom last-admin detail.',
      );
    });

    test('CANNOT_DEACTIVATE_SELF returns self-deactivate message', () {
      expect(
        staffMessageForRpc(_failure(code: 'CANNOT_DEACTIVATE_SELF')),
        'You cannot deactivate your own account.',
      );
    });

    test('CANNOT_DELETE_SELF returns self-delete message', () {
      expect(
        staffMessageForRpc(_failure(code: 'CANNOT_DELETE_SELF')),
        'You cannot delete your own account.',
      );
    });

    test('INVALID_INPUT passes through backend message', () {
      expect(
        staffMessageForRpc(_failure(code: 'INVALID_INPUT', message: 'Username taken')),
        'Username taken',
      );
    });

    test('RPC_NOT_APPLIED passes through backend message', () {
      expect(
        staffMessageForRpc(_failure(code: 'RPC_NOT_APPLIED', message: 'RPC skipped')),
        'RPC skipped',
      );
    });

    test('unknown code falls back to connectivity message', () {
      expect(
        staffMessageForRpc(_failure(code: 'UNKNOWN_STAFF_ERROR')),
        'Unable to complete the staff action. Check connectivity and try again.',
      );
    });

    test('all known codes produce non-empty strings', () {
      const knownCodes = [
        'FORBIDDEN',
        'STAFF_NOT_FOUND',
        'STAFF_STILL_ACTIVE',
        'STAFF_ALREADY_DELETED',
        'CROSS_ORG_DENIED',
        'INVALID_BRANCH',
        'LAST_ADMINISTRATOR',
        'CANNOT_DEACTIVATE_SELF',
        'CANNOT_DELETE_SELF',
        'INVALID_INPUT',
        'RPC_NOT_APPLIED',
      ];

      for (final code in knownCodes) {
        expect(
          staffMessageForRpc(_failure(code: code)),
          isNotEmpty,
          reason: 'code=$code should produce non-empty message',
        );
      }
    });
  });
}
