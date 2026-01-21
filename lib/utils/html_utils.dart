// lib/utils/html_utils.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

String stripHtmlTags(String? s) {
  if (s == null || s.isEmpty) return '';
  String t = s.replaceAll(RegExp(r'<br\s*\/?>', caseSensitive: false), '\n');
  t = t.replaceAllMapped(RegExp(r'<\/?b>', caseSensitive: false), (m) {
    final v = m.group(0) ?? '';
    return v.toLowerCase().contains('</') ? '</b>' : '<b>';
  });
  t = t.replaceAll(RegExp(r'<(?!\/?b\b)[^>]*>', caseSensitive: false), '');
  return t;
}

String previewText(String? raw, {int maxLen = 120}) {
  if (raw == null || raw.isEmpty) return '';
  final cleaned = stripHtmlTags(raw);
  final single = cleaned.replaceAll('\n', ' ').trim();
  if (single.length <= maxLen) return single;
  return single.substring(0, maxLen - 1).trim() + '…';
}

Widget selectableTextFromHtml(String? raw) {
  final text = stripHtmlTags(raw);
  return SelectableText(text, style: const TextStyle(fontSize: 14, height: 1.3));
}
