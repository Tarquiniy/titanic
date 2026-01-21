// lib/widgets/journal_widget.dart
import 'package:flutter/material.dart';

/// JournalWidget
/// - entries: List<Map<String,dynamic>> where each map may contain:
///   id, title, message, created_at, visible_role, actor_id, metadata ...
class JournalWidget extends StatefulWidget {
  final List<Map<String, dynamic>> entries;
  const JournalWidget({Key? key, required this.entries}) : super(key: key);

  @override
  State<JournalWidget> createState() => _JournalWidgetState();
}

class _JournalWidgetState extends State<JournalWidget> {

  // === Helpers ===
  String _fmtTime(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = DateTime.tryParse(raw);
      if (dt == null) return raw;
      final local = dt.toLocal();
      String z(int n) => n.toString().padLeft(2, '0');
      return '${z(local.day)}.${z(local.month)} ${z(local.hour)}:${z(local.minute)}';
    } catch (_) {
      return raw;
    }
  }

  /// Replace <br> tags with \n and keep <b>...</b> tokens, remove other tags.
  String _normalizeHtml(String? s) {
    if (s == null) return '';
    String t = s;
    // convert br -> \n
    t = t.replaceAll(RegExp(r'<br\s*\/?>', caseSensitive: false), '\n');
    // normalize b tags to lower-case markers
    t = t.replaceAllMapped(RegExp(r'<\/?b>', caseSensitive: false), (m) {
      final v = m.group(0) ?? '';
      return v.toLowerCase().contains('</') ? '</b>' : '<b>';
    });
    // remove any other tags
    t = t.replaceAll(RegExp(r'<(?!\/?b\b)[^>]*>', caseSensitive: false), '');
    return t;
  }

  /// Convert simple html with <b> tags to a TextSpan (bold) and plain parts.
  TextSpan _parseToTextSpan(String? htmlSource, {TextStyle? base}) {
    final text = _normalizeHtml(htmlSource);
    if (text.isEmpty) return TextSpan(text: '', style: base);

    final reg = RegExp(r'(.*?)<b>(.*?)<\/b>', dotAll: true, caseSensitive: false);
    final matches = reg.allMatches(text).toList();
    if (matches.isEmpty) {
      return TextSpan(text: text, style: base);
    }

    final children = <TextSpan>[];
    int currentIndex = 0;
    for (final m in matches) {
      if (m.start > currentIndex) {
        children.add(TextSpan(text: text.substring(currentIndex, m.start), style: base));
      }
      final boldText = m.group(2) ?? '';
      children.add(TextSpan(
        text: boldText,
        style: base?.merge(const TextStyle(fontWeight: FontWeight.w700)) ??
            const TextStyle(fontWeight: FontWeight.w700),
      ));
      currentIndex = m.end;
    }
    if (currentIndex < text.length) {
      children.add(TextSpan(text: text.substring(currentIndex), style: base));
    }
    return TextSpan(children: children, style: base);
  }

  IconData _iconForTitle(String? title, String? message) {
    final t = (title ?? '').toLowerCase();
    final m = (message ?? '').toLowerCase();
    if (t.contains('речь') || m.contains('speech') || t.contains('speech')) return Icons.mic;
    if (t.contains('баланс') || m.contains('войсы') || t.contains('поступление') || m.contains('зачислено')) return Icons.account_balance_wallet;
    if (t.contains('политреш') || t.contains('политическое') || m.contains('политреш')) return Icons.gavel;
    if (t.contains('дебат') || t.contains('дебаты') || m.contains('дебат')) return Icons.forum;
    if (t.contains('оффер') || m.contains('offer')) return Icons.local_shipping;
    if (t.contains('предмет') || m.contains('inventory') || m.contains('предмет')) return Icons.inventory_2;
    if (t.contains('изменение') || t.contains('профиль')) return Icons.person;
    return Icons.notifications;
  }

  Color _colorForIcon(String? title) {
    final t = (title ?? '').toLowerCase();
    if (t.contains('баланс') || t.contains('поступление')) return Colors.green.shade700;
    if (t.contains('политреш')) return Colors.indigo.shade700;
    if (t.contains('дебат')) return Colors.purple.shade700;
    if (t.contains('речь')) return Colors.orange.shade700;
    if (t.contains('предмет')) return Colors.teal.shade700;
    return Colors.blueGrey.shade700;
  }

  bool _isFresh(String? createdAt) {
    if (createdAt == null) return false;
    try {
      final dt = DateTime.tryParse(createdAt);
      if (dt == null) return false;
      final diff = DateTime.now().toUtc().difference(dt.toUtc());
      return diff.inMinutes <= 5;
    } catch (_) {
      return false;
    }
  }

  String _contentSignature(String title, String message) {
    // create normalized signature to detect identical messages (ignore whitespace and case)
    final a = (title ?? '').trim().toLowerCase();
    final b = (message ?? '').replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    return '$a|$b';
  }

  String _contentSignatureFromRaw(Map<String, dynamic> raw) {
    final title = (raw['title'] ?? raw['message'] ?? '').toString();
    final msg = (raw['message'] ?? '').toString();
    return _contentSignature(title, msg);
  }

  @override
