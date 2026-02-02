// lib/widgets/journal_widget.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import 'art_deco_card.dart';
import 'art_deco_button.dart';

/// JournalWidget — design focused. Keeps behavior simple and stable.
class JournalWidget extends StatefulWidget {
  final List<Map<String, dynamic>> entries;
  final bool showControls;
  final ValueChanged<Map<String, dynamic>>? onAddEntry;
  final ValueChanged<Map<String, dynamic>>? onEditEntry;
  final ValueChanged<String>? onDeleteEntry;

  const JournalWidget({
    Key? key,
    required this.entries,
    this.showControls = true,
    this.onAddEntry,
    this.onEditEntry,
    this.onDeleteEntry,
  }) : super(key: key);

  @override
  State<JournalWidget> createState() => _JournalWidgetState();
}

class _JournalWidgetState extends State<JournalWidget> {
  late List<Map<String, dynamic>> _items;
  final TextEditingController _search = TextEditingController();
  final DateFormat _fmt = DateFormat('yyyy-MM-dd HH:mm');
  Map<String, bool> _expanded = {};

  @override
  void initState() {
    super.initState();
    _items = List<Map<String, dynamic>>.from(widget.entries);
    _search.addListener(_applyFilter);
  }

  @override
  void didUpdateWidget(covariant JournalWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries != widget.entries) {
      _items = List<Map<String, dynamic>>.from(widget.entries);
      _applyFilter();
    }
  }

  void _applyFilter() {
    setState(() {}); // simple; filtering done in builder for brevity
  }

  String _formatDate(dynamic v) {
    if (v == null) return '';
    DateTime? dt;
    if (v is DateTime) dt = v;
    else dt = DateTime.tryParse(v.toString());
    if (dt == null) return '';
    return _fmt.format(dt.toLocal());
  }

  Future<void> _showAddDialog() async {
    final title = TextEditingController();
    final msg = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить запись'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: title, decoration: TitanicTheme.inputDecoration.copyWith(hintText: 'Заголовок')),
            const SizedBox(height: 8),
            TextField(controller: msg, decoration: TitanicTheme.inputDecoration.copyWith(hintText: 'Сообщение'), maxLines: 4),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              final e = {
                'id': UniqueKey().toString(),
                'title': title.text,
                'message': msg.text,
                'created_at': DateTime.now().toUtc().toIso8601String(),
              };
              widget.onAddEntry?.call(e);
              setState(() {
                _items.insert(0, e);
              });
              Navigator.of(ctx).pop();
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final filtered = _items.where((e) {
      final t = (e['title'] ?? '').toString().toLowerCase();
      final m = (e['message'] ?? '').toString().toLowerCase();
      return q.isEmpty || t.contains(q) || m.contains(q);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: TitanicTheme.inputDecoration.copyWith(prefixIcon: const Icon(Icons.search), hintText: 'Поиск в журнале'),
                ),
              ),
              const SizedBox(width: 10),
              if (widget.showControls)
                ArtDecoButton(text: 'Добавить', icon: Icons.add, onPressed: _showAddDialog, primary: true),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: filtered.isEmpty
              ? Center(child: Text('Записей нет', style: TitanicTheme.body.copyWith(color: TitanicTheme.softIvory.withOpacity(0.7))))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final entry = filtered[i];
                    final id = (entry['id'] ?? i.toString()).toString();
                    final isExp = _expanded[id] ?? false;
                    final title = (entry['title'] ?? '').toString();
                    final msg = (entry['message'] ?? '').toString();
                    final created = _formatDate(entry['created_at']);
                    return ArtDecoCard(
                      title: title.isEmpty ? 'Без заголовка' : title,
                      subtitle: created,
                      leading: CircleAvatar(backgroundColor: TitanicTheme.deepTeal.withOpacity(0.4), child: Text(title.isNotEmpty ? title[0].toUpperCase() : '?')),
                      trailing: IconButton(
                        icon: Icon(isExp ? Icons.expand_less : Icons.expand_more, color: TitanicTheme.warmGold),
                        onPressed: () {
                          setState(() {
                            _expanded[id] = !isExp;
                          });
                        },
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedCrossFade(
                            firstChild: Text(msg.length > 180 ? '${msg.substring(0, 180)}…' : msg, style: TitanicTheme.body),
                            secondChild: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(msg, style: TitanicTheme.body),
                                const SizedBox(height: 8),
                                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                  TextButton.icon(onPressed: () => _editEntry(entry), icon: const Icon(Icons.edit), label: const Text('Редактировать')),
                                  TextButton.icon(onPressed: () => _deleteEntry(id), icon: const Icon(Icons.delete), label: const Text('Удалить')),
                                ]),
                              ],
                            ),
                            crossFadeState: isExp ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                            duration: const Duration(milliseconds: 200),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _editEntry(Map<String, dynamic> entry) async {
    final title = TextEditingController(text: entry['title']?.toString());
    final msg = TextEditingController(text: entry['message']?.toString());
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Редактировать'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: TitanicTheme.inputDecoration.copyWith(hintText: 'Заголовок')),
          const SizedBox(height: 8),
          TextField(controller: msg, decoration: TitanicTheme.inputDecoration.copyWith(hintText: 'Сообщение'), maxLines: 4),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              final updated = Map<String, dynamic>.from(entry);
              updated['title'] = title.text;
              updated['message'] = msg.text;
              widget.onEditEntry?.call(updated);
              final idx = _items.indexWhere((e) => (e['id'] ?? '').toString() == (entry['id'] ?? '').toString());
              if (idx >= 0) setState(() => _items[idx] = updated);
              Navigator.of(ctx).pop();
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  void _deleteEntry(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить запись?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              widget.onDeleteEntry?.call(id);
              setState(() => _items.removeWhere((e) => (e['id'] ?? '').toString() == id));
              Navigator.of(ctx).pop();
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }
}
