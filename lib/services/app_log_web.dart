import 'dart:async';

import 'package:flutter/foundation.dart';

class AppLog {
  static bool _hookInstalled = false;
  static DebugPrintCallback? _originalDebugPrint;

  static void installDebugPrintHook() {
    if (_hookInstalled) return;
    _hookInstalled = true;
    _originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      _originalDebugPrint?.call(message, wrapWidth: wrapWidth);
      if (message == null || message.trim().isEmpty) return;
      unawaited(write(
        level: 'DEBUG',
        source: 'debugPrint',
        message: message,
      ));
    };
  }

  static Future<void> db(
    String source,
    String message, {
    Map<String, dynamic>? data,
  }) {
    return write(level: 'DB', source: source, message: message, data: data);
  }

  static Future<void> info(
    String source,
    String message, {
    Map<String, dynamic>? data,
  }) {
    return write(level: 'INFO', source: source, message: message, data: data);
  }

  static Future<void> warn(
    String source,
    String message, {
    Map<String, dynamic>? data,
  }) {
    return write(level: 'WARN', source: source, message: message, data: data);
  }

  static Future<void> error(
    String source,
    String message, {
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    return write(
      level: 'ERROR',
      source: source,
      message: message,
      data: data,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static Future<void> write({
    required String level,
    required String source,
    required String message,
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    // Web build: no file-system logging. Keep console output only.
    _originalDebugPrint?.call('[$level][$source] $message');
  }

  static Future<String?> currentLogPath() async {
    return null;
  }
}
