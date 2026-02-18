// lib/widgets/journal_widget.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import 'art_deco_card.dart';
import 'art_deco_button.dart';

/// JournalWidget — displays journal entries and persists "seen" state locally via SharedPreferences.
class JournalWidget extends StatefulWidget {
  final List<Map<String, dynamic>> entries;
  final String? currentUserId;
  final String? currentUserRole;

  /// Optional CRUD callbacks (UI only; storage is handled outside).
  final void Function(Map<String, dynamic> entry)? onEditEntry;
  final void Function(String id)? onDeleteEntry;
  final void Function(String title, String message)? onAddEntry;

  const JournalWidget({
    Key? key,
    required this.entries,
    this.currentUserId,
    this.currentUserRole,
    this.onEditEntry,
    this.onDeleteEntry,
    this.onAddEntry,
  }) : super(key: key);

  @override
  State<JournalWidget> createState() => _JournalWidgetState();
}

class _JournalWidgetState extends State<JournalWidget> {
  late List<Map<String, dynamic>> _items;
  final TextEditingController _search = TextEditingController();
  final DateFormat _fmt = DateFormat('yyyy-MM-dd HH:mm');

  final _supabase = Supabase.instance.client;
  final Map<String, String> _actorNameCache = {};
  final Set<String> _actorNameLoading = {};

  final Map<String, bool> _expanded = {};
  final Set<String> _seenKeys = {};
  bool _seenLoaded = false;

  static const String _seenPrefsKey = 'titanic_journal_seen_v1';

  @override
  void initState() {
    super.initState();
    _items = List<Map<String, dynamic>>.from(widget.entries);
    _loadSeen();
  }

