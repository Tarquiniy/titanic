
/*
  Дополнительно: пример простого контроллера инвентаря и экрана для мгновенного отображения добавленного предмета.
  Файл: lib/widgets/inventory_controller_and_screen.dart
*/

// lib/widgets/inventory_controller_and_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Простой контроллер инвентаря, который может быть разделяем между экраном инвентаря и точкой добавления предметов.
class InventoryController {
  final ValueNotifier<List<Map<String, dynamic>>> _items = ValueNotifier<List<Map<String, dynamic>>>([]);

  InventoryController([List<Map<String, dynamic>>? initial]) {
    if (initial != null) _items.value = List.from(initial);
  }

  ValueListenable<List<Map<String, dynamic>>> get itemsListenable => _items;

  void addItem(Map<String, dynamic> item) {
    _items.value = [item, ..._items.value];
  }

  List<Map<String, dynamic>> get snapshot => List.unmodifiable(_items.value);
}

/// Экран инвентаря, использующий InventoryController.
class InventoryScreen extends StatelessWidget {
  final InventoryController controller;

  const InventoryScreen({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Инвентарь')),
      body: ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: controller.itemsListenable,
        builder: (context, items, _) {
          if (items.isEmpty) return const Center(child: Text('Пусто'));
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, index) {
              final it = items[index];
              final name = it['name'] ?? 'Предмет';
              final created = it['created_at'] ?? '';
              final meta = it['metadata'] ?? {};
              return ListTile(
                title: Text(name.toString()),
                subtitle: Text('От: ${meta['from'] ?? ''} • ${created.toString()}'),
              );
            },
          );
        },
      ),
    );
  }
}

