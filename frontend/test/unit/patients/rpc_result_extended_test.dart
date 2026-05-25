import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RpcResult.fromDynamic', () {
    test('parses map with success=true', () {
      final result = RpcResult.fromDynamic({
        'success': true,
        'data': {'patient_id': 'p1'},
      });

      expect(result.success, isTrue);
      expect(result.data?['patient_id'], 'p1');
      expect(result.errorCode, isNull);
      expect(result.errorMessage, isNull);
    });

    test('parses map with success=false and error fields', () {
      final result = RpcResult.fromDynamic({
        'success': false,
        'error_code': 'NOT_FOUND',
        'error_message': 'Patient was not found.',
      });

      expect(result.success, isFalse);
      expect(result.errorCode, 'NOT_FOUND');
      expect(result.errorMessage, 'Patient was not found.');
    });

    test('parses map with camelCase error key aliases', () {
      final result = RpcResult.fromDynamic({
        'success': false,
        'errorCode': 'STALE_PATIENT',
        'errorMessage': 'Record was updated elsewhere.',
      });

      expect(result.errorCode, 'STALE_PATIENT');
      expect(result.errorMessage, 'Record was updated elsewhere.');
    });

    test('prefers snake_case keys over camelCase when both present', () {
      final result = RpcResult.fromDynamic({
        'success': false,
        'error_code': 'SNAKE',
        'errorCode': 'CAMEL',
        'error_message': 'Snake message',
        'errorMessage': 'Camel message',
      });

      expect(result.errorCode, 'SNAKE');
      expect(result.errorMessage, 'Snake message');
    });

    test('success string "true" parses as true', () {
      final result = RpcResult.fromDynamic({'success': 'true'});
      expect(result.success, isTrue);
    });

    test('success string "t" parses as true', () {
      final result = RpcResult.fromDynamic({'success': 't'});
      expect(result.success, isTrue);
    });

    test('success string "TRUE" parses as true (case insensitive)', () {
      final result = RpcResult.fromDynamic({'success': 'TRUE'});
      expect(result.success, isTrue);
    });

    test('success string "false" parses as false', () {
      final result = RpcResult.fromDynamic({'success': 'false'});
      expect(result.success, isFalse);
    });

    test('success null parses as false', () {
      final result = RpcResult.fromDynamic({'success': null});
      expect(result.success, isFalse);
    });

    test('success 0 or other values parse as false', () {
      expect(RpcResult.fromDynamic({'success': 0}).success, isFalse);
      expect(RpcResult.fromDynamic({'success': 'yes'}).success, isFalse);
    });

    test('data as non-Map is coerced to null', () {
      final result = RpcResult.fromDynamic({
        'success': true,
        'data': 'not a map',
      });

      expect(result.data, isNull);
    });

    test('data as Map<Object, Object> is coerced to Map<String, dynamic>', () {
      final result = RpcResult.fromDynamic({
        'success': true,
        'data': <Object, Object>{'key': 'value'},
      });

      expect(result.data, isA<Map<String, dynamic>>());
      expect(result.data?['key'], 'value');
    });

    test('returns itself when input is already RpcResult', () {
      const original = RpcResult(success: true, data: {'id': '1'});
      final result = RpcResult.fromDynamic(original);

      expect(identical(result, original), isTrue);
    });

    test('parses list with 4+ elements', () {
      final result = RpcResult.fromDynamic([true, {'id': 'p1'}, 'ERROR_CODE', 'Error message']);

      expect(result.success, isTrue);
      expect(result.data?['id'], 'p1');
      expect(result.errorCode, 'ERROR_CODE');
      expect(result.errorMessage, 'Error message');
    });

    test('list format: null data produces null', () {
      final result = RpcResult.fromDynamic([false, null, 'CODE', 'msg']);
      expect(result.data, isNull);
    });

    test('throws FormatException for unrecognized payload', () {
      expect(() => RpcResult.fromDynamic(42), throwsA(isA<FormatException>()));
      expect(() => RpcResult.fromDynamic('string'), throwsA(isA<FormatException>()));
      expect(() => RpcResult.fromDynamic(null), throwsA(isA<FormatException>()));
    });

    test('throws FormatException for list shorter than 4', () {
      expect(() => RpcResult.fromDynamic([true, null, 'CODE']), throwsA(isA<FormatException>()));
      expect(() => RpcResult.fromDynamic([true]), throwsA(isA<FormatException>()));
      expect(() => RpcResult.fromDynamic(<dynamic>[]), throwsA(isA<FormatException>()));
    });
  });

  group('RpcFailure', () {
    test('code defaults to RPC_ERROR when errorCode is null', () {
      final failure = RpcFailure(const RpcResult(success: false));
      expect(failure.code, 'RPC_ERROR');
    });

    test('message defaults when errorMessage is null', () {
      final failure = RpcFailure(const RpcResult(success: false));
      expect(failure.message, 'The clinic service rejected this request.');
    });

    test('toString includes code and message', () {
      final failure = RpcFailure(
        const RpcResult(success: false, errorCode: 'TEST', errorMessage: 'Test message'),
      );

      expect(failure.toString(), contains('TEST'));
      expect(failure.toString(), contains('Test message'));
    });

    test('code returns errorCode from result', () {
      final failure = RpcFailure(
        const RpcResult(success: false, errorCode: 'CUSTOM_CODE'),
      );
      expect(failure.code, 'CUSTOM_CODE');
    });

    test('message returns errorMessage from result', () {
      final failure = RpcFailure(
        const RpcResult(success: false, errorMessage: 'Custom error'),
      );
      expect(failure.message, 'Custom error');
    });
  });
}