  @override
  void didUpdateWidget(covariant JournalWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries != widget.entries) {
      _items = List<Map<String, dynamic>>.from(widget.entries);
      // do NOT clear seen/expanded; preserve user state
      setState(() {});
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_seenPrefsKey);
      if (raw == null || raw.isEmpty) {
        if (!mounted) return;
        setState(() {
          _seenLoaded = true;
        });
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        if (!mounted) return;
        setState(() {
          _seenKeys
            ..clear()
            ..addAll(decoded.map((e) => e.toString()));
          _seenLoaded = true;
        });
      } else {
        if (!mounted) return;
        setState(() => _seenLoaded = true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _seenLoaded = true);
    }
  }

  Future<void> _saveSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_seenPrefsKey, jsonEncode(_seenKeys.toList()));
    } catch (_) {}
  }

  void _markSeen(String key) {
    if (!_seenLoaded) return;
    if (_seenKeys.contains(key)) return;
    setState(() {
      _seenKeys.add(key);
    });
    _saveSeen();
  }

  String _entryKey(Map<String, dynamic> e, int index) {
    final id = e['id']?.toString();
    if (id != null && id.isNotEmpty) return 'id::$id';
    final t = (e['title'] ?? '').toString();
    final m = (e['message'] ?? '').toString();
    final c = (e['created_at'] ?? '').toString();
    return 'txt::$t::$m::$c::$index';
  }

  String _formatDate(dynamic createdAt) {
    if (createdAt == null) return '';
    final s = createdAt.toString();
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    try {
      return _fmt.format(dt.toLocal());
    } catch (_) {
      return s;
    }
  }

  bool _looksLikeSpeechEvent(Map<String, dynamic> e) {
    final t = (e['title'] ?? '').toString().toLowerCase();
    final m = (e['message'] ?? '').toString().toLowerCase();
    final meta = (e['metadata'] ?? '').toString().toLowerCase();
    return t.contains('speech_state') ||
        t.contains('речь') ||
        t.contains('речь жизни') ||
        m.contains('speech_state') ||
        m.contains('речь') ||
        meta.contains('speech_state') ||
        meta.contains('speech');
  }

  bool _looksLikeTradeOffer(Map<String, dynamic> e) {
    final t = (e['title'] ?? '').toString().toLowerCase();
    final m = (e['message'] ?? '').toString().toLowerCase();
    final meta = (e['metadata'] ?? '').toString().toLowerCase();

    // Heuristics: offer/request to buy an item
    const needles = [
      'trade',
      'торг',
      'торгов',
      'обмен',
      'предлож',
      'офер',
      'offer',
      'запрос',
      'купить',
      'покупк',
      'покупа',
      'приглашение к покупке',
    ];

    for (final n in needles) {
      if (t.contains(n) || m.contains(n) || meta.contains(n)) return true;
    }
    return false;
  }

  bool _isAllowedCommonEvent(Map<String, dynamic> e) {
    // Only common events we want to show:
    // - speech activation (speech_state)
    // - trade offer to buy an item
    return _looksLikeSpeechEvent(e) || _looksLikeTradeOffer(e);
  }

  String? _ensureActorLabel(String? actorId) {
    final id = (actorId ?? '').trim();
    if (id.isEmpty) return null;

    final cached = _actorNameCache[id];
    if (cached != null && cached.isNotEmpty) return cached;

    if (_actorNameLoading.contains(id)) return null;
    _actorNameLoading.add(id);

    () async {
      try {
        final row = await _supabase
            .from('user_credentials')
            .select('first_name,last_name,telegram_username')
            .eq('id', id)
            .maybeSingle();

        if (!mounted) return;

        String? label;
        if (row is Map<String, dynamic>) {
          final first = (row['first_name'] ?? '').toString().trim();
          final last = (row['last_name'] ?? '').toString().trim();
          final tg = (row['telegram_username'] ?? '').toString().trim();
          label = ('$first $last').trim();
          if (label.isEmpty) label = tg;
        }

        if (label != null && label.isNotEmpty) {
          setState(() {
            _actorNameCache[id] = label!;
          });
        }
      } catch (_) {
        // ignore
      } finally {
        _actorNameLoading.remove(id);
      }
    }();

    return null;
  }

  bool _isVisibleToUser(Map<String, dynamic> e) {
    final uid = widget.currentUserId?.toString();

    // If not provided, do not filter here (assume source already filtered)
    if (uid == null || uid.isEmpty) return true;

    final entryUserId = e['user_id']?.toString();
    final vis = e['visible_role']?.toString();

    // 1) User events: only own rows
    if (entryUserId == uid) return true;

    // 2) Common events: only explicit "all" + allowed types
    if (vis == 'all' && _isAllowedCommonEvent(e)) return true;

    // IMPORTANT: do NOT treat NULL visible_role as visible (prevents leakage)
    return false;
  }

  /// Filter out any events related to color bank updates.
  bool _isBlockedEntry(Map<String, dynamic> e) {
    final t = (e['title'] ?? '').toString().toLowerCase();
    final m = (e['message'] ?? '').toString().toLowerCase();
    final meta = (e['metadata'] ?? '').toString().toLowerCase();

    // Most common keywords that appear in your journal for that table
    const needles = [
      'color_banks',
      'color_bank',
      'color banks',
      'банк цвета',
      'банки цвета',
    ];

    for (final n in needles) {
      if (t.contains(n) || m.contains(n) || meta.contains(n)) return true;
    }
    return false;
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
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Заголовок'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: msg,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Сообщение'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              final t = title.text.trim();
              final m = msg.text.trim();
              if (t.isEmpty && m.isEmpty) return;
              widget.onAddEntry?.call(t, m);
              Navigator.of(ctx).pop();
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    title.dispose();
    msg.dispose();
  }

  Future<void> _editEntry(Map<String, dynamic> entry) async {
    final tCtrl = TextEditingController(text: (entry['title'] ?? '').toString());
    final mCtrl =
        TextEditingController(text: (entry['message'] ?? '').toString());
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Редактировать запись'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: tCtrl,
              decoration: const InputDecoration(labelText: 'Заголовок'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: mCtrl,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Сообщение'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              final newEntry = Map<String, dynamic>.from(entry);
              newEntry['title'] = tCtrl.text.trim();
              newEntry['message'] = mCtrl.text.trim();
              widget.onEditEntry?.call(newEntry);

              // update local list to reflect changes immediately
              final id = (entry['id'] ?? '').toString();
              if (id.isNotEmpty) {
                setState(() {
                  final idx = _items.indexWhere(
                      (e) => (e['id'] ?? '').toString() == id);
                  if (idx >= 0) _items[idx] = newEntry;
                });
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    tCtrl.dispose();
    mCtrl.dispose();
  }

  Future<void> _deleteEntry(Map<String, dynamic> entry) async {
    final id = (entry['id'] ?? '').toString();
    if (id.isEmpty) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить запись?'),
        content: const Text('Действие необратимо.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              widget.onDeleteEntry?.call(id);
              setState(() =>
                  _items.removeWhere((e) => (e['id'] ?? '').toString() == id));
              Navigator.of(ctx).pop();
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();

    // Apply:
    // 1) visibility filter (own + allowed common)
    // 2) blocked filter (color_banks)
    // 3) search filter
    final filtered = <Map<String, dynamic>>[];
    for (final e in _items) {
      if (!_isVisibleToUser(e)) continue;
      if (_isBlockedEntry(e)) continue;

      final t = (e['title'] ?? '').toString().toLowerCase();
      final m = (e['message'] ?? '').toString().toLowerCase();
      final meta = (e['metadata'] ?? '').toString().toLowerCase();

      if (q.isNotEmpty) {
        if (!t.contains(q) && !m.contains(q) && !meta.contains(q)) continue;
      }
      filtered.add(e);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header row
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Поиск в журнале…',
                  hintStyle: TextStyle(
                    color: TitanicTheme.ivoryCream.withOpacity(0.6),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: TitanicTheme.raptureGold.withOpacity(0.9),
                  ),
                  filled: true,
                  fillColor: TitanicTheme.surfaceNavy.withOpacity(0.6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: TitanicTheme.raptureGold.withOpacity(0.25),
                      width: 1,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: TitanicTheme.raptureGold.withOpacity(0.18),
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: TitanicTheme.raptureGold.withOpacity(0.6),
                      width: 1.5,
                    ),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            if (widget.onAddEntry != null)
              SizedBox(
                height: 48,
                child: ArtDecoButton(
                  text: '',
                  icon: Icons.add,
                  onPressed: _showAddDialog,
                  primary: true,
                  width: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'Нет событий для отображения',
                    style: TitanicTheme.body.copyWith(
                      color: TitanicTheme.ivoryCream.withOpacity(0.75),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final entry = filtered[i];
                    final key = _entryKey(entry, i);

                    final isExp = _expanded[key] ?? false;
                    final isUnread =
                        _seenLoaded ? !_seenKeys.contains(key) : false;

                    final title = (entry['title'] ?? '').toString();
                    final msgRaw = (entry['message'] ?? '').toString();
                    final created = _formatDate(entry['created_at']);
                    final actorId = entry['actor_id']?.toString();

                    final bool isSpeech = _looksLikeSpeechEvent(entry);
                    final bool isTrade = _looksLikeTradeOffer(entry);
                    final actorLabel =
                        (isSpeech || isTrade) ? _ensureActorLabel(actorId) : null;

                    String msg = msgRaw;
                    if (isSpeech) {
                      // Keep message short and explicit for the common feed.
                      if (msg.trim().isEmpty ||
                          msg.toLowerCase().contains('измен')) {
                        msg = 'Активирована речь жизни';
                      }
                      if (actorLabel != null &&
                          actorLabel.isNotEmpty &&
                          !msg.toLowerCase().contains('инициатор')) {
                        msg = '$msg\nИнициатор: $actorLabel';
                      } else if (actorLabel == null &&
                          actorId != null &&
                          actorId!.isNotEmpty &&
                          !msg.toLowerCase().contains('инициатор')) {
                        msg = '$msg\nИнициатор: …';
                      }
                    } else if (isTrade) {
                      // Optional: show who offers the trade if we can resolve it.
                      if (actorLabel != null &&
                          actorLabel.isNotEmpty &&
                          !msg.toLowerCase().contains('от')) {
                        msg = '$msg\nОт: $actorLabel';
                      }
                    }

                    final leadingLetter =
                        title.isNotEmpty ? title[0].toUpperCase() : '?';

                    // Unread highlight: subtle glow + stronger border
                    final wrapperDecoration = BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: isUnread
                          ? [
                              BoxShadow(
                                color: TitanicTheme.raptureGold.withOpacity(0.18),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ]
                          : const [],
                    );

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: wrapperDecoration,
                      child: Stack(
                        children: [
                          ArtDecoCard(
                            title: title.isEmpty ? 'Без заголовка' : title,
                            subtitle: created,
                            leading: Stack(
                              children: [
                                CircleAvatar(
                                  backgroundColor:
                                      TitanicTheme.deepTeal.withOpacity(0.4),
                                  child: Text(leadingLetter),
                                ),
                                if (isUnread)
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: TitanicTheme.raptureGold,
                                        border: Border.all(
                                          color: TitanicTheme.panelDark
                                              .withOpacity(0.9),
                                          width: 1.2,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            trailing: IconButton(
                              icon: Icon(
                                isExp ? Icons.expand_less : Icons.expand_more,
                                color: TitanicTheme.raptureGold,
                              ),
                              onPressed: () {
                                setState(() {
                                  _expanded[key] = !isExp;
                                });
                                // mark as seen when user expands
                                _markSeen(key);
                              },
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AnimatedCrossFade(
                                  firstChild: Text(
                                    msg.length > 180
                                        ? '${msg.substring(0, 180)}…'
                                        : msg,
                                    style: TitanicTheme.body,
                                  ),
                                  secondChild: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(msg, style: TitanicTheme.body),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          TextButton.icon(
                                            onPressed: widget.onEditEntry == null
                                                ? null
                                                : () => _editEntry(entry),
                                            icon: const Icon(Icons.edit),
                                            label: const Text('Изменить'),
                                          ),
                                          const SizedBox(width: 8),
                                          TextButton.icon(
                                            onPressed:
                                                widget.onDeleteEntry == null
                                                    ? null
                                                    : () => _deleteEntry(entry),
                                            icon: const Icon(Icons.delete),
                                            label: const Text('Удалить'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  crossFadeState: isExp
                                      ? CrossFadeState.showSecond
                                      : CrossFadeState.showFirst,
                                  duration: const Duration(milliseconds: 220),
                                ),
                              ],
                            ),
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
}