Widget build(BuildContext context) {
  final seenIds = <dynamic>{};
  final seenSigs = <String>{};
  final List<Map<String, dynamic>> items = [];

  for (final e in widget.entries) {
    final id = e['id'];
    final sig = _contentSignatureFromRaw(e);

    if (id != null) {
      if (seenIds.contains(id)) continue;
      seenIds.add(id);
    } else {
      if (seenSigs.contains(sig)) continue;
      seenSigs.add(sig);
    }

    items.add(e);
  }

  if (items.isEmpty) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text('Пусто', style: TextStyle(color: Colors.grey)),
      ),
    );
  }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final e = items[index];
        final rawTitle = (e['title'] ?? 'Событие').toString();
        final rawMsgOriginal = (e['message'] ?? '').toString();

        // --- Normalize/Translate frequently seen tokens to user-friendly RU text ---
        // (Keep UI-level translation here to ensure journal looks Russian)
        String title = rawTitle;
        String message = rawMsgOriginal;

        // quick token replacements to make lines friendlier
        message = message.replaceAll(RegExp(r'\bv_balance\b', caseSensitive: false), 'Войсы');
        message = message.replaceAll(RegExp(r'\bm_balance\b', caseSensitive: false), 'Майндов');
        message = message.replaceAll(RegExp(r'<br\s*\/?>', caseSensitive: false), '\n');
        // remove stray table/column markers that admin triggers may include
        message = message.replaceAll(RegExp(r'\b(user_credentials|speech_state|debates|political_resolutions|item_offers)\b', caseSensitive: false), '');

        // map obvious raw titles to RU
        final low = rawTitle.toLowerCase();
        if (low.contains('speech_state') || low.contains('речь')) title = 'Речь жизни';
        if (low.contains('balance') || low.contains('v_balance') || message.toLowerCase().contains('войсы')) {
          if (!title.toLowerCase().contains('баланс')) title = 'Баланс изменён';
        }
        if (low.contains('debate') || low.contains('дебат')) title = 'Дебаты';
        if (low.contains('resolution') || low.contains('политреш')) title = 'Политрешение';
        if (low.contains('offer') || low.contains('оффер')) title = 'Оффер';
        if (low.contains('item') || low.contains('inventory') || message.toLowerCase().contains('добавлен')) {
          if (!title.toLowerCase().contains('предмет')) title = 'Добавлен предмет';
        }

        final created = (e['created_at'] ?? e['createdAt'] ?? '').toString();
        final time = _fmtTime(created);
        final icon = _iconForTitle(title, message);
        final iconColor = _colorForIcon(title);
        final fresh = _isFresh(created);

        final actor = e['actor_id'] ?? e['actor'] ?? e['metadata']?['actor_id'];

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[850] : const Color(0xFFFBF7FB),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text(title),
                  content: SingleChildScrollView(
                    child: SelectableText(_normalizeHtml(message)),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Закрыть'))],
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon + fresh dot
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: iconColor.withOpacity(0.12),
                        child: Icon(icon, size: 20, color: iconColor),
                      ),
                      if (fresh)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  // Texts
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // title + time
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                            ),
                            Text(time, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // message (render <b> as bold)
                        Text.rich(
                          _parseToTextSpan(message, base: const TextStyle(fontSize: 14, color: Colors.black87)),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        // optional metadata row (actor etc)
                        if (actor != null || (e['metadata'] != null && e['metadata'] is Map))
                          Row(
                            children: [
                              if (actor != null)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                ),
                              if (e['metadata'] != null && e['metadata'] is Map)
                                const Icon(Icons.info_outline, size: 14, color: Colors.black45),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
final Set<dynamic> _seenIds = {};
