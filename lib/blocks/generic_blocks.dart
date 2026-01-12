// lib/blocks/generic_blocks.dart
import 'package:flutter/material.dart';

class EconomistBlock extends StatelessWidget {
  final VoidCallback? onAnalytics;
  const EconomistBlock({super.key, this.onAnalytics});
  @override
  Widget build(BuildContext context) => ElevatedButton(onPressed: onAnalytics, child: const Text('Аналитика / Ставки'));
}

class HollywoodBlock extends StatelessWidget {
  final VoidCallback? onOpen;
  const HollywoodBlock({super.key, this.onOpen});
  @override
  Widget build(BuildContext context) => ElevatedButton(onPressed: onOpen, child: const Text('Контент / Ставки'));
}

class MafiaBlock extends StatelessWidget {
  final VoidCallback? onManage;
  const MafiaBlock({super.key, this.onManage});
  @override
  Widget build(BuildContext context) => ElevatedButton(onPressed: onManage, child: const Text('Управление предприятиями'));
}

class PublicFigureBlock extends StatelessWidget {
  final VoidCallback? onOpen;
  const PublicFigureBlock({super.key, this.onOpen});
  @override
  Widget build(BuildContext context) => ElevatedButton(onPressed: onOpen, child: const Text('События / Прослушал'));
}

class AdminBlock extends StatelessWidget {
  final Future<void> Function()? onRefresh;
  final void Function(String label)? onAction;
  const AdminBlock({super.key, this.onRefresh, this.onAction});

  void _call(String label) {
    if (onAction != null) onAction!(label);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ElevatedButton(onPressed: () => _call('Админ-панель'), style: ElevatedButton.styleFrom(backgroundColor: Colors.black87), child: const Text('Админ-панель')),
      const SizedBox(height: 8),
      ElevatedButton(onPressed: () => _call('Пополнить V/M'), child: const Text('Пополнить V/M')),
      const SizedBox(height: 8),
      ElevatedButton(onPressed: () => _call('Создать опрос'), child: const Text('Создать опрос')),
      const SizedBox(height: 8),
      ElevatedButton(onPressed: () => _call('Создать аукцион'), child: const Text('Создать аукцион')),
      const SizedBox(height: 8),
      ElevatedButton(onPressed: () => _call('Статистика цветов'), child: const Text('Статистика цветов')),
    ]);
  }
}
