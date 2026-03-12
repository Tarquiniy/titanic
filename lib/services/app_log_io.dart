import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class AppLog {
  static const String _filePrefix = 'titanic_events';
  static bool _hookInstalled = false;
  static DebugPrintCallback? _originalDebugPrint;
  static Future<void> _queue = Future<void>.value();
  static File? _activeFile;
  static String? _activeDay;

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
    final String line = _formatRecord(
      level: level,
      source: source,
      message: message,
      data: data,
      error: error,
      stackTrace: stackTrace,
    );

    _queue = _queue.then((_) async {
      try {
        final file = await _ensureLogFile();
        await file.writeAsString(line, mode: FileMode.append, flush: true);
      } catch (_) {
        // Logging must never crash app flow.
      }
    });

    return _queue;
  }

  static Future<String?> currentLogPath() async {
    try {
      final file = await _ensureLogFile();
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static String _formatRecord({
    required String level,
    required String source,
    required String message,
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final now = DateTime.now().toLocal().toIso8601String();
    final b = StringBuffer()
      ..writeln('[$now] [$level] [$source] $message');

    if (data != null && data.isNotEmpty) {
      b.writeln('  data:');
      b.writeln(_prettyJson(data, indent: '    '));
    }
    if (error != null) {
      b.writeln('  error: $error');
    }
    if (stackTrace != null) {
      final lines = stackTrace.toString().trim().split('\n');
      final take = lines.length > 8 ? 8 : lines.length;
      if (take > 0) {
        b.writeln('  stack:');
        for (int i = 0; i < take; i++) {
          b.writeln('    ${lines[i]}');
        }
      }
    }

    b.writeln('');
    return b.toString();
  }

  static String _prettyJson(Map<String, dynamic> data, {String indent = '  '}) {
    try {
      final normalized = _jsonSafe(data);
      final json = const JsonEncoder.withIndent('  ').convert(normalized);
      return json
          .split('\n')
          .map((line) => '$indent$line')
          .join('\n');
    } catch (_) {
      return '$indent${data.toString()}';
    }
  }

  static dynamic _jsonSafe(dynamic value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is DateTime) return value.toIso8601String();
    if (value is Map) {
      final out = <String, dynamic>{};
      value.forEach((k, v) {
        out[k.toString()] = _jsonSafe(v);
      });
      return out;
    }
    if (value is Iterable) {
      return value.map(_jsonSafe).toList();
    }
    return value.toString();
  }

  static Future<File> _ensureLogFile() async {
    final now = DateTime.now().toLocal();
    final day = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    if (_activeFile != null && _activeDay == day) {
      return _activeFile!;
    }

    // Logs are stored locally on the running device, next to the app working dir.
    final logsDir = Directory(
      '${Directory.current.path}${Platform.pathSeparator}logs',
    );
    if (!await logsDir.exists()) {
      await logsDir.create(recursive: true);
    }

    final file = File(
      '${logsDir.path}${Platform.pathSeparator}$_filePrefix-$day.log',
    );
    if (!await file.exists()) {
      await file.create(recursive: true);
      await file.writeAsString(
        'Titanic event log file\n'
        'date: $day\n'
        '----------------------------------------\n\n',
        mode: FileMode.append,
        flush: true,
      );
    }

    _activeDay = day;
    _activeFile = file;
    return file;
  }
}
