import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Сервис для управления предприятиями.
/// Автоматически обновляет цвет всех предприятий экономиста при смене его цвета.
class EnterpriseService {
  final SupabaseClient supabase;

  EnterpriseService(this.supabase);

  /// Обновляет цвет всех предприятий, построенных экономистом [economistId],
  /// на [newColor]. Возвращает количество обновлённых записей.
  /// Если пользователь не является экономистом – ничего не делает.
  Future<int> updateEnterprisesColorForEconomist({
    required String economistId,
    required String newColor,
  }) async {
    // 1. Проверяем, что пользователь – экономист
    final userRes = await supabase
        .from('user_credentials')
        .select('role')
        .eq('id', economistId)
        .maybeSingle();

    if (userRes == null) return 0;
    final role = (userRes['role'] ?? '').toString().toLowerCase();
    if (role != 'economist' && role != 'экономист') {
      return 0; // Не экономист – выходим
    }

    // 2. Формируем JSON-фильтр для поиска инвентарей, содержащих предприятия этого экономиста
    final filter = [
      {
        'type': 'enterprise',
        'builder_id': economistId,
      }
    ];
    final filterJson = jsonEncode(filter);

    // 3. Ищем всех пользователей, у которых в инвентаре есть предприятия с builder_id = economistId
    final response = await supabase
        .from('user_credentials')
        .select('id, inventory')
        .filter('inventory', 'cs', filterJson); // 'cs' – оператор @> (contains)

    if (response is! List) return 0;

    int updatedCount = 0;

    for (final row in response) {
      final userId = row['id'] as String;
      dynamic inventory = row['inventory'];

      // Парсим инвентарь
      List<dynamic> inventoryList = [];
      if (inventory == null) {
        continue;
      } else if (inventory is String) {
        try {
          inventoryList = jsonDecode(inventory) as List;
        } catch (_) {
          continue;
        }
      } else if (inventory is List) {
        inventoryList = List.from(inventory);
      } else {
        continue;
      }

      bool modified = false;
      for (final item in inventoryList) {
        if (item is Map) {
          // Находим предприятия этого экономиста (по builder_id)
          if (item['type'] == 'enterprise' && item['builder_id'] == economistId) {
            // Обновляем цвет – поддерживаем оба формата
            if (item.containsKey('meta') && item['meta'] is Map) {
              // Новый формат: цвет в meta['color']
              item['meta']['color'] = newColor;
              modified = true;
            } else if (item.containsKey('color')) {
              // Старый формат: цвет на верхнем уровне
              item['color'] = newColor;
              modified = true;
            }
          }
        }
      }

      if (modified) {
        // Сохраняем изменённый инвентарь
        await supabase
            .from('user_credentials')
            .update({'inventory': inventoryList})
            .eq('id', userId);
        updatedCount++;
      }
    }

    return updatedCount;
  }
}