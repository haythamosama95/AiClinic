import 'dart:async';
import 'dart:io';

import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';

/// Maps caught errors to user-friendly messages for display in form pages.
abstract final class UserErrorMapper {
  static String mapToUserMessage(Object error) {
    if (error is RpcFailure) {
      return error.message;
    }
    if (error is SocketException) {
      return 'Unable to connect to the server. Please check your network connection.';
    }
    if (error is TimeoutException) {
      return 'The operation timed out. Please try again.';
    }
    if (error is FormatException) {
      return 'Invalid data format. Please check your input and try again.';
    }
    if (error is StateError) {
      return error.message;
    }
    if (error is ArgumentError) {
      return error.message?.toString() ?? 'Invalid input. Please check your data and try again.';
    }

    AppLog.warning('unhandled_error type=${error.runtimeType} error=$error');
    return 'An unexpected error occurred. Please try again or contact support.';
  }
}
