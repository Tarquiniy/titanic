// lib/blocks/journalist_block.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class JournalistBlock extends StatefulWidget {
  final String currentUserId;
  final Future<void> Function()? onPublished;

  const JournalistBlock({super.key, required this.currentUserId, this.onPublished});

  @override
  State<JournalistBlock> createState() => _JournalistBlockState();
}

class _JournalistBlockState extends State<JournalistBlock> {
  final supabase = Supabase.instance.client;
  bool _loading = false;
  bool _usedAlready = false;
  double _mBalance = 0.0;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    setState(() => _loading = true);
    try {
      final row = await supabase.from('user_credentials').select('m_balance, used_honor_article, role').eq('id', widget.currentUserId).maybeSingle();
      if (row is Map<String, dynamic>) {
        final role = row['role'] as String?;
        if (role != 'journalist') {
          setState(() {
            _usedAlready = true;
            _mBalance = 0.0;
          });
        } else {
          _mBalance = (row['m_balance'] is num) ? (row['m_balance'] as num).toDouble() : 0.0;
          _usedAlready = (row['used_honor_article'] == true);
        }
      } else {
        _usedAlready = false;
        _mBalance = 0.0;
      }
    } catch (_) {
      _usedAlready = false;
      _mBalance = 0.0;
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _onPublishPressed() async {
    if (_usedAlready) return;
    await _loadState();
    if (_usedAlready) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вы уже использовали Статью Чести.')));
      return;
    }

    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Статья Чести'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Ваш доступный M: ${_mBalance.toStringAsFixed(2)}'),
          const SizedBox(height: 8),
          TextField(controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Сумма M')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')), ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Подтвердить'))],
      ),
    );

    if (confirmed != true) return;
    final raw = ctrl.text.trim().replaceAll(',', '.');
    final amount = double.tryParse(raw) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите корректную сумму')));
      return;
    }
    if (amount > _mBalance) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Недостаточно M')));
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await supabase.rpc('publish_article', params: {'p_user': widget.currentUserId, 'p_amount': amount});
      Map<String, dynamic>? parsed;
      if (res is Map<String, dynamic>) parsed = res;
      else if (res is List && res.isNotEmpty && res[0] is Map) parsed = Map<String, dynamic>.from(res[0]);
      else if (res is String) {
        try {
          parsed = Map<String, dynamic>.from(jsonDecode(res) as Map);
        } catch (_) {
          parsed = null;
        }
      }

      if (parsed != null && (parsed['status'] == 'ok' || parsed['status'] == 'OK')) {
        final added = parsed['added_m'] ?? amount;
        final color = parsed['color'] ?? '';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Статья опубликована — $added M в банк цвета $color')));
        setState(() => _usedAlready = true);
        if (widget.onPublished != null) await widget.onPublished!();
      } else {
        final msg = parsed != null ? (parsed['message'] ?? parsed.toString()) : 'Неожиданный ответ';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $msg')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Дебаты / Публикации'))), child: const Text('Дебаты / Публикации'))),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: (_loading || _usedAlready) ? null : _onPublishPressed,
          style: ElevatedButton.styleFrom(backgroundColor: _usedAlready ? Colors.grey : Colors.purple),
          child: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_usedAlready ? 'Статья Чести — использовано' : 'Статья Чести'),
        ),
      ),
    ]);
  }
}
