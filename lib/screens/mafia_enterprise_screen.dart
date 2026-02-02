// lib/screens/mafia_enterprise_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MafiaEnterpriseScreen extends StatefulWidget {
  final String mafiaUserId;
  final Future<void> Function()? onSuccess;

  const MafiaEnterpriseScreen({
    Key? key,
    required this.mafiaUserId,
    this.onSuccess,
  }) : super(key: key);

  @override
  State<MafiaEnterpriseScreen> createState() => _MafiaEnterpriseScreenState();
}

class _MafiaEnterpriseScreenState extends State<MafiaEnterpriseScreen> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameCtrl = TextEditingController();
  String? _selectedColor;
  String? _selectedRegion;

  bool _loading = false;

  // Список цветов для выбора
  final Map<String, String> _colorOptions = {
    'красный': '#F44336',
    'зелёный': '#4CAF50',
    'синий': '#2196F3',
    'малиновый': '#E91E63',
    'жёлтый': '#FFC107',
  };

  // Список регионов
  final List<String> _regionOptions = [
    'Азиатская группа',
    'Англа-саксонская группа',
    'Предсоциалистический блок',
    'Пиренейская группа',
    'Центрально-европейская группа',
  ];

  Future<void> _buyEnterprise() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack('Введите название предприятия');
      return;
    }

    if (_selectedColor == null || _selectedColor!.isEmpty) {
      _showSnack('Выберите цвет предприятия');
      return;
    }

    if (_selectedRegion == null || _selectedRegion!.isEmpty) {
      _showSnack('Выберите регион предприятия');
      return;
    }

    // Сначала показываем диалог с вопросом
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Подтверждение'),
        content: const Text('А ты сходил в мерцалку и преуспел?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Да, преуспел!'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return; // Пользователь отменил
    }

    setState(() {
      _loading = true;
    });

    try {
      // 1. Получаем текущий инвентарь мафиози
      final userRow = await supabase
          .from('user_credentials')
          .select('inventory, first_name, last_name')
          .eq('id', widget.mafiaUserId)
          .maybeSingle();

      if (userRow is! Map<String, dynamic>) {
        _showSnack('Профиль мафиози не найден');
        setState(() => _loading = false);
        return;
      }

      dynamic inv = userRow['inventory'];
      List<dynamic> invList = [];

      // Парсим существующий инвентарь
      if (inv == null) {
        invList = [];
      } else if (inv is String) {
        try {
          final decoded = jsonDecode(inv);
          if (decoded is List) {
            invList = List.from(decoded);
          } else if (decoded is Map) {
            invList = [decoded];
          }
        } catch (_) {
          invList = [];
        }
      } else if (inv is List) {
        invList = List.from(inv);
      } else if (inv is Map) {
        invList = [inv];
      } else {
        invList = [];
      }

      // 2. Создаем новое предприятие
      final Map<String, dynamic> newEnterprise = {
        'type': 'enterprise',
        'name': name,
        'color': _selectedColor,
        'color_hex': _colorOptions[_selectedColor],
        'region': _selectedRegion,
        'owner_type': 'mafia',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'mafia_id': widget.mafiaUserId,
        'description': 'Приобретено мафией',
      };

      // 3. Добавляем предприятие в инвентарь
      invList.add(newEnterprise);

      // 4. Обновляем инвентарь в базе данных
      await supabase
          .from('user_credentials')
          .update({
            'inventory': invList,
          })
          .eq('id', widget.mafiaUserId);

      // 5. Добавляем запись в журнал
      final mafiaName = '${userRow['first_name'] ?? ''} ${userRow['last_name'] ?? ''}'.trim();
      final mafiaNameDisplay = mafiaName.isEmpty ? 'Мафиози ID: ${widget.mafiaUserId}' : mafiaName;

      await supabase.from('user_journal').insert({
        'user_id': widget.mafiaUserId,
        'visible_role': 'all',
        'actor_id': widget.mafiaUserId,
        'title': 'Новое предприятие мафии',
        'message': '$mafiaNameDisplay приобрел предприятие "$name" в регионе $_selectedRegion (цвет: $_selectedColor)',
        'metadata': {
          'enterprise_name': name,
          'color': _selectedColor,
          'region': _selectedRegion,
          'type': 'mafia_enterprise'
        },
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      _showSnack('Предприятие "$name" успешно добавлено в ваш инвентарь!');

      if (widget.onSuccess != null) {
        await widget.onSuccess!();
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('MafiaEnterpriseScreen._buyEnterprise error: $e');
      _showSnack('Ошибка при покупке предприятия: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Купить предприятие (мафия)'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Создание предприятия мафии',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Предприятие будет добавлено в ваш инвентарь. Стоимость отсутствует.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 24),

              // Название предприятия
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Название предприятия',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Введите название предприятия'
                    : null,
              ),
              const SizedBox(height: 16),

              // Выбор цвета
              DropdownButtonFormField<String>(
                value: _selectedColor,
                items: _colorOptions.keys.map((color) {
                  final hex = _colorOptions[color]!;
                  return DropdownMenuItem<String>(
                    value: color,
                    child: Row(
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: Color(int.parse('0xFF${hex.replaceFirst('#', '')}')),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: Colors.black12),
                          ),
                        ),
                        Text(color),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _selectedColor = value),
                decoration: const InputDecoration(
                  labelText: 'Цвет предприятия',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Выберите цвет предприятия'
                    : null,
              ),
              const SizedBox(height: 16),

              // Выбор региона
              DropdownButtonFormField<String>(
                value: _selectedRegion,
                items: _regionOptions.map((region) {
                  return DropdownMenuItem<String>(
                    value: region,
                    child: Text(region),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _selectedRegion = value),
                decoration: const InputDecoration(
                  labelText: 'Регион предприятия',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Выберите регион предприятия'
                    : null,
              ),

              const SizedBox(height: 32),

              // Кнопка покупки
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _buyEnterprise,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'КУПИТЬ ПРЕДПРИЯТИЕ',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}