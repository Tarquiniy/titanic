// lib/screens/pay_movie_screen.dart
// Экран: Оплатить фильм (стоимость 100 M)
// Сохраняет в таблицу `movies`:
//  - title
//  - creator_id
//  - director_id, director_name
//  - writer_id, writer_name
//  - actor_ids (uuid[]), actor_names (text[])
//  - price, metadata

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/services/shared_balance_service.dart';

class PayMovieScreen extends StatefulWidget {
  final String currentUserId;
  const PayMovieScreen({Key? key, required this.currentUserId}) : super(key: key);

  @override
  State<PayMovieScreen> createState() => _PayMovieScreenState();
}

class _PayMovieScreenState extends State<PayMovieScreen> {
  final supabase = Supabase.instance.client;
  final SharedBalanceService _sharedBalance = SharedBalanceService();
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleCtrl = TextEditingController();

  List<Map<String, dynamic>> _hollywoodUsers = []; // each: id, first_name, last_name, telegram_username, role
  String? _directorId;
  String? _writerId;
  final List<String?> _actorIds = [null]; // dynamic up to 5 (nullable)

  bool _loading = false;
  bool _loadingUsers = true;
  String? _error;

  static const int price = 1; // стоимость в "M"

  @override
  void initState() {
    super.initState();
    _loadHollywoodUsers();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHollywoodUsers() async {
    setState(() {
      _loadingUsers = true;
    });
    try {
      final res = await supabase.from('user_credentials').select('id, telegram_username, first_name, last_name, role').order('first_name');
      final List<Map<String, dynamic>> list = [];
      if (res is List) {
        for (final e in res) {
          final row = Map<String, dynamic>.from(e as Map);
          final roleRaw = (row['role'] ?? '').toString().toLowerCase();
          if (roleRaw.contains('голливуд') || roleRaw.contains('hollywood')) {
            list.add(row);
          }
        }
      }
      setState(() {
        _hollywoodUsers = list;
      });
    } catch (e) {
      debugPrint('PayMovieScreen._loadHollywoodUsers error: $e');
      setState(() {
        _hollywoodUsers = [];
      });
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  String _displayNameFromRow(Map<String, dynamic> u) {
    final fn = (u['first_name'] ?? '').toString().trim();
    final ln = (u['last_name'] ?? '').toString().trim();
    final un = (u['telegram_username'] ?? '').toString().trim();
    if (fn.isEmpty && ln.isEmpty) return un.isNotEmpty ? un : (u['id']?.toString() ?? '—');
    final combined = '${fn}${fn.isNotEmpty && ln.isNotEmpty ? ' ' : ''}$ln'.trim();
    return combined.isNotEmpty ? combined : (un.isNotEmpty ? un : (u['id']?.toString() ?? '—'));
  }

  // Helper: given userId, find display name in _hollywoodUsers (fallback to id)
  String _displayNameById(String? id) {
    if (id == null) return '';
    try {
      final found = _hollywoodUsers.firstWhere((u) => u['id']?.toString() == id, orElse: () => {});
      if (found.isNotEmpty) return _displayNameFromRow(found);
      return id;
    } catch (_) {
      return id;
    }
  }

  Future<void> _addActorSlot() async {
    if (_actorIds.length >= 5) return;
    setState(() => _actorIds.add(null));
  }

  void _removeActorSlot(int idx) {
    if (_actorIds.length <= 1) return;
    setState(() => _actorIds.removeAt(idx));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final title = _titleCtrl.text.trim();
    final director = _directorId;
    final writer = _writerId;
    final actors = _actorIds.where((e) => e != null && e!.isNotEmpty).map((e) => e!).toList();

    if (director == null || director.isEmpty) {
      _showSnack('Выберите режиссёра');
      setState(() => _loading = false);
      return;
    }
    if (writer == null || writer.isEmpty) {
      _showSnack('Выберите сценариста');
      setState(() => _loading = false);
      return;
    }

    try {
      await _sharedBalance.normalizeLinkedBalanceForSpend(
        userId: widget.currentUserId,
        balanceKey: 'm_balance',
      );
      // fetch current m_balance
      final fresh = await supabase.from('user_credentials').select('m_balance').eq('id', widget.currentUserId).maybeSingle();
      double currentBalance = 0.0;
      if (fresh is Map<String, dynamic> && fresh.containsKey('m_balance')) {
        final vb = fresh['m_balance'];
        if (vb is num) currentBalance = vb.toDouble();
        else if (vb is String) currentBalance = double.tryParse(vb.replaceAll(',', '.')) ?? 0.0;
      } else {
        _showSnack('Профиль не найден');
        setState(() => _loading = false);
        return;
      }

      if (currentBalance < price) {
        _showSnack('Недостаточно M: требуется $price, у вас ${currentBalance.toStringAsFixed(2)}');
        setState(() => _loading = false);
        return;
      }

      // attempt atomic update (only if m_balance >= price)
      final newBalance = (currentBalance - price).clamp(0, double.infinity);
      final upd = await supabase
          .from('user_credentials')
          .update({'m_balance': newBalance})
          .eq('id', widget.currentUserId)
          .gte('m_balance', price)
          .select()
          .maybeSingle();

      if (upd == null) {
        // failed to update (likely insufficient funds / race)
        _showSnack('Не удалось списать M — возможно, недостаточно средств. Попробуйте снова.');
        setState(() => _loading = false);
        return;
      }

      await _sharedBalance.syncLinkedBalancesForUser(
        userId: widget.currentUserId,
        sourceUserId: widget.currentUserId,
      );

      // Prepare name fields
      final directorName = _displayNameById(director);
      final writerName = _displayNameById(writer);
      final actorNames = actors.map((aid) => _displayNameById(aid)).toList();

      // После успешного списания — вставляем запись в таблицу movies
      final Map<String, dynamic> movieRow = {
        'title': title,
        'creator_id': widget.currentUserId,
        'director_id': director,
        'director_name': directorName,
        'writer_id': writer,
        'writer_name': writerName,
        // actor_ids ожидает массив UUID'ов; Supabase/PostgREST принимает список строк
        'actor_ids': actors,
        'actor_names': actorNames,
        'price': price,
        'metadata': {}, // при желании можно положить JSON с доп.инфой
      };

      try {
        // вставляем и просим вернуть вставленную строку (id и created_at)
        final inserted = await supabase.from('movies').insert(movieRow).select().maybeSingle();

        if (inserted == null) {
          // insertion failed silently — попытка отката
          debugPrint('PayMovieScreen: insert returned null (no inserted row). Attempting rollback.');
          await _attemptRollback(widget.currentUserId, currentBalance);
          _showSnack('Ошибка сохранения фильма — операция отменена.');
          setState(() => _loading = false);
          return;
        }

        // Вставка успешна — option: добавить запись в purchased_movies для истории
        try {
          await supabase.from('purchased_movies').insert({
            'movie_id': inserted['id'],
            'purchaser_id': widget.currentUserId,
            'price': price,
            'metadata': {},
          });
        } catch (e) {
          // не критично — логируем
          debugPrint('PayMovieScreen: failed to insert purchased_movies -> $e');
        }

        _showSnack('Фильм оплачен и сохранён (100 M).');
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } catch (e) {
        // insertion threw error — попытка отката списания
        debugPrint('PayMovieScreen: insert error -> $e');
        final rolled = await _attemptRollback(widget.currentUserId, currentBalance);
        if (rolled) {
          _showSnack('Ошибка при сохранении фильма — списание отменено.');
        } else {
          _showSnack('Ошибка при сохранении фильма. Попытка отката не удалась — обратитесь к администратору.');
        }
        setState(() => _loading = false);
        return;
      }
    } catch (e) {
      debugPrint('PayMovieScreen._submit error: $e');
      _showSnack('Ошибка при оплате: $e');
      setState(() => _loading = false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _attemptRollback(String userId, double previousBalance) async {
    try {
      // best-effort: вернуть старый баланс
      await supabase.from('user_credentials').update({'m_balance': previousBalance}).eq('id', userId);
      await _sharedBalance.syncLinkedBalancesForUser(
        userId: userId,
        sourceUserId: userId,
      );
      return true;
    } catch (e) {
      debugPrint('PayMovieScreen._attemptRollback failed: $e');
      return false;
    }
  }

  void _showSnack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Widget _buildUserDropdown({
    required String? value,
    required ValueChanged<String?> onChanged,
    required String hint,
  }) {
    final items = _hollywoodUsers.map((u) {
      return DropdownMenuItem<String>(value: u['id']?.toString(), child: Text(_displayNameFromRow(u)));
    }).toList();
    return DropdownButtonFormField<String>(
      value: value,
      items: items,
      onChanged: onChanged,
      validator: (v) => (v == null || v.isEmpty) ? 'Выберите $hint' : null,
      decoration: InputDecoration(labelText: hint),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Оплатить фильм (100 M)'),
      ),
      body: _loadingUsers
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(labelText: 'Название фильма'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Введите название фильма' : null,
                    ),
                    const SizedBox(height: 12),
                    _buildUserDropdown(value: _directorId, onChanged: (v) => setState(() => _directorId = v), hint: 'Режиссёр'),
                    const SizedBox(height: 12),
                    _buildUserDropdown(value: _writerId, onChanged: (v) => setState(() => _writerId = v), hint: 'Сценарист'),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Актёры (до 5)'),
                        TextButton(
                          onPressed: _actorIds.length >= 5 ? null : _addActorSlot,
                          child: const Text('Добавить актёра'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._actorIds.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final cur = entry.value;
                      // prepare options with a leading "— не выбран —"
                      final options = _hollywoodUsers
                          .map((u) => DropdownMenuItem<String?>(value: u['id']?.toString(), child: Text(_displayNameFromRow(u))))
                          .toList();
                      final List<DropdownMenuItem<String?>> itemsWithEmpty = [
                        const DropdownMenuItem<String?>(value: null, child: Text('— не выбран —')),
                        ...options,
                      ];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String?>(
                                value: cur,
                                items: itemsWithEmpty,
                                onChanged: (v) => setState(() => _actorIds[idx] = v),
                                decoration: InputDecoration(labelText: 'Актёр ${idx + 1}'),
                                validator: (_) => null, // actors optional
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_actorIds.length > 1)
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _removeActorSlot(idx),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 18),
                    _loading
                        ? const CircularProgressIndicator()
                        : SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _submit,
                              child: const Text('Подтвердить оплату (100 M)'),
                            ),
                          ),
                    const SizedBox(height: 12),
                    if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ),
    );
  }
}
