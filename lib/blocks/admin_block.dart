// lib/admin_block.dart
import 'package:flutter/material.dart';

class AdminBlock extends StatelessWidget {
  final Future<void> Function()? onRefresh;
  final void Function(String label)? onAction;

  const AdminBlock({Key? key, this.onRefresh, this.onAction}) : super(key: key);

  void _call(String label) {
    if (onAction != null) onAction!(label);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: () => _call('Админ-панель'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.black87),
          child: const Text('Админ-панель'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(onPressed: () => _call('Пополнить V/M'), child: const Text('Пополнить V/M')),
        const SizedBox(height: 8),
        ElevatedButton(onPressed: () => _call('Создать опрос'), child: const Text('Создать опрос')),
        const SizedBox(height: 8),
        ElevatedButton(onPressed: () => _call('Создать аукцион'), child: const Text('Создать аукцион')),
        const SizedBox(height: 8),
        ElevatedButton(onPressed: () => _call('Статистика цветов'), child: const Text('Статистика цветов')),
      ],
    );
  }
}
