import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/widgets/art_deco_button.dart';

Future<Map<String, dynamic>> fetchHonorState(String userId) async {
  final supabase = Supabase.instance.client;
  try {
    final row = await supabase
        .from('user_credentials')
        .select('m_balance, used_honor_article')
        .eq('id', userId)
        .maybeSingle();

    if (row is Map<String, dynamic>) {
      final mb = row['m_balance'];
      double parsedM = 0.0;
      if (mb is num) parsedM = mb.toDouble();
      else if (mb is String) {
        parsedM = double.tryParse(mb.replaceAll(',', '.')) ?? 0.0;
      }

      final usedFlag = row['used_honor_article'];
      final bool used = (usedFlag == true) || 
          (usedFlag?.toString().toLowerCase() == 'true');

      return {'m_balance': parsedM, 'used': used};
    } else {
      return {'m_balance': 0.0, 'used': false};
    }
  } catch (_) {
    return {'m_balance': 0.0, 'used': false};
  }
}

Future<void> showHonorArticleDialog(
  BuildContext context,
  String userId, {
  Future<void> Function()? onPublished,
}) async {
  final supabase = Supabase.instance.client;
  final state = await fetchHonorState(userId);
  final double mBalance = state['m_balance'] as double? ?? 0.0;
  final bool used = state['used'] as bool? ?? false;

  if (used) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Статья Чести уже использована'))
    );
    return;
  }

  final ctrl = TextEditingController();
  
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Статья Чести'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Ваш доступный M: ${mBalance.toStringAsFixed(2)}'),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Сумма M'),
          ),
          const SizedBox(height: 8),
          const Text('Введите целую сумму, если вы введёте не целое число, оно округлится!'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Отмена'),
        ),
        ArtDecoButton(
          text: 'Подтвердить',
          onPressed: () => Navigator.of(ctx).pop(true),
          primary: true,
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  final raw = ctrl.text.trim().replaceAll(',', '.');
  final amountDouble = double.tryParse(raw) ?? 0.0;
  
  if (amountDouble <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Введите корректную сумму'))
    );
    return;
  }

  final intAmount = amountDouble.toInt();
  if (intAmount <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Сумма слишком мала после округления'))
    );
    return;
  }
  
  if (intAmount > mBalance.floor()) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Недостаточно M'))
    );
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Отправка...'))
  );

  try {
    final res = await supabase.rpc(
      'publish_article',
      params: {'p_user': userId, 'p_amount': intAmount},
    );
    
    Map<String, dynamic>? parsed;
    if (res is Map<String, dynamic>) parsed = res;
    else if (res is List && res.isNotEmpty && res[0] is Map) {
      parsed = Map<String, dynamic>.from(res[0]);
    } else if (res is String) {
      try {
        parsed = Map<String, dynamic>.from(jsonDecode(res) as Map);
      } catch (_) {
        parsed = null;
      }
    }

    if (parsed != null && (parsed['status'] == 'ok' || parsed['status'] == 'OK')) {
      final added = parsed['added_m'] ?? intAmount;
      final color = parsed['color'] ?? '';
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Статья опубликована — $added M в банк цвета $color')
        )
      );
      
      if (onPublished != null) {
        try {
          await onPublished();
        } catch (_) {}
      }
    } else {
      final msg = parsed != null 
          ? (parsed['message'] ?? parsed.toString()) 
          : 'Неожиданный ответ от сервера';
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $msg'))
      );
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ошибка RPC: $e'))
    );
  }
}

class JournalistBlock extends StatefulWidget {
  final String currentUserId;
  final Future<void> Function()? onPublished;

  const JournalistBlock({
    super.key,
    required this.currentUserId,
    this.onPublished,
  });

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
    if (widget.currentUserId.isEmpty) {
      debugPrint('JournalistBlock: currentUserId is empty');
      setState(() {
        _usedAlready = true;
        _mBalance = 0.0;
      });
      return;
    }

    setState(() => _loading = true);
    
    try {
      final row = await supabase
          .from('user_credentials')
          .select('m_balance, used_honor_article, role')
          .eq('id', widget.currentUserId)
          .maybeSingle();

      debugPrint('JournalistBlock: _loadState row -> $row');

      if (row is Map<String, dynamic>) {
        final roleRaw = row['role'];
        final roleStr = (roleRaw == null) 
            ? '' 
            : roleRaw.toString().toLowerCase().trim();

        final bool isJournalist = roleStr == 'journalist' || 
            roleStr == 'журналист' || 
            roleStr.contains('journal');

        if (!isJournalist) {
          setState(() {
            _usedAlready = true;
            _mBalance = 0.0;
          });
        } else {
          final mb = row['m_balance'];
          double parsedM = 0.0;
          try {
            if (mb is num) parsedM = mb.toDouble();
            else if (mb is String) {
              parsedM = double.tryParse(mb.replaceAll(',', '.')) ?? 0.0;
            } else parsedM = 0.0;
          } catch (_) {
            parsedM = 0.0;
          }

          final usedFlag = row['used_honor_article'];
          final bool used = (usedFlag == true) || 
              (usedFlag?.toString().toLowerCase() == 'true');

          setState(() {
            _mBalance = parsedM;
            _usedAlready = used;
          });
        }
      } else {
        debugPrint('JournalistBlock: user row not found for id=${widget.currentUserId}');
        setState(() {
          _usedAlready = true;
          _mBalance = 0.0;
        });
      }
    } catch (e) {
      debugPrint('JournalistBlock: _loadState error -> $e');
      setState(() {
        _usedAlready = true;
        _mBalance = 0.0;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onPublishPressed() async {
    if (_usedAlready) return;

    await showHonorArticleDialog(
      context,
      widget.currentUserId,
      onPublished: () async {
        await _loadState();
        if (widget.onPublished != null) await widget.onPublished!();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: ArtDecoButton(
            text: 'Дебаты / Публикации',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Дебаты / Публикации'))
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ArtDecoButton(
            text: _loading 
                ? 'Загрузка...' 
                : (_usedAlready 
                    ? 'Статья Чести — использовано' 
                    : 'Статья Чести'),
            onPressed: (_loading || _usedAlready) ? null : _onPublishPressed,
            loading: _loading,
            primary: !_usedAlready,
          ),
        ),
      ],
    );
  }
}